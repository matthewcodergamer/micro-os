import 'package:flutter/material.dart';

/// Layout constants shared by the shell and the window manager.
const double kMenuBarHeight = 28;
const double kStatusBarHeight = kMenuBarHeight; // legacy alias
const double kCompactBreakpoint = 720;
const double kDockHeight = 92; // legacy
const double kDockReserved = 108; // legacy

/// macOS "Golden Gate" palette: dark chrome, Liquid-Glass translucency.
class MicroColors {
  const MicroColors._();

  static const accent = Color(0xFF0A84FF);
  static const panel = Color(0xCC1C1C1E);
  static const panelSolid = Color(0xFF1E1E21);
  static const windowBody = Color(0xF21E1E21);
  static const windowHeader = Color(0xFF2B2B2F);
  static const sidebar = Color(0xFF28282C);
  static const border = Color(0x33FFFFFF);
  static const hairline = Color(0x1AFFFFFF);
  static const text = Color(0xFFF2F2F7);
  static const subtle = Color(0xFF9A9AA3);
  static const green = Color(0xFF28C840);
  static const amber = Color(0xFFFEBC2E);
  static const red = Color(0xFFFF5F57);
  static const inactiveLight = Color(0xFF4A4A4D);
}

/// Frosted "Liquid Glass" decoration used by the dock, Control Center tiles,
/// Spotlight and the lock screen controls.
BoxDecoration glassDecoration({
  double radius = 24,
  double topAlpha = 0.30,
  double bottomAlpha = 0.12,
  double borderAlpha = 0.35,
}) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.white.withValues(alpha: topAlpha),
        Colors.white.withValues(alpha: bottomAlpha),
      ],
    ),
    border: Border.all(
      color: Colors.white.withValues(alpha: borderAlpha),
      width: 0.8,
    ),
  );
}

ThemeData buildMicroTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: MicroColors.accent,
    brightness: Brightness.dark,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.transparent,
    fontFamily: 'Roboto',
    splashFactory: NoSplash.splashFactory,
    visualDensity: VisualDensity.compact,
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: MicroColors.text, fontSize: 14),
      bodySmall: TextStyle(color: MicroColors.subtle, fontSize: 12),
      titleMedium: TextStyle(
        color: MicroColors.text,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: const Color(0xF22A2A2E),
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: MicroColors.border, width: 0.8),
      ),
      textStyle: const TextStyle(color: MicroColors.text, fontSize: 14),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith<Color?>((states) {
        return states.contains(WidgetState.selected)
            ? MicroColors.green
            : const Color(0xFF48484C);
      }),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: MicroColors.accent,
      thumbColor: Colors.white,
      inactiveTrackColor: Color(0xFF48484C),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: const Color(0x14FFFFFF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: MicroColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: MicroColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: MicroColors.accent, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: MicroColors.accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: MicroColors.text,
        side: const BorderSide(color: MicroColors.border),
        shape: const StadiumBorder(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: MicroColors.accent),
    ),
    dividerColor: MicroColors.hairline,
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: MicroColors.accent,
      linearTrackColor: Color(0x22FFFFFF),
    ),
  );
}
