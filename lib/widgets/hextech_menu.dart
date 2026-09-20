import 'package:flutter/material.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';

/// One row of a [HextechMenuButton]. A [danger] entry is drawn in red for
/// actions that cost someone something (kick, end game).
class HextechMenuItem<T> {
  final T value;
  final String label;
  final IconData? icon;
  final bool danger;

  const HextechMenuItem({required this.value, required this.label, this.icon, this.danger = false});
}

/// The kebab ("⋮") button: a small icon that opens a Hextech-styled popup
/// with [items]. The popup itself is styled by `popupMenuTheme`; this only
/// lays out the rows and honours reduced motion.
class HextechMenuButton<T> extends StatelessWidget {
  final List<HextechMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  final String tooltip;

  const HextechMenuButton({
    super.key,
    required this.items,
    required this.onSelected,
    this.tooltip = 'More',
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;

    return PopupMenuButton<T>(
      tooltip: tooltip,
      icon: Icon(Icons.more_vert, size: 20, color: hextech.textSecondary),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        minimumSize: const Size(36, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      popUpAnimationStyle: Motion.reduced(context)
          ? AnimationStyle.noAnimation
          : AnimationStyle(duration: Motion.base, curve: Motion.enter, reverseDuration: Motion.fast),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final item in items)
          PopupMenuItem<T>(
            value: item.value,
            height: 40,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.icon != null) ...[
                  Icon(item.icon, size: 18, color: item.danger ? HextechColors.dangerBright : hextech.accent),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Text(
                    item.label,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      color: item.danger ? HextechColors.dangerBright : hextech.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
