import 'dart:math' as math;
import 'package:flutter/material.dart';

const mrDeskRemoteTabsMethod = 'mrdesk_remote_tabs_v1';

class MrDeskSession {
  const MrDeskSession(this.windowId, this.peerId);
  final int windowId;
  final String peerId;
}

bool mrDeskSameSessions(List<MrDeskSession> a, List<MrDeskSession> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i].windowId != b[i].windowId || a[i].peerId != b[i].peerId) return false;
  }
  return true;
}

// Session ownership belongs to the home window that initiated the connection.
// Native remote windows may contain several peers or move a peer between tabs;
// the destination ID is stable across those UI operations. Unknown native
// sessions belong to the primary home (zero), never to every home.
class MrDeskSessionOwners {
  final _owners = <String, int>{};
  final _pendingUntil = <String, DateTime>{};

  void assign(String peerId, int homeId, DateTime now) {
    _owners[peerId] = homeId;
    _pendingUntil[peerId] = now.add(const Duration(seconds: 30));
  }

  int ownerOf(String peerId) => _owners[peerId] ?? 0;

  void forget(String peerId) {
    _owners.remove(peerId);
    _pendingUntil.remove(peerId);
  }

  void releaseHome(int homeId) {
    // Closing a home must not close its native remote connections.
    final ids = _owners.entries.where((e) => e.value == homeId)
        .map((e) => e.key).toList();
    for (final id in ids) { forget(id); }
  }

  void reconcile(List<MrDeskSession> sessions, DateTime now,
      {required bool complete}) {
    final live = sessions.map((s) => s.peerId).toSet();
    for (final id in live) { _pendingUntil.remove(id); }
    if (!complete) return;
    for (final id in _owners.keys.toList()) {
      if (live.contains(id)) continue;
      final until = _pendingUntil[id];
      if (until == null || !now.isBefore(until)) forget(id);
    }
  }

  List<MrDeskSession> forHome(List<MrDeskSession> sessions, int homeId) =>
      sessions.where((s) => ownerOf(s.peerId) == homeId).toList();
}

// A new home window has no remote ID or credentials in its launch payload.
const mrDeskHomeWindowKey = 'mrdesk_home_window_v1';
const mrDeskHomeOpenMethod = 'mrdesk_home_open_v1';
const mrDeskHomeCloseMethod = 'mrdesk_home_close_v1';
const mrDeskHomeSnapshotMethod = 'mrdesk_home_snapshot_v1';
const mrDeskHomeSettingsMethod = 'mrdesk_home_settings_v1';

Map<String, dynamic> mrDeskHomeWindowArguments() => {mrDeskHomeWindowKey: true};
String mrDeskHomeEventChannel(int windowId) => 'mrdesk-home-$windowId';

class MrDeskNewSessionButton extends StatelessWidget {
  const MrDeskNewSessionButton({
    super.key,
    required this.enabled,
    required this.onOpen,
  });

  final bool enabled;
  final Future<void> Function() onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = MrDeskTechnicianPalette(
        Theme.of(context).brightness == Brightness.dark);
    return IconButton(
      tooltip: 'Nova sessão',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 36, height: 34),
      icon: Icon(Icons.add_to_queue_outlined, size: 19,
          color: enabled ? palette.foreground : palette.border),
      onPressed: enabled ? onOpen : null,
    );
  }
}

// Tabs are visually separated from the new-window action. Keep them in
// their own scrolling area so they cannot overlap window controls.
class MrDeskSessionTabs extends StatelessWidget {
  const MrDeskSessionTabs({super.key, required this.sessions,
      required this.onActivate, required this.labelFor});
  final List<MrDeskSession> sessions;
  final ValueChanged<MrDeskSession> onActivate;
  final String Function(MrDeskSession) labelFor;

  @override
  Widget build(BuildContext context) {
    final palette = MrDeskTechnicianPalette(
        Theme.of(context).brightness == Brightness.dark);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final session in sessions)
          Padding(
            key: ValueKey((session.windowId, session.peerId)),
            padding: const EdgeInsets.only(left: 8),
            child: Tooltip(
              message: labelFor(session),
              child: Material(
                color: palette.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                  side: BorderSide(color: palette.border),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(5),
                  onTap: () => onActivate(session),
                  child: SizedBox(
                    height: 28,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.desktop_windows_outlined,
                            color: palette.muted, size: 16),
                        const SizedBox(width: 7),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 142),
                          child: Text(labelFor(session), maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: palette.foreground, fontSize: 13)),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

// All device sections use the same width and aspect ratio. A short list
// never grows its cards to fill the unused columns.
double mrDeskCardWidth(double available) {
  if (available <= 0) return 0;
  final columns = ((available + 12) / 230).floor().clamp(1, 4).toInt();
  return math.min(320.0, (available - (columns - 1) * 12) / columns);
}

enum MrDeskServerState { ready, connecting, disconnected, unavailable }

MrDeskServerState mrDeskServerState(int? status, {required bool stopped}) {
  if (stopped) return MrDeskServerState.disconnected;
  switch (status) {
    case 1: return MrDeskServerState.ready;
    case 0: return MrDeskServerState.connecting;
    case -1: return MrDeskServerState.disconnected;
    default: return MrDeskServerState.unavailable;
  }
}

class MrDeskWordmark extends StatelessWidget {
  const MrDeskWordmark({super.key});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Text.rich(
      TextSpan(children: [
        const TextSpan(text: 'MR', style: TextStyle(color: Color(0xFF5B7FE5))),
        TextSpan(text: 'Desk', style: TextStyle(color: dark
            ? const Color(0xFFFCFCFC) : const Color(0xFF172033))),
      ]),
      style: const TextStyle(fontFamily: 'Inter', fontSize: 16,
        fontWeight: FontWeight.w500, letterSpacing: -0.3),
      maxLines: 1,
      softWrap: false,
    );
  }
}

// Keep the existing dark identity and provide a matching readable light palette.
class MrDeskTechnicianPalette {
  const MrDeskTechnicianPalette(this.dark);
  final bool dark;
  Color get background => dark ? const Color(0xFF0E1421) : const Color(0xFFF6F8FC);
  Color get surface => dark ? const Color(0xFF192334) : Colors.white;
  Color get border => dark ? const Color(0xFF53657A) : const Color(0xFFB8C4D6);
  Color get foreground => dark ? const Color(0xFFF8FAFC) : const Color(0xFF172033);
  Color get muted => dark ? const Color(0xFFB5C9E0) : const Color(0xFF52647B);
  Color get selected => dark ? const Color(0xFF111A28) : const Color(0xFFE5EBFA);
}

class MrDeskLocalId extends StatelessWidget {
  const MrDeskLocalId({super.key, required this.id, required this.onInfo, this.onCopy});
  final String id;
  final VoidCallback onInfo;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final palette = MrDeskTechnicianPalette(
        Theme.of(context).brightness == Brightness.dark);
    return Container(
      height: 96,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 160, child: Text('Seu Dispositivo',
            textAlign: TextAlign.right,
            style: TextStyle(color: palette.foreground, fontSize: 16))),
          const SizedBox(width: 20),
          Text(id, style: const TextStyle(color: Color(0xFF5B7FE5),
              fontSize: 46, fontWeight: FontWeight.w600)),
          const SizedBox(width: 20),
          SizedBox(width: 160, child: Row(children: [
            IconButton(tooltip: 'Informações do ID', onPressed: onInfo,
                icon: Icon(Icons.info_outline, color: palette.foreground, size: 22)),
            IconButton(tooltip: 'Copiar ID', onPressed: onCopy,
                icon: const Icon(Icons.copy_outlined, size: 22)),
          ])),
        ]),
      ),
    );
  }
}

class MrDeskServerIndicator extends StatelessWidget {
  const MrDeskServerIndicator({super.key, required this.status, required this.publicServer});
  final MrDeskServerState status;
  final bool publicServer;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    switch (status) {
      case MrDeskServerState.ready:
        color = const Color(0xFF00C853);
        label = publicServer ? 'Servidor público pronto' : 'Servidor pronto';
        break;
      case MrDeskServerState.connecting:
        color = const Color(0xFFFFC857);
        label = 'Conectando ao servidor';
        break;
      case MrDeskServerState.disconnected:
        color = const Color(0xFFEF4444);
        label = 'Servidor desconectado';
        break;
      case MrDeskServerState.unavailable:
        color = const Color(0xFF9CA3AF);
        label = 'Status indisponível';
        break;
    }
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: Container(
          width: 18, height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: status == MrDeskServerState.ready
              ? const Icon(Icons.check, color: Colors.white, size: 13)
              : null,
        ),
      ),
    );
  }
}
