import 'package:flutter/material.dart';
import 'package:undercoverleague/models/daily_theme.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/widgets/hextech_button.dart';
import 'package:undercoverleague/widgets/hextech_chip.dart';
import 'package:undercoverleague/widgets/hextech_panel.dart';

/// "Today's theme": the server's daily preset pool, with an Apply button
/// for the host ([onApply] null hides it).
class DailyThemeCard extends StatelessWidget {
  final DailyTheme theme;
  final VoidCallback? onApply;

  const DailyThemeCard({super.key, required this.theme, required this.onApply});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;

    return HextechPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      accent: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.today_outlined, color: hextech.accent, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const HextechSectionLabel("Today's theme"),
                const SizedBox(height: 4),
                Text(theme.title, style: textTheme.titleMedium?.copyWith(color: HextechColors.goldBright)),
                if (theme.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(theme.description, style: textTheme.bodySmall?.copyWith(color: hextech.textSecondary)),
                ],
              ],
            ),
          ),
          if (onApply != null) ...[
            const SizedBox(width: 12),
            HextechButton(
              label: 'Apply',
              icon: Icons.auto_awesome_outlined,
              variant: HextechButtonVariant.secondary,
              expand: false,
              onPressed: onApply,
            ),
          ],
        ],
      ),
    );
  }
}
