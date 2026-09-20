import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';

/// Full-bleed page backdrop: a soft navy glow fading out to the abyss, with a
/// handful of motes drifting slowly across it.
///
/// Deliberately cheap — one controller for the whole app, plain circles, no
/// blur, no `BackdropFilter` — because this paints behind every screen and the
/// web build is the deployed target. Under reduced motion the controller never
/// starts and only the static gradient is painted.
class HextechBackground extends StatefulWidget {
  final Widget child;

  const HextechBackground({super.key, required this.child});

  @override
  State<HextechBackground> createState() => _HextechBackgroundState();
}

class _HextechBackgroundState extends State<HextechBackground> with SingleTickerProviderStateMixin {
  static const int _particleCount = 14;
  static const Duration _period = Duration(seconds: 20);

  late final AnimationController _controller = AnimationController(vsync: this, duration: _period);
  late final List<_Mote> _motes = _buildMotes();
  bool _ticking = false;

  static List<_Mote> _buildMotes() {
    // Fixed seed: the drift should look the same on every launch rather than
    // occasionally clumping all the motes into one corner.
    final random = math.Random(0x1EA48A);
    return List<_Mote>.generate(_particleCount, (i) {
      return _Mote(
        x: random.nextDouble(),
        y: random.nextDouble(),
        radius: 1.2 + random.nextDouble() * 2.4,
        opacity: 0.08 + random.nextDouble() * 0.17,
        drift: 0.04 + random.nextDouble() * 0.10,
        phase: random.nextDouble(),
        sway: 0.01 + random.nextDouble() * 0.03,
        blue: i.isEven,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Starts or stops the ticker to match the current reduced-motion setting,
  /// which can change while the app is running.
  void _syncTicker(bool reduced) {
    if (reduced == !_ticking) return;
    if (reduced) {
      _controller.stop();
      _ticking = false;
    } else {
      _controller.repeat();
      _ticking = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);
    _syncTicker(reduced);

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: reduced
              ? CustomPaint(painter: _BackgroundPainter(motes: _motes, t: 0, drawMotes: false))
              : AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => CustomPaint(
                    painter: _BackgroundPainter(motes: _motes, t: _controller.value, drawMotes: true),
                  ),
                ),
        ),
        widget.child,
      ],
    );
  }
}

class _Mote {
  final double x;
  final double y;
  final double radius;
  final double opacity;

  /// Fraction of the height travelled per loop.
  final double drift;

  /// Where in the loop this mote starts, so they do not move in lockstep.
  final double phase;

  /// Horizontal sway amplitude, as a fraction of the width.
  final double sway;
  final bool blue;

  const _Mote({
    required this.x,
    required this.y,
    required this.radius,
    required this.opacity,
    required this.drift,
    required this.phase,
    required this.sway,
    required this.blue,
  });
}

class _BackgroundPainter extends CustomPainter {
  final List<_Mote> motes;
  final double t;
  final bool drawMotes;

  const _BackgroundPainter({required this.motes, required this.t, required this.drawMotes});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // A navy glow high in the frame, falling away to the abyss at the edges.
    final gradient = RadialGradient(
      center: const Alignment(0, -0.35),
      radius: 1.05,
      colors: const [
        HextechColors.navy,
        HextechColors.abyss,
      ],
      stops: const [0.0, 1.0],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));

    if (!drawMotes) return;

    final paint = Paint()..style = PaintingStyle.fill;
    for (final mote in motes) {
      final progress = (t + mote.phase) % 1.0;
      // Upward drift, wrapping around; a slow sideways sway on top.
      final y = ((mote.y - progress * mote.drift * 4) % 1.0) * size.height;
      final x = (mote.x + math.sin((progress + mote.phase) * 2 * math.pi) * mote.sway) * size.width;
      // Fade in and out over the loop so the wrap-around is never visible.
      final fade = math.sin(progress * math.pi);
      paint.color = (mote.blue ? HextechColors.blue : HextechColors.gold)
          .withValues(alpha: mote.opacity * fade);
      canvas.drawCircle(Offset(x, y), mote.radius, paint);
    }
  }

  @override
  bool shouldRepaint(_BackgroundPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.drawMotes != drawMotes;
}
