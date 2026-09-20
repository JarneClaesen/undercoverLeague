import 'package:flutter/material.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';

enum SnackTone { info, warning, success, error }

/// The one snackbar helper. Every transient message in the app goes through
/// here so they all look and behave the same.
void showHextechSnack(BuildContext context, String message, {SnackTone tone = SnackTone.info}) {
  final hextech = context.hextech;
  final (Color colour, IconData icon) = switch (tone) {
    SnackTone.info => (hextech.accent, Icons.info_outline),
    SnackTone.warning => (HextechColors.blue, Icons.warning_amber_rounded),
    SnackTone.success => (hextech.success, Icons.check_circle_outline),
    SnackTone.error => (HextechColors.dangerBright, Icons.error_outline),
  };

  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: HextechColors.navy,
      elevation: 0,
      duration: const Duration(seconds: 4),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: colour.withValues(alpha: 0.7)),
      ),
      content: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: colour, width: 4)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: colour),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
