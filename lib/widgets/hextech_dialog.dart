import 'package:flutter/material.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';
import 'package:undercoverleague/widgets/hextech_button.dart';
import 'package:undercoverleague/widgets/hextech_panel.dart';

/// Asks the player to confirm something. Resolves to true only when they pick
/// the confirm button; dismissing the dialog counts as a cancel.
Future<bool> showHextechDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool danger = false,
}) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: cancelLabel,
    barrierColor: HextechColors.abyss.withValues(alpha: 0.78),
    transitionDuration: Motion.of(context, Motion.base),
    pageBuilder: (dialogContext, _, _) {
      final textTheme = Theme.of(dialogContext).textTheme;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Material(
              type: MaterialType.transparency,
              child: HextechPanel(
                accent: true,
                tone: danger ? PanelTone.danger : PanelTone.neutral,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title.toUpperCase(),
                      style: textTheme.titleLarge?.copyWith(
                        color: danger ? HextechColors.dangerBright : HextechColors.gold,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(message, style: textTheme.bodyMedium),
                    const SizedBox(height: 24),
                    HextechButton(
                      label: confirmLabel,
                      variant: danger ? HextechButtonVariant.danger : HextechButtonVariant.primary,
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                    ),
                    const SizedBox(height: 10),
                    HextechButton(
                      label: cancelLabel,
                      variant: HextechButtonVariant.secondary,
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (dialogContext, animation, _, child) {
      if (Motion.reduced(dialogContext)) return child;
      final curved = CurvedAnimation(parent: animation, curve: Motion.enter, reverseCurve: Motion.exit);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
  return result ?? false;
}
