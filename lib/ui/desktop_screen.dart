import 'dart:io';\n\nimport 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models/window_state.dart';
import 'apps/ai_hub_app.dart';
import 'apps/desktop_session_app.dart';
import 'apps/files_app.dart';
import 'apps/settings_app.dart';
import 'apps/terminal_app.dart';
import 'dock.dart';
import 'install_screen.dart';
import 'status_bar.dart';
import 'window_frame.dart';

/// The desktop: wallpaper, window layer, menu bar, Dock.
class DesktopScreen extends StatefulWidget {
  const DesktopScreen({super.key});

  @override
  State<DesktopScreen> createState() => _DesktopScreenState();
}

class _DesktopScreenState extends State<DesktopScreen> {
  Size _size = Size.zero;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          if (size != _size) {
            _size = size;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) scope.desktop.syncToScreen(size);
            });
          }

          final compact = size.width < 720;

          return AnimatedBuilder(
            animation: scope.desktop,
            builder: (context, _) {
              return Stack(
                children: [
                  Positioned.fill(child: _Wallpaper(settings: scope.settings)),
                  for (final window in scope.desktop.ordered)
                    if (!window.minimized)
                      Positioned(
                        left: window.rect.left,
                        top: window.rect.top,
                        width: window.rect.width,
                        height: window.rect.height,
                        child: WindowFrame(
                          window: window,
                          screen: size,
                          desktop: scope.desktop,
                          child: _contentFor(window, scope),
                        ),
                      ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: StatusBar(
                      desktop: scope.desktop,
                      stats: scope.stats,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: compact ? 10 : 14,
                    child: Center(
                      child: Dock(
                        desktop: scope.desktop,
                        compact: compact,
                        onOpen: (app) =>
                            scope.desktop.open(app, screen: size),
                      ),
                    ),
                  ),
                  if (!scope.runtime.isReady)
                    Positioned.fill(child: InstallScreen(runtime: scope.runtime)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _contentFor(ManagedWindow window, AppScope scope) {
    switch (window.app) {
      case AppId.terminal:
        return TerminalApp(runtime: scope.runtime, argv: window.args);
      case AppId.desktop:
        return DesktopSessionApp(runtime: scope.runtime);
      case AppId.browser:
        return DesktopSessionApp(
          runtime: scope.runtime,
          launchBrowser: true,
          singleProcess: scope.settings.singleProcessBrowser,
        );
      case AppId.files:
        return FilesApp(runtime: scope.runtime);
      case AppId.aiHub:
        return AiHubApp(runtime: scope.runtime);
      case AppId.settings:
        return SettingsApp(runtime: scope.runtime);
    }
  }
}

/// Cheap gradient wallpaper with two soft light sources. Drawn with plain
/// containers so it costs nothing while windows are being dragged.
class _Wallpaper extends StatelessWidget {
  const _Wallpaper();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF10131B), Color(0xFF1A1430), Color(0xFF07131A)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            left: -80,
            child: _Glow(color: const Color(0xFF2F5BFF), size: 380),
          ),
          Positioned(
            bottom: -160,
            right: -100,
            child: _Glow(color: const Color(0xFF7C4DFF), size: 420),
          ),
          Positioned(
            top: 180,
            right: 40,
            child: _Glow(color: const Color(0xFF00A67E), size: 220),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}
