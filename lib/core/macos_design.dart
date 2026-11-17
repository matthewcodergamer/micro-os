import 'package:flutter/material.dart';

/// macOS Sequoia design tokens for Misty OS.
///
/// The shell is a hand-built Flutter implementation, not a copy of another
/// project. The numbers and colours below follow Apple's published macOS 11+
/// design language as implemented by the MIT-licensed `macos_ui` package
/// (`macosui/macos_ui`, `lib/src/theme/macos_colors.dart`), with touch-sized
/// overrides where a 10pt desktop control would be unusable on a phone.
///
/// Provenance and the credit for the reference implementation live in
/// `docs/SEQUOIA.md`.
class Sequoia {
  const Sequoia._();

  // ---------------------------------------------------------------- geometry

  /// Window corner radius. macOS 11 through Sequoia use 10pt; 11 keeps the
  /// corners readable on a phone at 2x/3x pixel density.
  static const double windowRadius = 11;

  /// Sheets, popovers and Spotlight panels are visibly rounder than windows.
  static const double sheetRadius = 14;
  static const double cardRadius = 10;
  static const double popoverRadius = 12;

  /// Touch-sized title bar. A 28pt desktop title bar is impossible to hit with
  /// a finger, so Misty uses 40 for the drag zone and keeps the 12pt lights.
  static const double titleBarHeight = 40;
  static const double menuBarHeight = 28;
  static const double trafficLightSize = 12;
  static const double trafficLightGap = 8;
  static const double sidebarWidth = 232;
  static const double spotlightMaxWidth = 620;

  // ------------------------------------------------------------- system hues

  /// Apple's dark-appearance system colours (`macos_ui` / HIG values).
  static const accent = Color(0xFF0A84FF);
  static const blue = Color(0xFF0A84FF);
  static const green = Color(0xFF30D158);
  static const red = Color(0xFFFF453A);
  static const orange = Color(0xFFFF9F0A);
  static const yellow = Color(0xFFFFD60A);
  static const purple = Color(0xFFBF5AF2);
  static const pink = Color(0xFFFF375F);
  static const teal = Color(0xFF40C8E0);
  static const indigo = Color(0xFF5E5CE6);
  static const graphite = Color(0xFF8E8E93);

  /// Window traffic lights keep the macOS 11+ values rather than the system
  /// red/green/yellow, which are noticeably more saturated.
  static const closeLight = Color(0xFFFF5F57);
  static const miniLight = Color(0xFFFEBC2E);
  static const zoomLight = Color(0xFF28C840);

  // ------------------------------------------------------------------- text

  static const label = Color(0xFFF5F5F7);
  static const labelSecondary = Color(0xA6FFFFFF); // 65%
  static const labelTertiary = Color(0x66FFFFFF); // 40%

  // ----------------------------------------------------------------- chrome

  static const chromeBase = Color(0xFF1C1C1E);
  static const chromeSolid = Color(0xFF1E1E21);
  static const sidebarTint = Color(0xFF26262A);
  static const toolbarTint = Color(0xFF2C2C30);

  /// Translucent "material" used by the menu bar, Dock and panels.
  ///
  /// Flutter has no native macOS vibrancy; a [BackdropFilter] plus this tinted
  /// layer is the closest stable approximation on Android GPUs.
  static BoxDecoration glass({
    double radius = 20,
    double tint = 0.55,
    double borderAlpha = 0.18,
    Color base = chromeBase,
    BoxBorder? border,
  }) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      color: base.withValues(alpha: tint),
      border:
          border ??
          Border.all(
            color: Colors.white.withValues(alpha: borderAlpha),
            width: 0.8,
          ),
    );
  }

  /// Softer, larger shadow used by floating panels. Sequoia panels cast a
  /// wider and shallower shadow than the Big Sur windows they replaced.
  static List<BoxShadow> panelShadow({double opacity = 0.42}) => [
    BoxShadow(
      color: Colors.black.withValues(alpha: opacity),
      blurRadius: 34,
      offset: const Offset(0, 14),
    ),
  ];

  /// Settings-style grouped card: a rounded translucent block inside which
  /// rows are separated by hairlines.
  static BoxDecoration groupedCard({double radius = cardRadius}) =>
      BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.07),
          width: 0.8,
        ),
      );
}
