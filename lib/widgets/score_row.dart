import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:undercoverleague/models/lobby.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';
import 'package:undercoverleague/widgets/hextech_panel.dart';

/// One line of the scoreboard: rank emblem, name with the host crown and the
/// viewer marker, a stats line underneath, and the points on the right.
///
/// The top three ranks get a medal in the metal of their place; every other
/// rank is a plain number. A player who left the lobby keeps their row but
/// is dimmed and labelled so nobody looks for them at the table.
class ScoreRow extends StatelessWidget {
  final String name;
  final int rank;
  final int points;
  final PlayerStats? stats;
  final bool isHost;
  final bool isYou;
  final bool left;

  /// Position in the list, used to stagger the entrance.
  final int index;

  const ScoreRow({
    super.key,
    required this.name,
    required this.rank,
    required this.points,
    this.stats,
    this.isHost = false,
    this.isYou = false,
    this.left = false,
    this.index = 0,
  });

  /// The medal metal of [rank], null past the podium. Gold, silver and
  /// bronze are the palette's own gold, warm grey and dark gold.
  static Color? medalColor(int rank) => switch (rank) {
        1 => HextechColors.gold,
        2 => HextechColors.grey,
        3 => HextechColors.goldDark,
        _ => null,
      };

  /// "3 games · 2 as impostor · 1 survival", or null without stats.
  static String? describe(PlayerStats? stats) {
    if (stats == null) return null;
    String n(int count, String one, [String? many]) => '$count ${count == 1 ? one : many ?? '${one}s'}';
    return [
      n(stats.games, 'game'),
      '${stats.impostorGames} as impostor',
      n(stats.civilianSurvivals, 'survival'),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final medal = medalColor(rank);
    final nameColour = left ? hextech.textSecondary : hextech.textPrimary;
    final line = describe(stats);

    final emblem = SizedBox(
      width: 40,
      height: 40,
      child: medal == null
          ? Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: hextech.panelBorder),
              ),
              alignment: Alignment.center,
              child: Text(
                '$rank',
                style: textTheme.labelMedium?.copyWith(color: hextech.textSecondary),
              ),
            )
          : Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: medal.withValues(alpha: 0.14),
                border: Border.all(color: medal, width: 2),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.military_tech, size: 22, color: medal),
            ),
    );

    Widget row = Row(
      children: [
        emblem,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (isHost) ...[
                    Icon(Icons.workspace_premium, size: 16, color: hextech.accent),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyLarge?.copyWith(color: nameColour),
                    ),
                  ),
                  if (isYou) ...[
                    const SizedBox(width: 6),
                    Text('(you)', style: textTheme.bodySmall?.copyWith(color: hextech.textSecondary)),
                  ],
                  if (left) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(color: hextech.textDisabled),
                      ),
                      child: Text(
                        'LEFT',
                        style: textTheme.labelSmall?.copyWith(color: hextech.textDisabled),
                      ),
                    ),
                  ],
                ],
              ),
              if (line != null) ...[
                const SizedBox(height: 2),
                Text(
                  line,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(color: hextech.textSecondary),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$points',
              style: textTheme.titleLarge?.copyWith(color: isYou ? hextech.accentGlow : hextech.accent),
            ),
            Text(
              points == 1 ? 'PT' : 'PTS',
              style: textTheme.labelSmall?.copyWith(color: hextech.textSecondary),
            ),
          ],
        ),
      ],
    );

    row = HextechPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      accent: isYou,
      glow: isYou,
      child: row,
    );

    if (left) {
      row = Opacity(opacity: 0.6, child: row);
    }

    if (Motion.reduced(context)) return row;

    return row
        .animate()
        .fadeIn(duration: Motion.base, delay: Duration(milliseconds: index * 40), curve: Motion.enter)
        .slideX(begin: -0.05, end: 0, duration: Motion.base, curve: Motion.enter);
  }
}
