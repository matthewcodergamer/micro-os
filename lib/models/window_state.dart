import 'dart:ui';

/// Every application that can be hosted in a desktop window.
enum AppId { terminal, desktop, browser, files, torrents, aiHub, settings }

extension AppIdInfo on AppId {
  String get title => switch (this) {
        AppId.terminal => 'Terminal',
        AppId.desktop => 'Desktop',
        AppId.browser => 'Browser',
        AppId.files => 'Files',
        AppId.torrents => 'Torrents',
        AppId.aiHub => 'AI Hub',
        AppId.settings => 'Settings',
      };

  /// Sensible default window size on a tablet-sized screen.
  Size get defaultSize => switch (this) {
        AppId.terminal => const Size(660, 420),
        AppId.desktop => const Size(760, 540),
        AppId.browser => const Size(820, 580),
        AppId.files => const Size(600, 460),
        AppId.torrents => const Size(900, 620),
        AppId.aiHub => const Size(680, 440),
        AppId.settings => const Size(600, 560),
      };
}

/// A single managed window. Mutable on purpose: the window manager updates
/// geometry and stacking order many times per drag, and rebuilding immutable
/// copies for every pointer move would be wasteful.
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

  /// Legacy compatibility flag. New windows remain floating on phones too.
  bool pinned = false;
}
