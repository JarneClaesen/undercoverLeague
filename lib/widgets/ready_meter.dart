import 'package:flutter/material.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';

/// "SUMMONERS READY 3/5" over a row of pips, one per player. Segmented rather
/// than a continuous bar so the count is readable at a glance.
class ReadyMeter extends StatelessWidget {
  final int ready;
  final int total;
  final String label;

  const ReadyMeter({
    super.key,
    required this.ready,
    required this.total,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final filled = ready.clamp(0, total);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                label.toUpperCase(),
                style: textTheme.labelSmall?.copyWith(color: hextech.textSecondary, letterSpacing: 2),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$filled/$total',
              style: textTheme.labelSmall?.copyWith(color: hextech.accent, letterSpacing: 1.5),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (total <= 0)
          // Nobody to count yet: an empty rail keeps the layout from jumping
          // once the first player arrives.
          Container(height: 4, color: HextechColors.goldDeep)
        else
          Row(
            children: [
              for (var i = 0; i < total; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: AnimatedContainer(
                    duration: Motion.of(context, Motion.base),
                    curve: Motion.enter,
                    height: 4,
                    color: i < filled ? hextech.accent : HextechColors.goldDeep,
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }
}
