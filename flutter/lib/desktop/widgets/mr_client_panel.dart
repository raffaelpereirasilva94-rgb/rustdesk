import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/mr_desk_icon_button.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

// This compile-time flag is for internal visual validation only. It does
// not grant or enforce incoming-only permissions; the native profile does.
const mrClientPreview = bool.fromEnvironment('MR_CLIENT_PREVIEW');
bool get useMrClientLayout =>
    isWindows && (bind.isIncomingOnly() ||
        (mrClientPreview && !bind.isOutgoingOnly()));

// Compact Windows client window; logical pixels follow display scaling.
const mrClientWindowSize = Size(290, 500);
const _background = Color(0xFF11161F);
const _card = Color(0xFF181E28);
const _border = Color(0xFF485366);
const _blue = Color(0xFF1688FF);
const _white = Color(0xFFF8FAFC);

// Resized PNG from the original MR Automação Comercial logo supplied by
// the maintainer. Embedded to keep the visual preview asset-only.
final _logo = base64Decode(
  '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'
);

void _quitClient() {
  // Match the existing incoming-only Quit action and portable-service cleanup.
  bind.mainOnMainWindowClose();
  SystemNavigator.pop();
  exit(0);
}

class MrClientHeader extends StatelessWidget {
  const MrClientHeader({Key? key, required this.onSettings}) : super(key: key);
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: const BoxDecoration(
        color: _background,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          MrDeskIconButton(
            tooltip: 'Configurações',
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.menu_rounded, color: _white, size: 24),
            onPressed: onSettings,
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => windowManager.startDragging(),
              child: const SizedBox.expand(),
            ),
          ),
          MrDeskIconButton(
            tooltip: 'Minimizar',
            padding: EdgeInsets.zero,
            onPressed: () => windowManager.minimize(),
            icon: const Icon(Icons.remove, color: _white, size: 20),
          ),
          MrDeskIconButton(
            tooltip: 'Fechar',
            padding: EdgeInsets.zero,
            onPressed: _quitClient,
            icon: const Icon(Icons.close, color: _white, size: 22),
          ),
        ],
      ),
    );
  }
}

class MrClientPanel extends StatelessWidget {
  const MrClientPanel({
    Key? key,
    required this.stopped,
    required this.systemError,
    required this.securityWarning,
    required this.status,
  }) : super(key: key);

  final RxBool stopped;
  final String systemError;
  final Widget securityWarning;
  final Widget status;

  @override
  Widget build(BuildContext context) {
    final model = gFFI.serverModel;
    return Theme(
      data: ThemeData(brightness: Brightness.dark, fontFamily: 'Inter').copyWith(
        colorScheme: const ColorScheme.dark(primary: _blue, surface: _card),
        scaffoldBackgroundColor: _background,
      ),
      child: Material(
        color: _background,
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(builder: (context, constraints) {
                final h = constraints.maxHeight;
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 17),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: h * .035),
                      const _Brand(),
                      SizedBox(height: h * .075),
                      securityWarning,
                      if (systemError.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(systemError,
                              style: const TextStyle(color: Color(0xFFF87171))),
                        ),
                      AnimatedBuilder(
                        animation: model,
                        builder: (context, _) => Obx(() {
                          final id = model.serverId.text;
                          final idReady = id.isNotEmpty &&
                              id != translate('Generating ...');
                          final showPassword = !stopped.value &&
                              model.approveMode != 'click' &&
                              model.verificationMethod != kUsePermanentPassword;
                          final password = model.serverPasswd.text;
                          return Column(
                            children: [
                              _CredentialCard(
                                label: 'Seu ID',
                                value: idReady ? id : 'Gerando...',
                                action: 'Copiar',
                                icon: Icons.copy_outlined,
                                onTap: idReady ? () async {
                                  await Clipboard.setData(
                                      ClipboardData(text: model.serverId.text));
                                  showToast(translate('Copied'));
                                } : null,
                              ),
                              const SizedBox(height: 13),
                              _CredentialCard(
                                label: 'Senha de uso único',
                                value: showPassword
                                    ? (password == translate('Generating ...')
                                        ? 'Gerando...' : password)
                                    : '—',
                                action: 'Gerar nova',
                                icon: Icons.refresh_rounded,
                                onTap: showPassword
                                    ? () { bind.mainUpdateTemporaryPassword(); }
                                    : null,
                              ),
                            ],
                          );
                        }),
                      ),
                      SizedBox(height: h * .09),
                      Center(
                        child: SizedBox(
                          width: 160,
                          height: 42,
                          child: OutlinedButton(
                            onPressed: _quitClient,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _white,
                              side: const BorderSide(
                                  color: Color(0xFFBCCBF9), width: 1.4),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Sair',
                                style: TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                );
              }),
            ),
            Container(
              constraints: const BoxConstraints(minHeight: 45),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: _border)),
              ),
              child: Row(
                children: [
                  Expanded(child: status),
                  const SizedBox(width: 8),
                  const Text('v0.2.0-dev',
                      style: TextStyle(color: _white, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.memory(_logo, width: 76, height: 76, fit: BoxFit.contain,
                semanticLabel: 'MR Automação Comercial'),
            const SizedBox(width: 12),
            Container(width: 1.4, height: 47, color: _blue),
            const SizedBox(width: 12),
            const Text('MR Remote',
                style: TextStyle(color: _white, fontSize: 24,
                    fontWeight: FontWeight.w700, letterSpacing: -.4)),
          ],
        ),
      ),
    );
  }
}

class _CredentialCard extends StatelessWidget {
  const _CredentialCard({
    required this.label,
    required this.value,
    required this.action,
    required this.icon,
    required this.onTap,
  });
  final String label, value, action;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 91,
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border, width: 1.2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 4, height: 57,
            decoration: BoxDecoration(
                color: _blue, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(label, style: const TextStyle(
                      color: _white, fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(value,
                          maxLines: 1,
                          softWrap: false,
                          style: const TextStyle(
                              color: _white, fontSize: 32,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(width: 1, height: 48, color: _border),
          SizedBox(
            width: 72,
            child: Tooltip(
              message: action,
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: onTap,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 26,
                        color: onTap == null ? _border : _blue),
                    const SizedBox(height: 5),
                    Text(action, style: TextStyle(fontSize: 12,
                        color: onTap == null ? _border : _white)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
