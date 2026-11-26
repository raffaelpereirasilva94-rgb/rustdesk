import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/common/widgets/peer_card.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/widgets/mr_client_panel.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

// Internal preview only: does not grant access or override native permissions.
const mrTechnicianPreview = bool.fromEnvironment('MR_TECHNICIAN_PREVIEW');
bool get useMrTechnicianLayout => isWindows && mrTechnicianPreview &&
    !useMrClientLayout && !bind.isIncomingOnly();

const _bg = Color(0xFF0E1421);
const _surface = Color(0xFF192334);
const _border = Color(0xFF53657A);
const _white = Color(0xFFF8FAFC);
const _muted = Color(0xFFB5C9E0);
const _blue = Color(0xFF1688FF);
const _green = Color(0xFF19E53C);

class MrTechnicianPanel extends StatefulWidget {
  const MrTechnicianPanel({super.key, required this.systemError,
    required this.securityWarning, required this.status, required this.onSettings});
  final String systemError;
  final Widget securityWarning, status;
  final VoidCallback? onSettings;
  @override
  State<MrTechnicianPanel> createState() => _MrTechnicianPanelState();
}

class _MrTechnicianPanelState extends State<MrTechnicianPanel> with WindowListener {
  final _id = IDTextEditingController();
  late final _recent = gFFI.recentPeersModel;
  late final _favorites = gFFI.favoritePeersModel;
  late final _lan = gFFI.lanPeersModel;
  late final _tabs = gFFI.peerTabModel;
  late final Listenable _models = Listenable.merge([_recent, _favorites, _lan, _tabs]);
  int _selected = 0;
  Set<String> _favoriteIds = {};
  Timer? _timer;
  bool _active = true, _querying = false, _updatingFavorites = false;
  DateTime _lastQuery = DateTime.fromMillisecondsSinceEpoch(0);

  bool _visible(int i) => _tabs.isVisibleEnabled[i];
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    final available = [0, 1, 2].where(_visible).toList();
    if (available.isNotEmpty) _selected = available.first;
    if (isOptionFixed(kOptionPeerTabIndex) && available.contains(_tabs.currentTab)) {
      _selected = _tabs.currentTab;
    }
    _tabs.setCurrentTab(_selected);
    _favorites.addListener(_refreshFavorites);
    Get.put<IDTextEditingController>(_id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
    _timer = Timer.periodic(const Duration(seconds: 6), (_) => _poll());
  }
  void _reload() {
    if (_visible(0)) bind.mainLoadRecentPeers();
    if (_visible(1)) bind.mainLoadFavPeers();
    if (_visible(2)) {
      bind.mainLoadLanPeers();
      bind.mainDiscover();
    }
    _refreshFavorites();
    _poll();
  }
  Future<void> _refreshFavorites() async {
    try {
      final ids = (await bind.mainGetFav()).toSet();
      if (mounted) setState(() => _favoriteIds = ids);
    } catch (e) {
      debugPrint('MR favorites: $e');
    }
  }
  Future<void> _poll() async {
    if (!mounted || !_active || !isInHomePage() || _querying) return;
    _querying = true;
    try {
      final publicServer = await bind.mainIsUsingPublicServer();
      if (!mounted || !_active || !isInHomePage()) return;
      if (DateTime.now().difference(_lastQuery) < Duration(seconds: publicServer ? 20 : 6)) return;
      final ids = <String>{
        if (_visible(0)) ..._recent.peers.map((p) => p.id),
        if (_visible(1)) ..._favorites.peers.map((p) => p.id),
        if (_visible(2)) ..._lan.peers.map((p) => p.id),
      }..removeWhere((id) => id.isEmpty);
      if (ids.isNotEmpty) {
        await bind.queryOnlines(ids: ids.take(1000).toList());
        _lastQuery = DateTime.now();
      }
    } catch (e) {
      debugPrint('MR peer status: $e');
    } finally {
      _querying = false;
    }
  }
  @override
  void onWindowFocus() {
    _active = true;
    if (mounted && isInHomePage()) _reload();
  }
  @override
  void onWindowBlur() { _active = false; }
  @override
  void onWindowRestore() { _active = true; _poll(); }
  @override
  void dispose() {
    _timer?.cancel();
    windowManager.removeListener(this);
    _favorites.removeListener(_refreshFavorites);
    if (Get.isRegistered<IDTextEditingController>() &&
        identical(Get.find<IDTextEditingController>(), _id)) {
      Get.delete<IDTextEditingController>();
    }
    _id.dispose();
    super.dispose();
  }
  void _connect() {
    if (bind.isIncomingOnly() || _id.id.isEmpty) return;
    FocusScope.of(context).unfocus();
    connect(context, _id.id);
  }
  Future<void> _toggleFavorite(Peer peer) async {
    if (_updatingFavorites || !_visible(1)) return;
    _updatingFavorites = true;
    try {
      final ids = (await bind.mainGetFav()).toList();
      if (ids.contains(peer.id)) { ids.remove(peer.id); } else { ids.add(peer.id); }
      await bind.mainStoreFav(favs: ids);
      bind.mainLoadFavPeers();
      await _refreshFavorites();
    } catch (_) {
      if (mounted) showToast('Não foi possível atualizar o favorito.');
    } finally {
      _updatingFavorites = false;
    }
  }
  void _select(int i) {
    if (!_visible(i) || isOptionFixed(kOptionPeerTabIndex)) return;
    setState(() => _selected = i);
    _tabs.setCurrentTab(i);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(primary: _blue, surface: _surface),
        scaffoldBackgroundColor: _bg,
      ),
      child: Material(
        color: _bg,
        child: Column(children: [
          _header(),
          Expanded(child: AnimatedBuilder(
            animation: _models,
            builder: (context, _) {
              final available = [0, 1, 2].where(_visible).toList();
              final selected = available.contains(_selected) ? _selected :
                  (available.isEmpty ? -1 : available.first);
              return Column(children: [
                _localId(),
                widget.securityWarning,
                if (widget.systemError.isNotEmpty)
                  Padding(padding: const EdgeInsets.all(8),
                    child: Text(widget.systemError, style: const TextStyle(color: Colors.redAccent))),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
                    if (_visible(0)) _tab(0, selected, Icons.desktop_windows_outlined, 'Sessões recentes'),
                    if (_visible(1)) _tab(1, selected, Icons.star_border_rounded, 'Favoritos'),
                    if (_visible(2)) _tab(2, selected, Icons.radar_rounded, 'Encontrados'),
                  ]))),
                const Divider(height: 1, color: _border, indent: 24, endIndent: 24),
                Expanded(child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (selected == 0) ...[
                      _section(Icons.desktop_windows_outlined, 'Sessões recentes', _recent.peers, PeerTabIndex.recent),
                      if (_visible(2)) ...[
                        const SizedBox(height: 20),
                        const Divider(height: 1, color: _border),
                        const SizedBox(height: 15),
                        _section(Icons.radar_rounded, 'Encontrados', _lan.peers, PeerTabIndex.lan),
                      ],
                    ],
                    if (selected == 1) _section(Icons.star_border_rounded, 'Favoritos', _favorites.peers, PeerTabIndex.fav),
                    if (selected == 2) _section(Icons.radar_rounded, 'Encontrados', _lan.peers, PeerTabIndex.lan),
                  ]),
                )),
              ]);
            },
          )),
          Container(height: 46, padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: _border))),
            child: Row(children: [
              Expanded(child: widget.status), const SizedBox(width: 12),
              const Text('MR Automação Comercial', style: TextStyle(color: _white, fontSize: 13)),
            ])),
        ]),
      ),
    );
  }
  Widget _header() {
    return Container(
      height: 58, padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _border))),
      child: LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 750;
        return Row(children: [
          IconButton(tooltip: 'Configurações', onPressed: widget.onSettings,
            icon: const Icon(Icons.menu_rounded, color: _white, size: 25)),
          const SizedBox(width: 8),
          GestureDetector(behavior: HitTestBehavior.opaque,
            onPanStart: (_) => windowManager.startDragging(),
            child: Row(children: [
              Container(width: 39, height: 39, alignment: Alignment.center,
                decoration: const BoxDecoration(color: Color(0xFF080B89), shape: BoxShape.circle),
                child: const Text('MR', style: TextStyle(color: _white, fontWeight: FontWeight.w900, fontSize: 20))),
              if (!compact) ...[
                const SizedBox(width: 10),
                const Text('MR Remote', style: TextStyle(color: _white, fontSize: 20, fontWeight: FontWeight.w700)),
              ],
            ])),
          const SizedBox(width: 12),
          Container(width: 1, height: 30, color: _border),
          const SizedBox(width: 12),
          Expanded(child: SizedBox(height: 40, child: TextField(
            controller: _id, inputFormatters: [IDTextInputFormatter()],
            autocorrect: false, enableSuggestions: false,
            style: const TextStyle(color: _white, fontSize: 15),
            decoration: InputDecoration(
              hintText: compact ? 'Digite o ID' : 'Digite o ID ou endereço remoto',
              hintStyle: const TextStyle(color: _muted, fontSize: 14),
              prefixIcon: compact ? null : const Icon(Icons.desktop_windows_outlined, color: _muted, size: 20),
              filled: true, fillColor: _surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: const BorderSide(color: _border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: const BorderSide(color: _blue))),
            onSubmitted: (_) => _connect(),
          ))),
          const SizedBox(width: 10),
          SizedBox(height: 40, child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _id,
            builder: (context, value, _) => ElevatedButton.icon(
              onPressed: _id.id.isEmpty ? null : _connect,
              icon: const Icon(Icons.arrow_forward, size: 21),
              label: const Text('Conectar', style: TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0659F8),
                foregroundColor: _white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7))),
            ),
          )),
          const SizedBox(width: 8),
          if (!kUseCompatibleUiMode) ...[
            IconButton(tooltip: 'Minimizar', onPressed: () => windowManager.minimize(),
              icon: const Icon(Icons.remove, color: _white, size: 20)),
            Obx(() => IconButton(
              tooltip: stateGlobal.isMaximized.value ? 'Restaurar' : 'Maximizar',
              onPressed: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else { await windowManager.maximize(); }
              },
              icon: Icon(stateGlobal.isMaximized.value ? Icons.filter_none : Icons.crop_square, color: _white, size: 19))),
            IconButton(tooltip: 'Fechar', onPressed: () => windowManager.close(),
              icon: const Icon(Icons.close, color: _white, size: 21)),
          ],
        ]);
      }),
    );
  }
  Widget _localId() {
    final controller = gFFI.serverModel.serverId;
    return Container(height: 76, alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final id = value.text;
          final ready = id.isNotEmpty && id != translate('Generating ...');
          return FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('Seu ID de atendimento', style: TextStyle(color: _white, fontSize: 16)),
            const SizedBox(width: 20),
            Container(width: 1, height: 27, color: _border),
            const SizedBox(width: 20),
            Text(ready ? formatID(id) : 'Gerando...', style: const TextStyle(color: _white, fontSize: 32, fontWeight: FontWeight.w700)),
            const SizedBox(width: 14),
            IconButton(tooltip: 'Informações do ID', onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('ID de atendimento'),
                content: const Text('Identificação deste computador no servidor remoto. O acesso depende das permissões e da autorização configuradas.'),
                actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fechar'))],
              )),
              icon: const Icon(Icons.info_outline, color: _white, size: 22)),
            IconButton(tooltip: 'Copiar ID', onPressed: ready ? () async {
              await Clipboard.setData(ClipboardData(text: id));
              showToast(translate('Copied'));
            } : null, icon: const Icon(Icons.copy_outlined, size: 22)),
          ]));
        },
      ));
  }
  Widget _tab(int i, int selected, IconData icon, String title) {
    final active = i == selected;
    return InkWell(onTap: () => _select(i),
      child: Container(height: 43, padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(width: 3, color: active ? _blue : Colors.transparent))),
        child: Row(children: [
          Icon(icon, size: 21, color: active ? _blue : _muted),
          const SizedBox(width: 9),
          Text(title, style: TextStyle(color: active ? _white : _muted, fontSize: 15, fontWeight: FontWeight.w600)),
        ])));
  }
  Widget _section(IconData icon, String title, List<Peer> peers, PeerTabIndex tab) {
    final devices = peers.where((p) => p.id.isNotEmpty).take(1000).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, color: _muted, size: 20), const SizedBox(width: 9),
        Text(title, style: const TextStyle(color: _white, fontSize: 16, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 13),
      if (devices.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 20),
          child: Text('Nenhum computador nesta lista.', style: TextStyle(color: _muted)))
      else LayoutBuilder(builder: (context, constraints) {
        final columns = ((constraints.maxWidth + 12) / 190).floor().clamp(1, 5).toInt();
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(spacing: 12, runSpacing: 12, children: devices.map((peer) =>
          SizedBox(width: width, child: _device(peer, tab))).toList());
      }),
    ]);
  }
  Widget _device(Peer peer, PeerTabIndex tab) {
    final title = peer.alias.isNotEmpty ? peer.alias :
        (peer.hostname.isNotEmpty ? peer.hostname : formatID(peer.id));
    final BasePeerCard menu = tab == PeerTabIndex.recent ? RecentPeerCard(peer: peer) :
        tab == PeerTabIndex.fav ? FavoritePeerCard(peer: peer) : DiscoveredPeerCard(peer: peer);
    final favorite = _favoriteIds.contains(peer.id);
    return Tooltip(message: title + ' • ' + formatID(peer.id),
      child: Material(color: _surface, borderRadius: BorderRadius.circular(8), clipBehavior: Clip.antiAlias,
        child: InkWell(
          onDoubleTap: () { if (!bind.isIncomingOnly()) connectInPeerTab(context, peer, tab); },
          onTap: () { _id.id = peer.id; },
          child: Container(decoration: BoxDecoration(border: Border.all(color: _border), borderRadius: BorderRadius.circular(8)),
            child: Column(children: [
              SizedBox(height: 105, child: Stack(fit: StackFit.expand, children: [
                // Decorative artwork, never a captured remote screen.
                CustomPaint(painter: _DeviceArtwork(peer.id)),
                Positioned(top: 9, left: 10, child: Tooltip(
                  message: peer.online ? 'Online' : 'Offline ou ainda não consultado',
                  child: Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle,
                    color: peer.online ? _green : const Color(0xFF9CA3AF))))),
                if (_visible(1)) Positioned(top: 0, right: 1, child: IconButton(
                  tooltip: favorite ? 'Remover dos favoritos' : 'Adicionar aos favoritos',
                  onPressed: () => _toggleFavorite(peer),
                  icon: Icon(favorite ? Icons.star_rounded : Icons.star_border_rounded,
                    color: favorite ? const Color(0xFFFFC857) : _white, size: 23))),
              ])),
              SizedBox(height: 37, child: Row(children: [
                const SizedBox(width: 10),
                const Icon(Icons.desktop_windows_outlined, color: _white, size: 19),
                const SizedBox(width: 9),
                Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _white, fontSize: 13, fontWeight: FontWeight.w600))),
                Builder(builder: (buttonContext) => IconButton(
                  padding: EdgeInsets.zero, constraints: const BoxConstraints.tightFor(width: 35, height: 34),
                  tooltip: 'Mais opções',
                  onPressed: () async {
                    final box = buttonContext.findRenderObject() as RenderBox;
                    final pos = box.localToGlobal(box.size.center(Offset.zero));
                    await menu.showMrTechnicianMenu(buttonContext, RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy));
                    if (mounted) _refreshFavorites();
                  },
                  icon: const Icon(Icons.more_vert, color: _white, size: 20))),
              ])),
            ])),
        ),
      ));
  }
}

class _DeviceArtwork extends CustomPainter {
  const _DeviceArtwork(this.id);
  final String id;
  @override
  void paint(Canvas canvas, Size size) {
    final colors = <List<Color>>[
      [const Color(0xFF031A32), const Color(0xFF087CC5)],
      [const Color(0xFF05225E), const Color(0xFF126CF6)],
      [const Color(0xFF221044), const Color(0xFF7936B7)],
    ];
    final pair = colors[id.codeUnits.fold<int>(0, (a, b) => a + b) % colors.length];
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: pair).createShader(rect));
    final w = size.width, h = size.height;
    for (int i = 0; i < 3; i++) {
      final y = h * (.80 + i * .13);
      final path = Path()..moveTo(0, y)
        ..cubicTo(w * .40, h * (.08 + i * .17), w * .54, h * (.95 + i * .08), w, h * (.20 + i * .22))
        ..lineTo(w, h)..lineTo(0, h)..close();
      canvas.drawPath(path, Paint()..color = pair.last.withOpacity(.24 + i * .11));
    }
  }
  @override
  bool shouldRepaint(covariant _DeviceArtwork oldDelegate) => oldDelegate.id != id;
}
