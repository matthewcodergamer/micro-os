import 'package:flutter/material.dart';

/// Layout constants shared by the shell and the window manager.
const double kStatusBarHeight = 30;
const double kDockHeight = 92;
const double kDockReserved = 108;

/// macOS-flavoured palette. Everything is translucent so the wallpaper shows
/// through the chrome, which is what makes the shell feel like a desktop OS
/// instead of a normal Material app.
class MicroColors {
  const MicroColors._();

  static const accent = Color(0xFF0A84FF);
  static const panel = Color(0xCC101219);
  static const panelSolid = Color(0xFF15171F);
  static const windowBody = Color(0xF2161922);
  static const windowHeader = Color(0xFF1F222C);
  static const border = Color(0x33FFFFFF);
  static const text = Color(0xFFEDEFF5);
  static const subtle = Color(0xFF98A1B2);
  static const green = Color(0xFF2ECC71);
  static const amber = Color(0xFFF1C40F);
  static const red = Color(0xFFFF5F57);
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
      bodyMedium: TextStyle(color: MicroColors.text, fontSize: 13),
      bodySmall: TextStyle(color: MicroColors.subtle, fontSize: 11),
      titleMedium: TextStyle(
        color: MicroColors.text,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: const Color(0x14FFFFFF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
        borderSide: const BorderSide(color: MicroColors.accent),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: MicroColors.accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: MicroColors.accent),
    ),
    dividerColor: MicroColors.border,
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: MicroColors.accent,
      linearTrackColor: Color(0x22FFFFFF),
    ),
  );
}
