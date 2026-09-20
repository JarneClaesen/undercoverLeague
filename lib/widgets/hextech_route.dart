import 'package:flutter/material.dart';
import 'package:undercoverleague/theme/motion.dart';

/// The app's page transition: a fade-through. The arriving page fades in and
/// rises slightly; the leaving page just fades, so the two never slide past
/// each other. Replaces every `MaterialPageRoute`.
Route<T> hextechRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: Motion.slow,
    reverseTransitionDuration: Motion.base,
    opaque: true,
    barrierColor: null,
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (Motion.reduced(context)) return child;

      final incoming = CurvedAnimation(parent: animation, curve: Motion.enter);
      final outgoing = CurvedAnimation(parent: secondaryAnimation, curve: Motion.exit);

      return FadeTransition(
        // Fade the page out again while the next one covers it.
        opacity: Tween<double>(begin: 1, end: 0).animate(outgoing),
        child: FadeTransition(
          opacity: incoming,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(incoming),
            child: child,
          ),
        ),
      );
    },
  );
}
