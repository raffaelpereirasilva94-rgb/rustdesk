import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/desktop/widgets/mr_technician_chrome.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';

// Owned by window zero only. Other engines use restricted, credential-free IPC.
final _homeWindows = <int>{};
DateTime _lastPeerRefresh = DateTime.fromMillisecondsSinceEpoch(0);
bool _refreshingPeers = false;

bool isMrDeskHomeWindow(int id) => _homeWindows.contains(id);
bool isMrDeskHomeMethod(String method) => [
  mrDeskHomeOpenMethod, mrDeskHomeCloseMethod, mrDeskHomeSnapshotMethod,
  mrDeskHomeSettingsMethod,
].contains(method);

Future<bool> openMrDeskHomeWindow() async {
  if (bind.isIncomingOnly()) return false;
  WindowController? window;
  try {
    final created = await DesktopMultiWindow.createWindow(
        jsonEncode(mrDeskHomeWindowArguments()));
    window = created;
    _homeWindows.add(created.windowId);
    await rustDeskWinManager.registerActiveWindow(created.windowId);
    return true;
  } catch (e) {
    debugPrint('MR home window creation: $e');
    if (window != null) {
      _homeWindows.remove(window.windowId);
      await window.setPreventClose(false);
      await window.close();
      await rustDeskWinManager.unregisterActiveWindow(window.windowId);
    }
    return false;
  }
}

Future<List<MrDeskSession>> readMrDeskRemoteSessions() async {
  final ids = rustDeskWinManager.getActiveWindows()
      .where((id) => id != kMainWindowId && !isMrDeskHomeWindow(id)).toList();
  final groups = await Future.wait(ids.map((windowId) async {
    try {
      final raw = await DesktopMultiWindow.invokeMethod(
          windowId, mrDeskRemoteTabsMethod, null)
          .timeout(const Duration(seconds: 2));
      if (raw is! String) return <MrDeskSession>[];
      final peers = jsonDecode(raw);
      if (peers is! List) return <MrDeskSession>[];
      return peers.whereType<String>().where((id) => id.isNotEmpty)
          .map((id) => MrDeskSession(windowId, id)).toList();
    } catch (_) {
      return <MrDeskSession>[];
    }
  }));
  final current = rustDeskWinManager.getActiveWindows();
  return groups.expand((group) => group)
      .where((session) => current.contains(session.windowId)).toList();
}

List<Map<String, dynamic>> _peerSnapshot(List<Peer> peers) =>
    peers.take(1000).map((p) => <String, dynamic>{
      'id': p.id, 'hostname': p.hostname, 'alias': p.alias,
      'platform': p.platform, 'username': p.username,
      'online': p.online, 'forceAlwaysRelay': p.forceAlwaysRelay.toString(),
    }).toList();

Future<void> _refreshSharedPeers() async {
  if (_refreshingPeers ||
      DateTime.now().difference(_lastPeerRefresh) < const Duration(seconds: 6)) return;
  _refreshingPeers = true;
  try {
    final visible = gFFI.peerTabModel.isVisibleEnabled;
    if (visible[0]) bind.mainLoadRecentPeers();
    if (visible[1]) bind.mainLoadFavPeers();
    if (visible[2]) { bind.mainLoadLanPeers(); bind.mainDiscover(); }
    final publicServer = await bind.mainIsUsingPublicServer();
    if (publicServer &&
        DateTime.now().difference(_lastPeerRefresh) < const Duration(seconds: 20)) return;
    final ids = <String>{
      if (visible[0]) ...gFFI.recentPeersModel.peers.map((p) => p.id),
      if (visible[1]) ...gFFI.favoritePeersModel.peers.map((p) => p.id),
      if (visible[2]) ...gFFI.lanPeersModel.peers.map((p) => p.id),
    }..removeWhere((id) => id.isEmpty);
    _lastPeerRefresh = DateTime.now();
    if (ids.isNotEmpty) await bind.queryOnlines(ids: ids.take(1000).toList());
  } catch (e) {
    debugPrint('MR shared peers: $e');
  } finally {
    _refreshingPeers = false;
  }
}

Future<dynamic> handleMrDeskHomeMethod(MethodCall call, int fromWindowId) async {
  if (!isMrDeskHomeWindow(fromWindowId)) return null;
  if (call.method == mrDeskHomeCloseMethod) {
    _homeWindows.remove(fromWindowId);
    await rustDeskWinManager.unregisterActiveWindow(fromWindowId);
    return true;
  }
  if (bind.isIncomingOnly()) return false;
  switch (call.method) {
    case mrDeskHomeOpenMethod:
      return openMrDeskHomeWindow();
    case mrDeskHomeSettingsMethod:
      if (bind.isDisableSettings()) return false;
      await WindowController.main().show();
      await WindowController.main().focus();
      await rustDeskWinManager.registerActiveWindow(kMainWindowId);
      DesktopTabPage.onAddSetting();
      return true;
    case mrDeskHomeSnapshotMethod:
      // The native peer events go only to the original main engine.
      _refreshSharedPeers();
      final visible = gFFI.peerTabModel.isVisibleEnabled;
      final sessions = await readMrDeskRemoteSessions();
      return jsonEncode({
        'recent': visible[0] ? _peerSnapshot(gFFI.recentPeersModel.peers) : [],
        'favorites': visible[1] ? _peerSnapshot(gFFI.favoritePeersModel.peers) : [],
        'lan': visible[2] ? _peerSnapshot(gFFI.lanPeersModel.peers) : [],
        'sessions': sessions.map((s) =>
          {'windowId': s.windowId, 'peerId': s.peerId}).toList(),
      });
  }
  return null;
}

Future<void> showMrDeskMainSettings() async {
  try {
    await DesktopMultiWindow.invokeMethod(kMainWindowId, mrDeskHomeSettingsMethod, null);
  } catch (e) { debugPrint('MR settings: $e'); }
}

Future<void> closeMrDeskHomeWindow(int id) async {
  final controller = WindowController.fromWindowId(id);
  // Hide only this HWND. Do not close the native connection manager or peers.
  await controller.hide();
  try {
    // This channel is private to the home engine, never the main/remote stream.
    await bind.stopGlobalEventStream(appType: mrDeskHomeEventChannel(id));
  } catch (e) {
    debugPrint('MR home event cleanup: $e');
  }
  try {
    await DesktopMultiWindow.invokeMethod(kMainWindowId, mrDeskHomeCloseMethod, null)
        .timeout(const Duration(seconds: 3));
  } catch (e) {
    debugPrint('MR home unregister: $e');
  } finally {
    await controller.setPreventClose(false);
    await controller.close();
  }
}

class MrDeskIndependentHome extends StatefulWidget {
  const MrDeskIndependentHome({super.key, required this.windowId});
  final int windowId;

  @override
  State<MrDeskIndependentHome> createState() => _MrDeskIndependentHomeState();
}

class _MrDeskIndependentHomeState extends State<MrDeskIndependentHome>
    with MultiWindowListener {
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    DesktopMultiWindow.setMethodHandler((call, fromWindowId) async => null);
    DesktopMultiWindow.addListener(this);
  }

  @override
  void dispose() {
    DesktopMultiWindow.removeListener(this);
    DesktopMultiWindow.setMethodHandler(null);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    if (_closing) return;
    _closing = true;
    await closeMrDeskHomeWindow(widget.windowId);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: DesktopHomePage(technicianWindowId: widget.windowId));
}
