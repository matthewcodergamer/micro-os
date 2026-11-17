# macOS Sequoia design pass

Misty OS implements the macOS Sequoia visual language by hand in Flutter. It is
not a fork of another shell, and no third-party source code was copied into this
repository. This document records what was studied, what was adopted and what
was deliberately left out.

## Reference projects evaluated

| Project | Stars | Licence | Language | Verdict |
| --- | --- | --- | --- | --- |
| [`macosui/macos_ui`](https://github.com/macosui/macos_ui) | ~2.1k | MIT | Dart | **Adopted as the metric and colour reference.** Widgets are not imported: a second theme layer would fight the shell's existing window manager. |
| [`PuruVJ/macos-web`](https://github.com/PuruVJ/macos-web) | ~2.7k | MIT | Svelte | Studied for window/traffic-light behaviour on touch. Nothing copied. |
| [`Renovamen/playground-macos`](https://github.com/Renovamen/playground-macos) | ~3.5k | MIT | React | Studied for Launchpad and menu-bar layout. Nothing copied. |

`macos_ui` tracks Apple's published macOS system colours and control metrics
(`lib/src/theme/macos_colors.dart`). `lib/core/macos_design.dart` encodes the
subset the shell needs, with the desktop values adapted for fingers.

## What "Sequoia" means in this shell

macOS 15 is not a new widget set; it is a refinement of macOS 11's visual
language. The pass therefore changes values and materials, not the architecture:

- **Translucency over flat colour.** The menu bar and Dock are now a real
  `BackdropFilter` blur of the wallpaper instead of an opaque strip.
- **Softer, wider panel shadows.** `Sequoia.panelShadow()` replaces the tight
  12–30 px shadows with a 34 px, 0.3–0.5 alpha shadow.
- **Rounder floating surfaces.** Panels use 14–22 px radii; windows keep
  Apple's 10–11 px. Settings uses grouped cards (a rounded translucent block
  per section) instead of a flat list.
- **Apple system colours.** Traffic lights use the macOS 11+ values
  (`#FF5F57`, `#FEBC2E`, `#28C840`) rather than the more saturated system
  red/yellow/green.
- **A Sequoia-inspired wallpaper.** `assets/wallpapers/sequoia.jpg` is drawn by
  `tool/generate_sequoia_wallpaper.py`. Apple's own wallpaper artwork is
  copyrighted and is deliberately *not* mirrored here; the generator produces an
  original image in the same sunset/ridgeline language.
- **Unfocused windows recede.** The title bar dims and the shadow drops instead
  of the whole window fading out (which breaks Android platform views).

## Where the code lives

| Concern | File |
| --- | --- |
| Tokens (radii, metrics, system colours, glass) | `lib/core/macos_design.dart` |
| Window chrome, traffic lights, focus state | `lib/ui/window_frame.dart` |
| Menu bar blur | `lib/ui/status_bar.dart` |
| Dock glass | `lib/ui/dock.dart` |
| Spotlight panel | `lib/ui/spotlight.dart` |
| Control Center modules | `lib/ui/control_center.dart` |
| System Settings sidebar + Performance page | `lib/ui/apps/settings_app.dart` |
| Wallpaper catalogue | `lib/core/wallpapers.dart` |

## Deliberately not done

- No third-party widget package is added to `pubspec.yaml`. The APK already
  carries a 1.28 GB rootfs; a parallel UI kit would duplicate the shell's
  window manager for no visual gain.
- macOS-only materials that Flutter cannot reproduce on Android (real vibrancy,
  live wallpaper tinting, per-window blur) are approximated only where the cost
  is bounded (menu bar, Dock, panels). Windows keep flat chrome.
