import 'package:flutter/material.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';

/// The lobby's toggle chip: gold outline when off, filled gold with dark
/// text when on, dimmed when [enabled] is false. [dense] uses the smaller
/// label for long rows of options (tiers, classes, regions).
class HextechChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final bool dense;
  final IconData? icon;

  /// A short trailing count ("· 170"), shown next to the label.
  final String? badge;
  final ValueChanged<bool>? onSelected;

  const HextechChip({
    super.key,
    required this.label,
    required this.selected,
    this.enabled = true,
    this.dense = false,
    this.icon,
    this.badge,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final on = selected && enabled;
    final foreground = on
        ? HextechColors.abyss
        : enabled
            ? hextech.accent
            : hextech.textDisabled;
    final style = (dense ? textTheme.labelSmall : textTheme.labelMedium)?.copyWith(color: foreground);

    return FilterChip(
      label: Text.rich(
        TextSpan(
          text: label.toUpperCase(),
          children: [
            if (badge != null)
              TextSpan(
                text: ' $badge',
                style: style?.copyWith(color: on ? HextechColors.abyss.withValues(alpha: 0.7) : hextech.textSecondary),
              ),
          ],
        ),
      ),
      avatar: icon == null ? null : Icon(icon, size: 16, color: foreground),
      selected: on,
      showCheckmark: false,
      backgroundColor: hextech.panel,
      selectedColor: hextech.accent,
      disabledColor: hextech.panel,
      side: BorderSide(color: on ? hextech.accent : hextech.panelBorder),
      labelStyle: style,
      visualDensity: dense ? VisualDensity.compact : VisualDensity.standard,
      onSelected: enabled ? onSelected : null,
    );
  }
}

/// A small uppercase, letter-spaced heading over a group of controls.
class HextechSectionLabel extends StatelessWidget {
  final String text;
  final bool enabled;

  const HextechSectionLabel(this.text, {super.key, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final hextech = context.hextech;
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: enabled ? hextech.textSecondary : hextech.textDisabled,
            letterSpacing: 2,
          ),
    );
  }
}
