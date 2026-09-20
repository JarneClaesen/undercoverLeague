import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';
import 'package:undercoverleague/widgets/hextech_button.dart';
import 'package:undercoverleague/widgets/hextech_panel.dart';
import 'package:undercoverleague/widgets/hextech_snack.dart';

/// Opens a Hextech-styled modal with the lobby's join link as a scannable QR
/// code, the code itself, and the link text with a copy action — a friend can
/// scan it instead of typing the code by hand.
Future<void> showLobbyQrDialog(
  BuildContext context, {
  required String lobbyId,
  required String link,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: HextechColors.abyss.withValues(alpha: 0.78),
    transitionDuration: Motion.of(context, Motion.base),
    pageBuilder: (dialogContext, _, _) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Material(
              type: MaterialType.transparency,
              child: HextechPanel(
                accent: true,
                padding: const EdgeInsets.all(20),
                child: _LobbyQrContent(lobbyId: lobbyId, link: link),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (dialogContext, animation, _, child) {
      if (Motion.reduced(dialogContext)) return child;
      final curved = CurvedAnimation(parent: animation, curve: Motion.enter, reverseCurve: Motion.exit);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _LobbyQrContent extends StatefulWidget {
  final String lobbyId;
  final String link;

  const _LobbyQrContent({required this.lobbyId, required this.link});

  @override
  State<_LobbyQrContent> createState() => _LobbyQrContentState();
}

class _LobbyQrContentState extends State<_LobbyQrContent> {
  static const Duration _confirmFor = Duration(milliseconds: 1500);

  Timer? _confirmTimer;
  bool _copied = false;

  @override
  void dispose() {
    _confirmTimer?.cancel();
    super.dispose();
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: widget.link));
    hextechLightHaptic();
    if (!mounted) return;
    showHextechSnack(context, 'Link copied', tone: SnackTone.success);
    setState(() => _copied = true);
    _confirmTimer?.cancel();
    _confirmTimer = Timer(_confirmFor, () {
      if (!mounted) return;
      setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'SCAN TO JOIN',
          style: textTheme.labelSmall?.copyWith(color: hextech.textSecondary, letterSpacing: 2),
        ),
        const SizedBox(height: 16),
        // The QR needs a light quiet zone around dark modules for reliable
        // scanning, so it is painted in the app's inks rather than the panel's
        // navy — pulled from the same token set as everything else.
        LayoutBuilder(
          builder: (context, constraints) {
            final qrSize = constraints.maxWidth.isFinite ? constraints.maxWidth.clamp(160.0, 240.0) : 240.0;
            return Container(
              padding: const EdgeInsets.all(16),
              color: HextechColors.goldBright,
              child: QrImageView(
                data: widget.link,
                size: qrSize,
                padding: EdgeInsets.zero,
                backgroundColor: Colors.transparent,
                semanticsLabel: 'QR code for the lobby link',
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: HextechColors.abyss),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: HextechColors.abyss,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        SelectableText(
          widget.lobbyId,
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall?.copyWith(color: hextech.accent),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                widget.link,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(color: hextech.textSecondary),
              ),
            ),
            const SizedBox(width: 4),
            AnimatedSwitcher(
              duration: Motion.of(context, Motion.fast),
              switchInCurve: Motion.enter,
              switchOutCurve: Motion.exit,
              child: IconButton(
                key: ValueKey(_copied),
                icon: Icon(_copied ? Icons.check : Icons.copy, size: 18, color: hextech.accent),
                tooltip: 'Copy link',
                onPressed: _copyLink,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
