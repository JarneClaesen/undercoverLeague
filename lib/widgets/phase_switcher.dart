import 'package:flutter/material.dart';
import 'package:undercoverleague/theme/motion.dart';

/// Cross-fades whatever the game is showing when [phaseKey] changes, so a
/// phase change is something the player sees happen instead of a snap.
class PhaseSwitcher extends StatelessWidget {
  final Object phaseKey;
  final Widget child;

  const PhaseSwitcher({super.key, required this.phaseKey, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.slow),
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(animation),
          child: child,
        ),
      ),
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topCenter,
        children: [
          ...previousChildren.map((c) => Positioned.fill(child: c)),
          ?currentChild,
        ],
      ),
      child: KeyedSubtree(key: ValueKey(phaseKey), child: child),
    );
  }
}
