import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';

/// A placeholder row standing in for a summoner who has not arrived yet.
///
/// Sized and padded to match `PlayerTile` so the roster reads as one list, but
/// dashed and breathing rather than solid: the seat is an invitation, not a
/// player. Under reduced motion it simply sits at a dimmed opacity.
class LobbyOpenSeat extends StatelessWidget {
  const LobbyOpenSeat({super.key});

  /// Matches the medallion column of a `PlayerTile`.
  static const double _medallionSlot = 44;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;

    final Widget seat = CustomPaint(
      painter: _DashedBorderPainter(color: hextech.panelBorder),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: _medallionSlot,
              height: _medallionSlot,
              child: Center(
                child: Icon(Icons.person_add_alt, size: 22, color: hextech.textDisabled),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Open seat',
              style: textTheme.bodyLarge?.copyWith(color: hextech.textSecondary),
            ),
          ],
        ),
      ),
    );

    if (Motion.reduced(context)) return Opacity(opacity: 0.7, child: seat);

    return seat
        .animate(onPlay: (controller) => controller.repeat(reverse: true))
        .fade(begin: 0.5, end: 0.9, duration: 1000.ms, curve: Motion.emphasized);
  }
}

/// A 1px dashed rectangle around the child, drawn by walking the outline and
/// extracting alternating segments.
class _DashedBorderPainter extends CustomPainter {
  final Color color;

  const _DashedBorderPainter({required this.color});

  static const double _dash = 6;
  static const double _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final outline = Path()..addRect(Offset.zero & size);
    for (final metric in outline.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + _dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) => oldDelegate.color != color;
}
