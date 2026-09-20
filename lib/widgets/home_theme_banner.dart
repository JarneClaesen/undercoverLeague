import 'package:flutter/material.dart';
import 'package:undercoverleague/models/daily_theme.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/widgets/hextech_chip.dart';
import 'package:undercoverleague/widgets/hextech_panel.dart';

/// "Today's theme" on the home screen: what the server would draw from
/// today, before anyone has a lobby. It only informs; the Apply button lives
/// in the lobby, where the host is.
class HomeThemeBanner extends StatelessWidget {
  final DailyTheme theme;

  const HomeThemeBanner({super.key, required this.theme});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;

    return HextechPanel(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.today_outlined, color: hextech.accent, size: 26),
          ),
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
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.workspace_premium, size: 14, color: hextech.textDisabled),
                    const SizedBox(width: 4),
                    Text(
                      'Hosts can apply it in the lobby',
                      style: textTheme.labelSmall?.copyWith(color: hextech.textDisabled, letterSpacing: 0.6),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
