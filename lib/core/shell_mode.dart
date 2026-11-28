import 'dart:ui';

/// How the shell presents application windows.
///
/// Misty OS is a desktop that also has to feel native on a phone. Instead of
/// choosing one compromise, the user can pick the experience that fits them:
///
/// * [automatic] gives phones immersive, full-screen apps and keeps floating
///   macOS windows on tablets and desktop-sized screens.
/// * [desktop] always uses draggable, resizable macOS windows.
/// * [mobile] always uses edge-to-edge, touch-first full-screen apps.
enum ShellMode { automatic, desktop, mobile }

extension ShellModeInfo on ShellMode {
  String get storageValue => name;

  String get title => switch (this) {
    ShellMode.automatic => 'Automatic',
    ShellMode.desktop => 'Desktop',
    ShellMode.mobile => 'Mobile',
  };

  String get description => switch (this) {
    ShellMode.automatic =>
      'Full-screen, touch-friendly apps on phones. Floating macOS windows on '
          'tablets and larger screens.',
    ShellMode.desktop =>
      'The complete macOS experience everywhere: movable, resizable windows '
          'and a persistent Dock on larger screens.',
    ShellMode.mobile =>
      'Every app opens edge to edge with a compact mobile header and larger '
          'touch targets. Best for one-handed use.',
  };
}

ShellMode shellModeFromStorage(String? value) {
  for (final mode in ShellMode.values) {
    if (mode.storageValue == value) return mode;
  }
  return ShellMode.automatic;
}

/// Resolves [mode] against the current screen size.
///
/// The shortest side is used instead of the width so a phone stays in the
/// full-screen layout when it is rotated to landscape.
bool resolveMobileShell(ShellMode mode, Size size) {
  return switch (mode) {
    ShellMode.mobile => true,
    ShellMode.desktop => false,
    // `shortestSide == 0` happens on the first frame. Treat it as desktop so
    // windows opened before layout still get sensible floating geometry; the
    // first real layout pass immediately reflows them.
    ShellMode.automatic => size.shortestSide > 0 && size.shortestSide < 600,
  };
}
