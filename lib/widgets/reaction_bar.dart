import 'dart:async';

import 'package:flutter/material.dart';
import 'package:undercoverleague/services/lobby_service.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';
import 'package:undercoverleague/widgets/hextech_button.dart';
import 'package:undercoverleague/widgets/hextech_chip.dart';

/// The row of emoji a player on the bench can throw at the table.
///
/// Only spectators and eliminated players ever see it — the server rejects
/// reactions from anyone still alive, so the screens never mount it for
/// them. Taps are rate-limited here to the server's 700 ms so a mashed chip
/// does not queue up rejections; the chips dim while the bar is cooling.
class ReactionBar extends StatefulWidget {
  /// Sends the emoji; defaults to [LobbyService.react].
  final ValueChanged<String>? onReact;

  /// Matches the server's per-player rate limit.
  static const Duration cooldown = Duration(milliseconds: 700);

  const ReactionBar({super.key, this.onReact});

  @override
  State<ReactionBar> createState() => _ReactionBarState();
}

class _ReactionBarState extends State<ReactionBar> {
  Timer? _cooldown;
  bool _cooling = false;

  @override
  void dispose() {
    _cooldown?.cancel();
    super.dispose();
  }

  void _send(String emoji) {
    if (_cooling) return;
    hextechLightHaptic();
    try {
      (widget.onReact ?? LobbyService().react)(emoji);
    } catch (e) {
      debugPrint('Could not send reaction: $e');
      return;
    }
    setState(() => _cooling = true);
    _cooldown?.cancel();
    _cooldown = Timer(ReactionBar.cooldown, () {
      if (mounted) setState(() => _cooling = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const HextechSectionLabel('React'),
        const SizedBox(height: 8),
        AnimatedOpacity(
          opacity: _cooling ? 0.55 : 1,
          duration: Motion.of(context, Motion.fast),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final emoji in reactionEmoji)
                _ReactionChip(
                  emoji: emoji,
                  style: textTheme.titleLarge,
                  border: hextech.panelBorder,
                  fill: hextech.panel,
                  onTap: _cooling ? null : () => _send(emoji),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReactionChip extends StatelessWidget {
  final String emoji;
  final TextStyle? style;
  final Color border;
  final Color fill;
  final VoidCallback? onTap;

  const _ReactionChip({
    required this.emoji,
    required this.style,
    required this.border,
    required this.fill,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: 'React $emoji',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          splashColor: HextechColors.gold.withValues(alpha: 0.10),
          highlightColor: Colors.transparent,
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: fill, border: Border.all(color: border)),
            child: Text(emoji, style: style, textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }
}
