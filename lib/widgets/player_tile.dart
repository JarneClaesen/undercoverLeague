import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';
import 'package:undercoverleague/widgets/hextech_panel.dart';

/// What this player is doing right now, from the viewer's perspective.
enum PlayerState { normal, ready, current, eliminated, voted }

/// One row of the roster: initials medallion, name, status chip.
///
/// The medallion ring carries the identity (gold = host, blue = you) and the
/// chip carries the state, so neither has to be spelled out in prose.
class PlayerTile extends StatelessWidget {
  final String name;
  final bool isHost;
  final bool isYou;
  final bool connected;
  final PlayerState state;
  final Widget? trailing;

  /// Position in the list, used to stagger the entrance.
  final int index;

  /// Optional extra chip (the role, at game over).
  final Widget? roleChip;

  const PlayerTile({
    super.key,
    required this.name,
    this.isHost = false,
    this.isYou = false,
    this.connected = true,
    this.state = PlayerState.normal,
    this.trailing,
    this.index = 0,
    this.roleChip,
  });

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final word = parts.first;
      return (word.length == 1 ? word : word.substring(0, 2)).toUpperCase();
    }
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final eliminated = state == PlayerState.eliminated;

    final ringColour = isHost
        ? hextech.accent
        : isYou
            ? hextech.accentGlow
            : hextech.panelBorder;

    final medallion = SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: HextechColors.navyLight,
              border: Border.all(color: ringColour, width: 2),
            ),
            alignment: Alignment.center,
            child: Text(
              _initials,
              style: textTheme.labelMedium?.copyWith(
                color: eliminated ? hextech.textDisabled : hextech.textPrimary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          if (isHost)
            Positioned(
              top: -2,
              child: Icon(Icons.workspace_premium, size: 16, color: hextech.accent),
            ),
        ],
      ),
    );

    final chip = _statusChip(context);

    Widget row = Row(
      children: [
        medallion,
        const SizedBox(width: 12),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyLarge?.copyWith(
                    color: eliminated ? hextech.textSecondary : hextech.textPrimary,
                    decoration: eliminated ? TextDecoration.lineThrough : null,
                    decorationColor: hextech.danger,
                  ),
                ),
              ),
              if (isYou) ...[
                const SizedBox(width: 6),
                Text('(you)', style: textTheme.bodySmall?.copyWith(color: hextech.textSecondary)),
              ],
            ],
          ),
        ),
        if (roleChip != null) ...[const SizedBox(width: 8), roleChip!],
        if (chip != null) ...[const SizedBox(width: 8), chip],
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );

    row = HextechPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      accent: state == PlayerState.current,
      glow: state == PlayerState.current,
      tone: eliminated ? PanelTone.danger : PanelTone.neutral,
      child: row,
    );

    if (!connected) {
      row = Opacity(opacity: 0.55, child: row);
    }

    if (Motion.reduced(context)) return row;

    return row
        .animate()
        .fadeIn(duration: Motion.base, delay: Duration(milliseconds: index * 40), curve: Motion.enter)
        .slideX(begin: -0.05, end: 0, duration: Motion.base, curve: Motion.enter);
  }

  Widget? _statusChip(BuildContext context) {
    final hextech = context.hextech;

    // Connection trumps everything else: a disconnected player's "ready" is
    // not news, the fact that they dropped is.
    if (!connected) {
      return _Chip(label: 'RECONNECTING…', colour: HextechColors.blue, pulse: true);
    }

    return switch (state) {
      PlayerState.ready => _Chip(label: 'READY', colour: hextech.success),
      PlayerState.voted => _Chip(label: 'VOTED', colour: hextech.success),
      PlayerState.current => _Chip(label: 'DESCRIBING', colour: hextech.accentGlow, pulse: true),
      PlayerState.eliminated => _Chip(label: 'ELIMINATED', colour: hextech.danger),
      PlayerState.normal => null,
    };
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color colour;
  final bool pulse;

  const _Chip({required this.label, required this.colour, this.pulse = false});

  @override
  Widget build(BuildContext context) {
    Widget chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        border: Border.all(color: colour.withValues(alpha: 0.6)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colour, fontSize: 10),
      ),
    );

    if (pulse && !Motion.reduced(context)) {
      chip = chip
          .animate(onPlay: (controller) => controller.repeat(reverse: true))
          .fadeIn(duration: 900.ms, begin: 0.45, curve: Motion.emphasized);
    }
    return chip;
  }
}
