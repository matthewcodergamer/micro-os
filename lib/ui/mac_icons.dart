import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/window_state.dart';

ShapeBorder _squircle(double size, {BorderSide side = BorderSide.none}) {
  return ContinuousRectangleBorder(
    borderRadius: BorderRadius.circular(size * 0.44),
    side: side,
  );
}

/// Dock / Spotlight app icon: a glossy squircle with a per-app glyph.
class MacAppIcon extends StatelessWidget {
  const MacAppIcon({super.key, required this.app, required this.size});

  final AppId app;
  final double size;

  @override
  Widget build(BuildContext context) {
    final shape = _squircle(size);
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: shape,
          gradient: _gradient(app),
          shadows: [
            BoxShadow(
              color: const Color(0x44000000),
              blurRadius: size * 0.14,
              offset: Offset(0, size * 0.06),
            ),
          ],
        ),
        child: ClipPath(
          clipper: ShapeBorderClipper(shape: shape),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _glyph(app, size),
              // Top gloss.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment(0, 0.55),
                    colors: [
                      Color(0x55FFFFFF),
                      Color(0x00FFFFFF),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static LinearGradient _gradient(AppId app) {
    switch (app) {
      case AppId.terminal:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1C1C1E), Color(0xFF2C2C2E)],
        );
      case AppId.desktop:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A84FF), Color(0xFF5E5CE6)],
        );
      case AppId.browser:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF30B0C7), Color(0xFF0A84FF)],
        );
      case AppId.files:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A84FF), Color(0xFF64D2FF)],
        );
      case AppId.aiHub:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFBF5AF2), Color(0xFF5E5CE6)],
        );
      case AppId.settings:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8E8E93), Color(0xFF636366)],
        );
    }
  }

  static Widget _glyph(AppId app, double size) {
    final iconSize = size * 0.48;
    IconData icon;
    switch (app) {
      case AppId.terminal:
        icon = Icons.terminal_rounded;
        break;
      case AppId.desktop:
        icon = Icons.desktop_windows_rounded;
        break;
      case AppId.browser:
        icon = Icons.language_rounded;
        break;
      case AppId.files:
        icon = Icons.folder_rounded;
        break;
      case AppId.aiHub:
        icon = Icons.smart_toy_rounded;
        break;
      case AppId.settings:
        icon = Icons.settings_rounded;
        break;
    }
    return Center(
      child: Icon(icon, color: Colors.white, size: iconSize),
    );
  }
}

/// Small running indicator dot under a dock icon.
class RunningDot extends StatelessWidget {
  const RunningDot({super.key, this.active = true});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 5,
      decoration: BoxDecoration(
        color: active ? Colors.white : Colors.transparent,
        shape: BoxShape.circle,
      ),
    );
  }
}
