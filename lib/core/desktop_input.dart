/// Pointer profiles for the Linux desktop window.
///
/// These mirror the two practical ways to drive a native X11 desktop from a
/// phone. DroidDesk's interaction split is the reference, but this
/// implementation is original Misty OS code that talks to our own native X11
/// surface. No GPL code or third-party X server binary is vendored here.
enum DesktopPointerMode {
  /// Relative movement with a visible cursor. Best for precise selection,
  /// dragging, right-click menus and keyboard-heavy work.
  trackpad,

  /// Absolute touch-to-screen mapping. Best for quickly tapping buttons and
  /// scrolling through a desktop that was designed for a finger.
  direct,
}

extension DesktopPointerModeInfo on DesktopPointerMode {
  String get storageValue => switch (this) {
        DesktopPointerMode.trackpad => 'trackpad',
        DesktopPointerMode.direct => 'direct',
      };

  String get title => switch (this) {
        DesktopPointerMode.trackpad => 'Trackpad',
        DesktopPointerMode.direct => 'Direct touch',
      };

  String get description => switch (this) {
        DesktopPointerMode.trackpad =>
          'Move a visible pointer with one finger, tap to click, and hold to '
              'right-click. Best for precise desktop work.',
        DesktopPointerMode.direct =>
          'Tap and drag directly on the remote screen. Best for quickly '
              'pressing buttons and scrolling.',
      };

  bool get usesVisibleCursor => this == DesktopPointerMode.trackpad;

  DesktopPointerMode get next => switch (this) {
        DesktopPointerMode.trackpad => DesktopPointerMode.direct,
        DesktopPointerMode.direct => DesktopPointerMode.trackpad,
      };

  static DesktopPointerMode fromStorage(String? value) => switch (value) {
        'direct' => DesktopPointerMode.direct,
        _ => DesktopPointerMode.trackpad,
      };
}
