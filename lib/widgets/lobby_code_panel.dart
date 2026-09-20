import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';
import 'package:undercoverleague/widgets/hextech_button.dart';
import 'package:undercoverleague/widgets/hextech_panel.dart';
import 'package:undercoverleague/widgets/hextech_snack.dart';
import 'package:undercoverleague/widgets/lobby_qr.dart';

/// The lobby's code, large and selectable, with the one-tap ways of passing it
/// on. The copy buttons confirm themselves for a moment — the icon becomes a
/// check — so the tap is visibly acknowledged even if the snackbar is missed.
class LobbyCodePanel extends StatefulWidget {
  final String lobbyId;

  const LobbyCodePanel({super.key, required this.lobbyId});

  @override
  State<LobbyCodePanel> createState() => _LobbyCodePanelState();
}

class _LobbyCodePanelState extends State<LobbyCodePanel> {
  static const Duration _confirmFor = Duration(milliseconds: 1500);

  Timer? _confirmTimer;
  bool _copiedCode = false;
  bool _copiedLink = false;

  @override
  void dispose() {
    _confirmTimer?.cancel();
    super.dispose();
  }

  /// The page the app is served from, with the code attached, so a friend who
  /// opens it lands on the home screen with the code already filled in. On
  /// native builds `Uri.base` is not a web origin (it is a local file/app
  /// URI), so those fall back to the deployed web origin instead.
  String get _shareLink {
    final origin = kIsWeb ? Uri.base.origin : 'https://undercover.jarneclaesen.be';
    return '$origin/?lobby=${Uri.encodeQueryComponent(widget.lobbyId)}';
  }

  Future<void> _copy(String value, {required bool link}) async {
    await Clipboard.setData(ClipboardData(text: value));
    hextechLightHaptic();
    if (!mounted) return;
    showHextechSnack(context, link ? 'Link copied' : 'Code copied', tone: SnackTone.success);
    setState(() {
      _copiedCode = !link;
      _copiedLink = link;
    });
    _confirmTimer?.cancel();
    _confirmTimer = Timer(_confirmFor, () {
      if (!mounted) return;
      setState(() {
        _copiedCode = false;
        _copiedLink = false;
      });
    });
  }

  Widget _copyButton({
    required bool copied,
    required String label,
    required VoidCallback onPressed,
  }) {
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.fast),
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      child: HextechButton(
        // Keyed on the confirmation so the switcher cross-fades the swap.
        key: ValueKey(copied),
        label: label,
        icon: copied ? Icons.check : Icons.copy,
        variant: HextechButtonVariant.secondary,
        expand: false,
        onPressed: onPressed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;

    return HextechPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'LOBBY CODE',
            style: textTheme.labelSmall?.copyWith(color: hextech.textSecondary, letterSpacing: 2),
          ),
          const SizedBox(height: 8),
          SelectableText(
            widget.lobbyId,
            style: textTheme.headlineSmall?.copyWith(color: hextech.accent),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _copyButton(
                copied: _copiedCode,
                label: 'Copy',
                onPressed: () => _copy(widget.lobbyId, link: false),
              ),
              if (kIsWeb)
                _copyButton(
                  copied: _copiedLink,
                  label: 'Copy link',
                  onPressed: () => _copy(_shareLink, link: true),
                ),
              HextechButton(
                label: 'QR code',
                icon: Icons.qr_code_2,
                variant: HextechButtonVariant.secondary,
                expand: false,
                onPressed: () => showLobbyQrDialog(context, lobbyId: widget.lobbyId, link: _shareLink),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
