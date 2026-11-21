/// User-selectable interaction profiles for the same Linux desktop session.
///
/// Desktop mode favours a visible relative pointer and keyboard/mouse input.
/// Mobile desktop mode keeps the same applications and Linux guest but favours
/// direct touch, larger targets and the Android on-screen keyboard.
enum ExperienceMode { desktop, mobileDesktop }

extension ExperienceModePresentation on ExperienceMode {
  String get storageValue => switch (this) {
    ExperienceMode.desktop => 'desktop',
    ExperienceMode.mobileDesktop => 'mobile-desktop',
  };

  String get title => switch (this) {
    ExperienceMode.desktop => 'Desktop Mode',
    ExperienceMode.mobileDesktop => 'Mobile Desktop',
  };

  String get description => switch (this) {
    ExperienceMode.desktop =>
      'A pointer-first workstation with precise selection, dragging, right-click and keyboard shortcuts.',
    ExperienceMode.mobileDesktop =>
      'A touch-first desktop with direct tapping, comfortable controls and phone-friendly layouts.',
  };

  bool get usesTrackpadPointer => this == ExperienceMode.desktop;

  static ExperienceMode? fromStorage(String? value) => switch (value) {
    'desktop' => ExperienceMode.desktop,
    'mobile-desktop' => ExperienceMode.mobileDesktop,
    _ => null,
  };
}
