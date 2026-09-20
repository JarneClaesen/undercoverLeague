import 'package:flutter/material.dart';
import 'package:undercoverleague/theme/app_text.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';

/// The single theme of the app. There is no light variant: the Hextech look is
/// a dark one, and `main.dart` pins `ThemeMode.dark`.
ThemeData hextechTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: HextechColors.gold,
    onPrimary: HextechColors.abyss,
    primaryContainer: HextechColors.goldDeep,
    onPrimaryContainer: HextechColors.goldBright,
    secondary: HextechColors.blue,
    onSecondary: HextechColors.abyss,
    secondaryContainer: HextechColors.blueDeep,
    onSecondaryContainer: HextechColors.goldBright,
    tertiary: HextechColors.blueMid,
    onTertiary: HextechColors.abyss,
    error: HextechColors.danger,
    onError: HextechColors.goldBright,
    errorContainer: HextechColors.danger,
    onErrorContainer: HextechColors.goldBright,
    surface: HextechColors.abyss,
    onSurface: HextechColors.goldBright,
    onSurfaceVariant: HextechColors.grey,
    surfaceContainerLowest: HextechColors.abyss,
    surfaceContainerLow: HextechColors.navy,
    surfaceContainer: HextechColors.navy,
    surfaceContainerHigh: HextechColors.navyLight,
    surfaceContainerHighest: HextechColors.navyLight,
    outline: HextechColors.goldDark,
    outlineVariant: HextechColors.goldDeep,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: HextechColors.goldBright,
    onInverseSurface: HextechColors.abyss,
    inversePrimary: HextechColors.goldDark,
  );

  final text = hextechTextTheme();

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: HextechColors.abyss,
    canvasColor: HextechColors.abyss,
    fontFamily: fontBody,
    textTheme: text,
    primaryTextTheme: text,
    splashFactory: InkRipple.splashFactory,
    extensions: const <ThemeExtension<dynamic>>[HextechTheme.dark],

    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: HextechColors.gold,
      iconTheme: const IconThemeData(color: HextechColors.gold),
      titleTextStyle: text.titleLarge,
    ),

    iconTheme: const IconThemeData(color: HextechColors.gold, size: 22),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: HextechColors.abyss.withValues(alpha: 0.85),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: text.bodyMedium?.copyWith(color: HextechColors.greyDark),
      labelStyle: text.labelMedium?.copyWith(color: HextechColors.gold),
      floatingLabelStyle: text.labelMedium?.copyWith(color: HextechColors.blue),
      helperStyle: text.bodySmall,
      errorStyle: text.bodySmall?.copyWith(color: HextechColors.dangerBright),
      counterStyle: text.bodySmall?.copyWith(color: HextechColors.greyDark),
      prefixIconColor: HextechColors.goldDark,
      suffixIconColor: HextechColors.goldDark,
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: HextechColors.goldDark),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: HextechColors.goldDark),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: HextechColors.blue),
      ),
      disabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: HextechColors.goldDeep),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: HextechColors.danger),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: HextechColors.dangerBright),
      ),
    ),

    // Fallbacks only: the app uses HextechButton. These keep any stray
    // Material button on-brand rather than deep purple.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: HextechColors.navy,
        foregroundColor: HextechColors.gold,
        disabledBackgroundColor: HextechColors.navy,
        disabledForegroundColor: HextechColors.greyDark,
        elevation: 0,
        minimumSize: const Size(0, 48),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: HextechColors.gold),
        ),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: HextechColors.gold,
        disabledForegroundColor: HextechColors.greyDark,
        minimumSize: const Size(0, 44),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: HextechColors.gold,
        disabledForegroundColor: HextechColors.greyDark,
        minimumSize: const Size(0, 48),
        side: const BorderSide(color: HextechColors.goldDark),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        textStyle: text.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: HextechColors.gold,
        disabledForegroundColor: HextechColors.greyDark,
        highlightColor: HextechColors.navyLight,
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: HextechColors.navy,
      contentTextStyle: text.bodyMedium,
      actionTextColor: HextechColors.gold,
      elevation: 0,
      insetPadding: const EdgeInsets.all(16),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: HextechColors.gold),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: HextechColors.navy,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium,
      barrierColor: HextechColors.abyss.withValues(alpha: 0.72),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: HextechColors.goldDark),
      ),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: HextechColors.navy,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      textStyle: text.bodyMedium,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: HextechColors.goldDark),
      ),
    ),

    dividerTheme: const DividerThemeData(
      color: HextechColors.goldDark,
      thickness: 1,
      space: 1,
    ),

    chipTheme: ChipThemeData(
      backgroundColor: HextechColors.navy,
      selectedColor: HextechColors.goldDeep,
      disabledColor: HextechColors.navy,
      labelStyle: text.labelSmall?.copyWith(color: HextechColors.gold),
      secondaryLabelStyle: text.labelSmall?.copyWith(color: HextechColors.goldBright),
      side: const BorderSide(color: HextechColors.goldDark),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      showCheckmark: false,
      iconTheme: const IconThemeData(color: HextechColors.gold, size: 16),
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: HextechColors.gold,
      linearTrackColor: HextechColors.goldDeep,
      circularTrackColor: Colors.transparent,
      refreshBackgroundColor: HextechColors.navy,
    ),

    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return HextechColors.goldDeep;
        if (states.contains(WidgetState.selected)) return HextechColors.gold;
        return Colors.transparent;
      }),
      checkColor: const WidgetStatePropertyAll(HextechColors.abyss),
      side: const BorderSide(color: HextechColors.goldDark, width: 1.5),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? HextechColors.gold : HextechColors.grey),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? HextechColors.goldDeep : HextechColors.navy),
      trackOutlineColor: const WidgetStatePropertyAll(HextechColors.goldDark),
    ),

    listTileTheme: ListTileThemeData(
      iconColor: HextechColors.gold,
      textColor: HextechColors.goldBright,
      titleTextStyle: text.bodyLarge,
      subtitleTextStyle: text.bodySmall,
      selectedColor: HextechColors.blue,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    ),

    tooltipTheme: TooltipThemeData(
      decoration: const BoxDecoration(
        color: HextechColors.navy,
        border: Border.fromBorderSide(BorderSide(color: HextechColors.goldDark)),
      ),
      textStyle: text.bodySmall?.copyWith(color: HextechColors.goldBright),
      waitDuration: Motion.slow,
    ),

    textSelectionTheme: TextSelectionThemeData(
      cursorColor: HextechColors.blue,
      selectionColor: HextechColors.blue.withValues(alpha: 0.3),
      selectionHandleColor: HextechColors.blue,
    ),

    scrollbarTheme: ScrollbarThemeData(
      thumbColor: const WidgetStatePropertyAll(HextechColors.goldDeep),
      thickness: const WidgetStatePropertyAll(4),
      radius: Radius.zero,
    ),
  );
}
