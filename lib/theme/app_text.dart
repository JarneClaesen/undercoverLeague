import 'package:flutter/material.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';

/// Typography.
///
/// Both bundled families — Cinzel (display) and Source Sans 3 (body/UI) — ship
/// as *variable* fonts: one TTF each with a `wght` axis. Only the variable
/// builds are published in google/fonts, and Flutter cannot instantiate a
/// variable axis from the pubspec `weight:` descriptor, so every weight here is
/// selected with [FontVariation] on the `wght` axis. [FontWeight] is still set
/// alongside it so that synthetic fallbacks (and any platform that ignores
/// variations) land close to the intended weight.
///
/// Uppercasing is a widget concern, never a theme one: the styles below carry
/// the letterSpacing that uppercase display type needs, but the text itself is
/// upper-cased by the widget that renders it.
const String fontDisplay = 'Cinzel';
const String fontBody = 'SourceSans3';

/// `wght` axis values used by the app.
const double weightRegular = 400;
const double weightSemiBold = 600;
const double weightBold = 700;

List<FontVariation> _wght(double value) => [FontVariation('wght', value)];

FontWeight _weightOf(double value) => switch (value) {
      >= weightBold => FontWeight.w700,
      >= weightSemiBold => FontWeight.w600,
      _ => FontWeight.w400,
    };

/// A Cinzel style. Display and heading type only.
TextStyle displayStyle({
  required double size,
  double weight = weightBold,
  double letterSpacing = 1.5,
  Color color = HextechColors.goldBright,
  double? height,
}) {
  return TextStyle(
    fontFamily: fontDisplay,
    fontSize: size,
    fontWeight: _weightOf(weight),
    fontVariations: _wght(weight),
    letterSpacing: letterSpacing,
    color: color,
    height: height,
  );
}

/// A Source Sans 3 style. Body, labels and everything else.
TextStyle bodyStyle({
  required double size,
  double weight = weightRegular,
  double letterSpacing = 0,
  Color color = HextechColors.goldBright,
  double? height,
}) {
  return TextStyle(
    fontFamily: fontBody,
    fontSize: size,
    fontWeight: _weightOf(weight),
    fontVariations: _wght(weight),
    letterSpacing: letterSpacing,
    color: color,
    height: height,
  );
}

/// The app's [TextTheme]. Screens read `Theme.of(context).textTheme` and never
/// hard-code a font size.
TextTheme hextechTextTheme() {
  return TextTheme(
    // Display / headings — Cinzel.
    displayLarge: displayStyle(size: 40, letterSpacing: 3, color: HextechColors.gold, height: 1.1),
    displayMedium: displayStyle(size: 34, letterSpacing: 2.5, color: HextechColors.gold, height: 1.1),
    displaySmall: displayStyle(size: 30, letterSpacing: 2, color: HextechColors.gold, height: 1.15),
    headlineLarge: displayStyle(size: 32, letterSpacing: 2, color: HextechColors.goldBright),
    headlineMedium: displayStyle(size: 28, letterSpacing: 2, color: HextechColors.goldBright),
    headlineSmall: displayStyle(size: 24, letterSpacing: 1.8, color: HextechColors.goldBright),
    titleLarge: displayStyle(size: 22, weight: weightSemiBold, letterSpacing: 1.8, color: HextechColors.gold),
    titleMedium: displayStyle(size: 18, weight: weightSemiBold, letterSpacing: 1.5, color: HextechColors.gold),
    titleSmall: displayStyle(size: 15, weight: weightSemiBold, letterSpacing: 1.5, color: HextechColors.gold),

    // Body / UI — Source Sans 3.
    bodyLarge: bodyStyle(size: 17, color: HextechColors.goldBright, height: 1.4),
    bodyMedium: bodyStyle(size: 15, color: HextechColors.goldBright, height: 1.4),
    bodySmall: bodyStyle(size: 13, color: HextechColors.grey, height: 1.35),
    labelLarge: bodyStyle(size: 15, weight: weightSemiBold, letterSpacing: 1.2, color: HextechColors.goldBright),
    labelMedium: bodyStyle(size: 13, weight: weightSemiBold, letterSpacing: 1.2, color: HextechColors.grey),
    labelSmall: bodyStyle(size: 11, weight: weightSemiBold, letterSpacing: 1.6, color: HextechColors.grey),
  );
}
