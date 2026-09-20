import 'package:flutter/material.dart';
import 'package:undercoverleague/theme/motion.dart';

/// [AnimatedSize] that respects reduced motion. `AnimatedSize` asserts when
/// given [Duration.zero] (it re-lays itself out inside its own layout pass),
/// which is exactly what `Motion.of` yields under reduced motion, so every
/// size transition in the app goes through this widget: it animates
/// normally, and under reduced motion swaps [child] in outright.
class MotionSize extends StatelessWidget {
  const MotionSize({
    super.key,
    required this.child,
    this.duration = Motion.base,
    this.curve = Motion.enter,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;

  /// The animation length when motion is not reduced.
  final Duration duration;
  final Curve curve;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context) || duration == Duration.zero) return child;
    return AnimatedSize(
      duration: duration,
      curve: curve,
      alignment: alignment,
      child: child,
    );
  }
}
