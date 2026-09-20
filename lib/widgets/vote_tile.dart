import 'package:flutter/material.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';
import 'package:undercoverleague/widgets/hextech_panel.dart';
import 'package:undercoverleague/widgets/turn_order_strip.dart';

/// One candidate on the ballot.
///
/// [hasVoted] says only *that* this player has locked something in — never
/// whom they picked. The server broadcasts the whole votes map while voting is
/// open, and leaking a target here would hand the table the answer.
class VoteTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// Name the medallion initials are drawn from; omitted for the abstain tile.
  final String? avatarName;
  final bool isSkip;
  final bool hasVoted;

  const VoteTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.avatarName,
    this.isSkip = false,
    this.hasVoted = false,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final enabled = onTap != null;

    final leading = isSkip
        ? Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: HextechColors.navy,
              border: Border.all(color: selected ? hextech.accent : hextech.panelBorder),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.block, size: 20, color: hextech.textSecondary),
          )
        : Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: HextechColors.navyLight,
              border: Border.all(color: selected ? hextech.accent : hextech.panelBorder, width: 2),
            ),
            alignment: Alignment.center,
            child: Text(
              initialsOf(avatarName ?? label),
              style: textTheme.labelMedium?.copyWith(
                color: hextech.textPrimary,
                letterSpacing: 0.5,
              ),
            ),
          );

    final check = AnimatedSwitcher(
      duration: Motion.of(context, Motion.fast),
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
      child: selected
          ? Icon(Icons.check_circle, key: const ValueKey('checked'), color: hextech.accent, size: 24)
          : const SizedBox(key: ValueKey('unchecked'), width: 24, height: 24),
    );

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          splashColor: HextechColors.gold.withValues(alpha: 0.08),
          highlightColor: Colors.transparent,
          child: HextechPanel(
            accent: selected,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isSkip ? 'Abstain' : label,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyLarge?.copyWith(
                          color: enabled ? hextech.textPrimary : hextech.textDisabled,
                        ),
                      ),
                      if (isSkip)
                        Text(
                          'Eliminate nobody',
                          style: textTheme.bodySmall?.copyWith(color: hextech.textSecondary),
                        ),
                    ],
                  ),
                ),
                if (hasVoted) ...[
                  _VotedChip(colour: hextech.success),
                  const SizedBox(width: 10),
                ],
                check,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VotedChip extends StatelessWidget {
  final Color colour;

  const _VotedChip({required this.colour});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        border: Border.all(color: colour.withValues(alpha: 0.6)),
      ),
      child: Text(
        'VOTED',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colour),
      ),
    );
  }
}
