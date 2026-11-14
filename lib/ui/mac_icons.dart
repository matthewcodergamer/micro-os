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
    // Use the approved Dock artwork everywhere this icon is shown.
    final asset = switch (app) {
      AppId.files => 'assets/icons/dock/finder-icon.png',
      AppId.terminal => 'assets/icons/dock/terminal-icon.png',
      AppId.browser => 'assets/icons/dock/safari-icon.png',
      AppId.settings => 'assets/icons/dock/settings-icon.png',
      _ => null,
    };
    if (asset != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: Image.asset(
          asset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          cacheWidth: (size * 2).round(),
          cacheHeight: (size * 2).round(),
        ),
      );
    }
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
      case AppId.maps:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF30B0C7), Color(0xFF007AFF)],
        );
      case AppId.mail:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF64D2FF), Color(0xFF0A84FF)],
        );
      case AppId.notes:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFD60A), Color(0xFFFF9F0A)],
        );
      case AppId.photos:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF375F), Color(0xFFBF5AF2)],
        );
      case AppId.music:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF2D55), Color(0xFFAF52DE)],
        );
      case AppId.appStore:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5E5CE6), Color(0xFF0A84FF)],
        );
      case AppId.calculator:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF636366), Color(0xFF48484A)],
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
      case AppId.maps:
        icon = Icons.map_rounded;
        break;
      case AppId.mail:
        icon = Icons.mail_rounded;
        break;
      case AppId.notes:
        icon = Icons.note_alt_rounded;
        break;
      case AppId.photos:
        icon = Icons.photo_library_rounded;
        break;
      case AppId.music:
        icon = Icons.music_note_rounded;
        break;
      case AppId.appStore:
        icon = Icons.shopping_bag_rounded;
        break;
      case AppId.calculator:
        icon = Icons.calculate_rounded;
        break;
    }
    return Center(
      child: Icon(icon, color: Colors.white, size: iconSize),
    );
  }
}

/// Native-looking Finder glyphs shared by sidebar locations and file rows.
class FinderItemIcon extends StatelessWidget {
  const FinderItemIcon({super.key, required this.kind, this.size = 22});

  final String kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (icon, colors) = switch (kind) {
      'home' => (Icons.home_rounded, const [Color(0xFF64D2FF), Color(0xFF0A84FF)]),
      'downloads' => (Icons.download_rounded, const [Color(0xFF64D2FF), Color(0xFF0A84FF)]),
      'phone' => (Icons.phone_iphone_rounded, const [Color(0xFF8E8E93), Color(0xFF48484A)]),
      'drive' => (Icons.storage_rounded, const [Color(0xFF8E8E93), Color(0xFF48484A)]),
      'folder' => (Icons.folder_rounded, const [Color(0xFF64D2FF), Color(0xFF0A84FF)]),
      'link' => (Icons.link_rounded, const [Color(0xFFAEAEB2), Color(0xFF636366)]),
      _ => (Icons.insert_drive_file_rounded, const [Color(0xFFAEAEB2), Color(0xFF636366)]),
    };
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          borderRadius: BorderRadius.circular(size * 0.22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: size * 0.12,
              offset: Offset(0, size * 0.05),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.72),
      ),
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
