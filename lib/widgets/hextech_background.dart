import 'package:flutter/material.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';

/// Full-bleed page backdrop: a soft navy glow fading out to the abyss.
///
/// Deliberately static — no animation, no blur, no `BackdropFilter` — because
/// this paints behind every screen and an animated backdrop kept the whole app
/// repainting at the display's refresh rate even while idle, which showed up
/// as battery drain on phones. It is painted once and then only when the
/// screen size changes.
class HextechBackground extends StatelessWidget {
  final Widget child;

  const HextechBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const RepaintBoundary(child: CustomPaint(painter: _BackgroundPainter())),
        child,
      ],
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  const _BackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // A navy glow high in the frame, falling away to the abyss at the edges.
    const gradient = RadialGradient(
      center: Alignment(0, -0.35),
      radius: 1.05,
      colors: [HextechColors.navy, HextechColors.abyss],
      stops: [0.0, 1.0],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
  }

  @override
  bool shouldRepaint(_BackgroundPainter oldDelegate) => false;
}
