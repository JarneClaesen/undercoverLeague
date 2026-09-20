import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';

enum NoticeTone { info, warning, success, danger }

/// An inline "here is what is happening" row: icon, message, tinted plate.
/// Used wherever the screen is waiting on somebody else, so those moments read
/// as a state rather than as a stray line of text.
class StatusNotice extends StatelessWidget {
  final String message;
  final IconData? icon;
  final NoticeTone tone;

  /// Breathes the icon in and out — for "still waiting" states.
  final bool pulse;

  const StatusNotice({
    super.key,
    required this.message,
    this.icon,
    this.tone = NoticeTone.info,
    this.pulse = false,
  });

  @override
  Widget build(BuildContext context) {
    final hextech = context.hextech;
    final (Color colour, IconData defaultIcon) = switch (tone) {
      NoticeTone.info => (hextech.accent, Icons.info_outline),
      NoticeTone.warning => (HextechColors.blue, Icons.hourglass_empty),
      NoticeTone.success => (hextech.success, Icons.check_circle_outline),
      NoticeTone.danger => (HextechColors.dangerBright, Icons.report_gmailerrorred_outlined),
    };

    Widget glyph = Icon(icon ?? defaultIcon, size: 18, color: colour);
    if (pulse && !Motion.reduced(context)) {
      glyph = glyph
          .animate(onPlay: (controller) => controller.repeat(reverse: true))
          .fadeIn(duration: 900.ms, begin: 0.5, curve: Motion.emphasized);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.08),
        border: Border.all(color: colour.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: glyph),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: hextech.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
