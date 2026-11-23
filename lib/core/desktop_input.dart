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

/// How the Dock behaves across phone and desktop-size screens.
///
/// Automatic is the Misty default: large screens keep a centred, always-on
/// Dock, while phones hide it until you swipe up from the bottom edge.
enum DockVisibilityMode { automatic, alwaysVisible, autoHide }

extension DockVisibilityModeInfo on DockVisibilityMode {
  String get storageValue => switch (this) {
        DockVisibilityMode.automatic => 'automatic',
        DockVisibilityMode.alwaysVisible => 'always_visible',
        DockVisibilityMode.autoHide => 'auto_hide',
      };

  String get title => switch (this) {
        DockVisibilityMode.automatic => 'Automatic',
        DockVisibilityMode.alwaysVisible => 'Always visible',
        DockVisibilityMode.autoHide => 'Auto-hide',
      };

  String get description => switch (this) {
        DockVisibilityMode.automatic =>
          'Keep the Dock centred on tablets and desktops. On phones, swipe up '
              'from the bottom edge to reveal it.',
        DockVisibilityMode.alwaysVisible =>
          'Keep the Dock centred at all times, except while an app is '
              'full-screen.',
        DockVisibilityMode.autoHide =>
          'Hide the Dock everywhere. Swipe up from the bottom edge to bring '
              'it back.',
      };

  bool shouldAutoHide({required bool desktopMode}) => switch (this) {
        DockVisibilityMode.automatic => !desktopMode,
        DockVisibilityMode.alwaysVisible => false,
        DockVisibilityMode.autoHide => true,
      };

  static DockVisibilityMode fromStorage(String? value) => switch (value) {
        'always_visible' => DockVisibilityMode.alwaysVisible,
        'auto_hide' => DockVisibilityMode.autoHide,
        _ => DockVisibilityMode.automatic,
      };
}
