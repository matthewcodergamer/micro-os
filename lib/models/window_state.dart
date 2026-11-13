import 'dart:ui';

/// Every application that can be hosted in a desktop window.
enum AppId { terminal, desktop, browser, files, aiHub, settings }

extension AppIdInfo on AppId {
  String get title => switch (this) {
        AppId.terminal => 'Terminal',
        AppId.desktop => 'Linux Desktop',
        AppId.browser => 'Browser',
        AppId.files => 'Finder',
        AppId.aiHub => 'AI Hub',
        AppId.settings => 'System Settings',
      };

  String get subtitle => switch (this) {
        AppId.terminal => 'Linux shell',
        AppId.desktop => 'X11 desktop session',
        AppId.browser => 'Web browser',
        AppId.files => 'Android storage',
        AppId.aiHub => 'OpenCode agent',
        AppId.settings => 'Preferences',
      };

  /// Sensible default window size on a tablet-sized screen.
  Size get defaultSize => switch (this) {
        AppId.terminal => const Size(660, 420),
        AppId.desktop => const Size(760, 540),
        AppId.browser => const Size(820, 580),
        AppId.files => const Size(680, 460),
        AppId.aiHub => const Size(680, 440),
        AppId.settings => const Size(700, 520),
      };
}

/// A single managed window. Mutable on purpose: the window manager updates
/// geometry and stacking order many times per drag.
class ManagedWindow {
  ManagedWindow({
    required this.id,
    required this.app,
    required this.title,
    required this.rect,
    required this.zIndex,
    this.args,
  });

  final int id;
  final AppId app;
  final List<String>? args;
  String title;
  Rect rect;
  int zIndex;

  bool minimized = false;
  bool maximized = false;
  Rect? restoreRect;

  /// True when the window is locked to the usable area (phone portrait).
  bool pinned = false;
}
