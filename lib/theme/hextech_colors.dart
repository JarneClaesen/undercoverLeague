import 'package:flutter/material.dart';

/// Raw palette. These are the only literal colours in the app; every widget
/// reads either these tokens or the semantic ones on [HextechTheme].
abstract final class HextechColors {
  /// Page background.
  static const Color abyss = Color(0xFF010A13);

  /// Panels.
  static const Color navy = Color(0xFF0A1428);

  /// Raised panels, hover.
  static const Color navyLight = Color(0xFF0A323C);

  /// Primary borders, headings.
  static const Color gold = Color(0xFFC8AA6E);

  /// Primary text on dark.
  static const Color goldBright = Color(0xFFF0E6D2);

  /// Inactive borders, dividers.
  static const Color goldDark = Color(0xFF785A28);

  /// Gradient stops, disabled borders.
  static const Color goldDeep = Color(0xFF463714);

  /// Hextech accent: active / your-turn glow.
  static const Color blue = Color(0xFF0AC8B9);

  /// Secondary accent.
  static const Color blueMid = Color(0xFF0397AB);

  /// Accent gradient stop.
  static const Color blueDeep = Color(0xFF005A82);

  /// Secondary text.
  static const Color grey = Color(0xFFA09B8C);

  /// Disabled text.
  static const Color greyDark = Color(0xFF5B5A56);

  /// Undercover, eliminated, leave / end game.
  static const Color danger = Color(0xFFC24B42);
  static const Color dangerBright = Color(0xFFE84057);

  /// Vote locked, ready.
  static const Color success = Color(0xFF1EA48A);
}

/// Semantic colours, so widgets say what a colour is *for* rather than which
/// swatch it is. Read it with `context.hextech`.
@immutable
class HextechTheme extends ThemeExtension<HextechTheme> {
  final Color panel;
  final Color panelBorder;
  final Color accent;
  final Color accentGlow;
  final Color danger;
  final Color success;
  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;

  const HextechTheme({
    required this.panel,
    required this.panelBorder,
    required this.accent,
    required this.accentGlow,
    required this.danger,
    required this.success,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
  });

  static const HextechTheme dark = HextechTheme(
    panel: HextechColors.navy,
    panelBorder: HextechColors.goldDark,
    accent: HextechColors.gold,
    accentGlow: HextechColors.blue,
    danger: HextechColors.danger,
    success: HextechColors.success,
    textPrimary: HextechColors.goldBright,
    textSecondary: HextechColors.grey,
    textDisabled: HextechColors.greyDark,
  );

  @override
  HextechTheme copyWith({
    Color? panel,
    Color? panelBorder,
    Color? accent,
    Color? accentGlow,
    Color? danger,
    Color? success,
    Color? textPrimary,
    Color? textSecondary,
    Color? textDisabled,
  }) {
    return HextechTheme(
      panel: panel ?? this.panel,
      panelBorder: panelBorder ?? this.panelBorder,
      accent: accent ?? this.accent,
      accentGlow: accentGlow ?? this.accentGlow,
      danger: danger ?? this.danger,
      success: success ?? this.success,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textDisabled: textDisabled ?? this.textDisabled,
    );
  }

  @override
  HextechTheme lerp(covariant HextechTheme? other, double t) {
    if (other == null) return this;
    return HextechTheme(
      panel: Color.lerp(panel, other.panel, t)!,
      panelBorder: Color.lerp(panelBorder, other.panelBorder, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentGlow: Color.lerp(accentGlow, other.accentGlow, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      success: Color.lerp(success, other.success, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
    );
  }
}

extension HextechThemeContext on BuildContext {
  /// The semantic palette. Falls back to [HextechTheme.dark] so widgets keep
  /// working under a bare [ThemeData] (e.g. in widget tests).
  HextechTheme get hextech => Theme.of(this).extension<HextechTheme>() ?? HextechTheme.dark;
}
