# MicroOS "macOS 27 Golden Gate" UI

Drop-in replacement for the UI layer of `matthewcodergamer/micro-os`.
Built against the current `main` (Launchpad, welcome panel, terminal tabs,
read-aloud, Hugging Face, speech settings are all kept).

## Install
1. Unzip into the repo root so `lib/` merges with your existing `lib/`.
2. Commit and push (or open a PR). The existing `build-android.yml` builds the APK.
3. No pubspec changes and no new packages.

## Files (all under lib/)
New:      ui/wallpaper.dart, ui/mac_icons.dart, ui/login_screen.dart,
          ui/spotlight.dart, ui/control_center.dart, core/format.dart,
          core/terminal_profiles.dart
Replaced: core/theme.dart, models/window_state.dart, state/desktop_state.dart,
          services/settings_store.dart, ui/desktop_screen.dart, ui/dock.dart,
          ui/status_bar.dart, ui/window_frame.dart, ui/install_screen.dart,
          ui/apps/files_app.dart, ui/apps/terminal_app.dart,
          ui/apps/settings_app.dart
Untouched: main.dart, app_scope.dart, services/linux_runtime.dart,
          services/github_auth.dart, services/system_stats.dart,
          ui/apps/ai_hub_app.dart, ui/apps/desktop_session_app.dart

## What changed
* Wallpaper: Golden Gate sunset drawn in code (no asset).
* Login screen: big clock, avatar, password pill. Password is optional and set in
  Settings > Users & Login. It is a local shell lock, not encryption.
* Menu bar: Apple menu, app menus, battery/Wi-Fi, Spotlight, Control Center, clock.
* Dock: glass dock, squircle icons, running dots, Launchpad, Trash. Auto-hide
  (Settings > Desktop & Dock): swipe up from the bottom edge to bring it back.
* Windows: traffic lights, rounded title bar, drag + edge/corner resize.
  Phones (< 720 dp wide) still open apps maximized; the green light restores.
* Finder: sidebar (drawer on phones), icon + list views, path bar, search,
  long-press menu (Open, Open in Terminal, Copy Path), Terminal here.
* Terminal: tab strip, Terminal.app colour profiles, window title
  "root - bash - 80x24". Read-aloud, auto-copy, paste, key bar all kept.
* Settings: System Settings layout (sidebar on wide, list on phones).
* Control Center shows only live data (network, battery, memory, zram, Linux).

## Notes
* Not compiled by the author. Run the CI build; if it reports an error, send it back.
* To use a real photo wallpaper, change `Wallpaper` in ui/wallpaper.dart to an
  `Image.asset` and declare the asset in pubspec.yaml.
