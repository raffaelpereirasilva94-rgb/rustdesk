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
    return const Text.rich(
      TextSpan(children: [
        TextSpan(text: 'MR', style: TextStyle(color: Color(0xFF5B7FE5))),
        TextSpan(text: 'Desk', style: TextStyle(color: Color(0xFFFCFCFC))),
      ]),
      style: TextStyle(fontFamily: 'Segoe UI', fontSize: 16,
        fontWeight: FontWeight.w500, letterSpacing: -0.3),
      maxLines: 1,
      softWrap: false,
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
