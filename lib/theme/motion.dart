import 'package:flutter/material.dart';

/// Every duration and curve the app animates with. Nothing animates for a
/// length that is not named here, so timings stay consistent across screens.
abstract final class Motion {
  /// Press feedback, hover.
  static const fast = Duration(milliseconds: 150);

  /// State swaps, list changes.
  static const base = Duration(milliseconds: 260);

  /// Panel entrance, phase swap.
  static const slow = Duration(milliseconds: 450);

  /// Card flip, game over.
  static const reveal = Duration(milliseconds: 900);

  static const enter = Curves.easeOutCubic;
  static const exit = Curves.easeInCubic;
  static const emphasized = Curves.easeInOutCubicEmphasized;

  /// True when the platform asks for reduced motion (Android "Remove
  /// animations", `prefers-reduced-motion` on the web). Callers skip the
  /// animation or run it with [Duration.zero].
  static bool reduced(BuildContext c) => MediaQuery.disableAnimationsOf(c);

  /// [d], or zero when the platform asks for reduced motion.
  static Duration of(BuildContext c, Duration d) => reduced(c) ? Duration.zero : d;
}
