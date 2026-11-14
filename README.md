# Misty OS — Master Engineering Task List

**Repository:** [matthewcodergamer/micro-os](https://github.com/matthewcodergamer/micro-os)  
**Primary branch:** `main`  

## Why Misty OS?

Misty OS is lightweight, highly optimized for mobile, and leverages the cloud so you can code anywhere. It is designed as a mobile-friendly Linux workstation with a calm, airy interface.

**Target device:** Samsung Galaxy A07 · Android 16 · 4 GB RAM · ARM64

## Mission

Improve Misty OS into a stable, mobile-friendly Linux desktop experience running on Android.

Work directly in the existing repository. Inspect the implementation before changing it, preserve working features, fix the critical memory problem first, and deliver a verified Android APK through GitHub Actions.

Do not stop after writing a plan. Implement, test, and document the work.

---

## 1. Project overview

MicroOS is a Flutter-based Android desktop environment with a macOS-inspired Golden Gate interface.

Its architecture includes:

- Flutter: desktop interface, windows, Dock, settings and terminal UI.
- PRoot: Ubuntu 24.04 ARM64 Linux userspace.
- X11/Openbox: Linux graphical desktop.
- VNC/noVNC: remote desktop display inside MicroOS.
- OpenCode: AI coding agent running inside the Linux environment.
- PTY/xterm: interactive Linux terminal.
- TTS bridge: Android text-to-speech integration for OpenCode.
- GitHub Actions: Linux root filesystem preparation and Android APK builds.

This is a Linux userspace running through PRoot, not a separate Linux kernel.

## 2. Priority 1 — Fix the terminal memory crash

**This is the first task.**

### Problem

Pasting large blocks of text into the MicroOS terminal can freeze the application or cause it to crash. Investigate the actual source of memory pressure rather than assuming one component is responsible.

### Inspect

- `lib/ui/apps/terminal_app.dart`
- `lib/services/linux_runtime.dart` (PTY input and terminal output handling)

### Required implementation

1. Chunk large pastes into approximately 500-character blocks.
2. Preserve Unicode correctly; never split a UTF-8 sequence or UTF-16 surrogate pair.
3. Deliver chunks through a queue with a small configurable delay.
4. Add PTY backpressure so input is not flooded faster than it can be consumed.
5. Keep Flutter responsive during large pastes.
6. Limit terminal scrollback to no more than 1,000 lines.
7. Bound output queues, temporary strings and other buffers.
8. Handle cancelled pastes, disconnected PTYs and failed writes safely.

Do not corrupt newlines, shell commands, Unicode characters or pasted code.

### Tests

Test ordinary commands, large blocks, multiline commands, Unicode and emoji, long code snippets, pastes during terminal output, and pastes after reconnecting to a terminal session.

**Success:** Large pastes no longer freeze MicroOS, and normal terminal interaction remains responsive.

## 3. Priority 2 — Android background execution

### Problem

OpenCode and the Linux environment should continue working when the user switches to YouTube or another Android application. Inspect process ownership and lifecycle; keeping a Flutter screen alive does not automatically keep the Linux workload alive.

### Required implementation

Implement a native Android foreground service with:

- A persistent notification showing that MicroOS has an active session.
- A deliberate way to stop the session and a way to return to MicroOS.
- Correct Android permissions and foreground-service configuration for the actual target SDK.
- Flutter communication through a MethodChannel or equivalent.
- Safe service startup, shutdown and reconnection.

Inspect `tool/bootstrap_android.sh` and the generated Android project. Ensure generated Android changes survive future bootstrap runs.

### Process supervision

Supervise PRoot, OpenCode, active terminal processes, X11/Openbox, x11vnc, websockify and installed browsers.

Implement:

- Process state tracking and unexpected-exit detection.
- Bounded restart attempts with backoff.
- Useful diagnostic logs and exit status.
- Session-state persistence and UI reconnection.
- Duplicate-process prevention.

Ordinary app switching, activity recreation and screen transitions must not deliberately terminate active Linux sessions.

Use a wake lock only when genuinely needed. Avoid unnecessary battery drain.

**Android limitation:** A foreground service improves background reliability but cannot guarantee that Android will never terminate an application. Force-stop, exceptional memory pressure and manufacturer restrictions can still interrupt it. Implement recovery and session persistence; do not promise zero crashes.

### Required device test

On the actual Samsung Galaxy A07:

1. Start MicroOS, Linux and OpenCode.
2. Begin a task that produces continuing output.
3. Press Home, open YouTube and play a video.
4. Leave MicroOS in the background for at least 10 minutes.
5. Return and verify that the session is still active or recovers correctly.
6. Repeat with the screen locked and Battery Saver enabled.

Record what was physically tested. Never claim a device test passed unless it was actually performed.

## 4. Priority 3 — VNC virtual trackpad

Inspect `lib/ui/apps/desktop_session_app.dart`. Finish the existing implementation without discarding working code.

### Trackpad mode

- One-finger drag moves a visible remote cursor.
- Tap performs a left-click.
- Long-press performs a right-click.
- Two-finger movement produces scrolling.
- Cursor coordinates remain correct after resizing and reconnecting.
- Touch cancellation releases all active mouse buttons.

### Direct-touch mode

Provide an alternative mode where tapping and dragging map directly to remote desktop coordinates.

### Validation

Test the actual noVNC desktop: left-click, right-click/context menus, cursor movement, two-finger scrolling, mouse down/up pairing, stuck-button prevention, reconnection and orientation changes.

JavaScript compilation alone does not prove remote input works.

## 5. Terminal touch controls

Inspect `lib/ui/apps/terminal_app.dart` and finish the existing long-press selection and clipboard implementation.

Required:

- Long-press text selection.
- Copy selected text to Android clipboard.
- Paste clipboard contents into the PTY.
- Two-finger vertical scrolling through terminal history.
- Correct handling of multiple simultaneous pointers.
- No accidental shell input during scrolling.
- Preserve UTF-8 output handling.

Test selection and clipboard behavior with long commands, file paths, multiline text and Unicode.

## 6. Linux desktop and browser reliability

Inspect:

- `lib/services/linux_runtime.dart`
- `tool/setup.sh`
- `tool/prebake_rootfs.sh`

Verify the complete desktop startup sequence:

1. Xvfb/X11 display `:1`.
2. Openbox.
3. x11vnc on port `5900`.
4. websockify/noVNC on port `6080`.
5. Browser attached to the correct display.

A listening port alone does not prove that the desktop works.

### Browser requirements

Verify which browsers are actually installed. Test browser launch, display inside noVNC, HTTPS loading, closing and reopening, duplicate-process prevention, and useful failure logs.

Do not assume Chromium or Firefox is installed merely because a launch script exists. Inspect the root filesystem and packaging method.

### OpenCode TTS

Inspect:

- `lib/services/opencode_tts_server.dart`
- `tool/opencode-tts-plugin.js`

Verify the bridge at `127.0.0.1:17842`. Test the `/speak` endpoint from inside PRoot and confirm actual connectivity rather than assuming Android and PRoot share loopback networking.

Preserve the existing UTF-8 terminal improvements.

## 7. Preserve and optimize the interface

MicroOS should retain its macOS-inspired appearance.

Inspect:

- `lib/core/theme.dart`
- `lib/ui/dock.dart`
- `lib/ui/wallpaper.dart`
- `lib/ui/window_frame.dart`

Preserve Inter typography, existing Dock artwork, Big Sur/Tahoe wallpaper integration, Dock magnification and touch interaction, window management, animations and visual styling.

### Performance requirements

For the 4 GB Android target:

- Keep Dock repaint isolation using `RepaintBoundary`.
- Keep backdrop blur sigma at or below 15.
- Avoid rebuilding the entire desktop during Dock animation.
- Decode wallpapers at appropriate screen dimensions.
- Avoid unnecessarily loading full-resolution images.
- Keep image and terminal buffers bounded.
- Avoid duplicate Linux desktops and unnecessary browser processes.
- Avoid unnecessary background timers and animations.

Inspect `tool/optimize_dock_icons.py`. Verify Dock icons are optimized to approximately 128 × 128 while preserving transparency and aspect ratio.

Do not remove visual features simply to make performance measurements look better.

## 8. GitHub Actions — Larger build runners

Inspect `.github/workflows/build-android.yml`.

The project needs reliable ARM64 rootfs preparation and Android APK packaging.

### Runner selection

Inspect the actual GitHub runner options available to this repository.

- Use a suitable native ARM64 runner for Linux rootfs preparation.
- Use a sufficiently large x64 runner for Flutter and Android packaging.
- Target at least 16 GB RAM when available.
- Use a 60 GB runner only if the account actually has access to one.

Do not assume `ubuntu-latest` automatically means 16 GB RAM. Do not invent runner labels or select unavailable machines.

Inspect the existing configuration: `MICROOS_ARM_RUNNER` and `MICROOS_MIN_RAM_GIB`. Retain compatible defaults if larger runners are unavailable.

### Build reliability

Improve disk-space checks, memory checks, dependency caching, rootfs archive validation, artifact transfer, APK packaging and failure diagnostics.

Preserve all required Linux packages and ARM64 libraries.

Print available RAM, available disk space, APK file size and APK SHA-256 checksum.

The APK may be large because it includes the Linux environment. Do not silently remove required components to reduce its size.

Before pushing, inspect active Actions runs. Avoid unintentionally cancelling a useful build through workflow concurrency.

## 9. Execution sequence

### Phase A — Audit

- Pull the latest `main`.
- Inspect recent commits and the working tree.
- Inspect terminal paste and output handling.
- Inspect Android lifecycle and process ownership.
- Inspect the VNC input bridge.
- Inspect Linux startup and browser packaging.
- Inspect the current GitHub Actions workflow.

Preserve uncommitted user changes.

### Phase B — Critical memory fix

- Implement chunked paste.
- Add PTY backpressure.
- Bound scrollback to 1,000 lines.
- Bound output buffers.
- Add tests for large pastes and Unicode.

### Phase C — Background service

- Implement the native Android foreground service.
- Integrate it with Flutter and LinuxRuntime.
- Add process supervision and recovery.
- Test ordinary app switching and reconnection.

### Phase D — Touch controls

- Finish VNC trackpad.
- Finish direct-touch mode.
- Implement terminal two-finger scrolling.
- Validate clipboard and selection.

### Phase E — Linux reliability

- Validate X11/VNC/noVNC.
- Validate browser launch.
- Validate OpenCode.
- Validate TTS.
- Fix startup races and duplicate processes.

### Phase F — Performance

- Verify wallpaper decoding.
- Verify Dock rendering.
- Verify icon optimization.
- Measure memory and CPU where possible.

### Phase G — Build and delivery

Run:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib
flutter analyze
flutter test
bash -n tool/setup.sh
bash -n tool/prebake_rootfs.sh
bash -n tool/bootstrap_android.sh
```

Fix errors introduced by the changes. Do not suppress errors just to obtain a green build.

Review the final diff, commit the work, push to `main`, and monitor the resulting GitHub Actions run.

If a build fails:

1. Retrieve the failing job logs.
2. Identify the actual failure.
3. Fix the problem.
4. Commit and rebuild.
5. Continue until the build succeeds or a genuine external blocker is identified.

## 10. Definition of done

- [ ] Large terminal pastes no longer freeze MicroOS.
- [ ] Unicode and multiline pastes remain correct.
- [ ] Terminal scrollback is limited to 1,000 lines.
- [ ] Terminal output buffers are bounded.
- [ ] Android foreground service is implemented.
- [ ] Active Linux/OpenCode sessions survive ordinary app switching or recover correctly.
- [ ] Process supervision and reconnection work.
- [ ] VNC cursor and trackpad gestures work.
- [ ] Right-click and two-finger scrolling work.
- [ ] Terminal selection, copy and paste work.
- [ ] Linux desktop and noVNC start reliably.
- [ ] Installed browser launches inside the guest.
- [ ] OpenCode TTS bridge works from PRoot.
- [ ] Existing interface artwork and performance optimizations are preserved.
- [ ] `flutter analyze` passes.
- [ ] Tests pass.
- [ ] GitHub Actions completes successfully.
- [ ] Final ARM64 APK is verified.

## 11. Final report

When finished, provide:

1. Summary of implemented changes.
2. Files changed.
3. Terminal memory fix and test results.
4. Background-service implementation and device-test results.
5. Trackpad and terminal gesture test results.
6. Linux desktop and browser test results.
7. `flutter analyze` and test results.
8. Final commit SHA.
9. GitHub Actions run link and status.
10. Verified APK download link, file size and SHA-256.

Clearly distinguish automated tests from physical-device tests.

---

## FINAL DIRECTIVE TO OPENCODE

Read this README completely before beginning.

Pull the latest `main`, inspect the existing project, and execute the tasks in priority order.

Fix the terminal memory and large-paste crash first. Then implement Android background execution, process recovery, touch controls and the remaining reliability improvements.

Do not merely produce a plan or recommendations. Make the changes, run the tests, push the code, monitor GitHub Actions and deliver the verified ARM64 APK.

Do not claim a feature works unless you have evidence. Do not stop while actionable build failures remain.


---

# Existing project documentation

> The following project reference is retained from the previous README so setup instructions and current alpha limitations are not lost while the engineering task list becomes the primary README.

# MicroOS

**MicroOS is an early alpha.** It is experimental software under active development. Expect bugs, incomplete features, performance issues, and possible data loss. It has not yet been validated across Android devices. Install and test at your own risk; back up important files first.

A Flutter shell that runs an Ubuntu userspace on Android, with a macOS-style
window manager, a PTY terminal, a desktop browser, and a developer toolchain
(Python, Node, Rust, git, GitHub CLI, OpenCode).

**Requirements:** an ARM64 Android device, a reliable Wi-Fi connection for the
first Linux installation, and **at least 1 GB of free storage** (more is
recommended because package downloads and unpacked files need space).

The UI and the Linux guest are deliberately separated: `lib/` is pure Flutter,
`tool/setup.sh` is pure bash running inside the guest.

---

## Alpha status and Known Limitations

MicroOS is an early alpha, not a finished or production-ready operating
system. The Android APK is an experimental sideload build. The app's Linux
guest runs in userspace through proot; it does **not** boot a separate Linux
kernel.

- **Device compatibility and performance:** tested behavior may vary by
  Android version, device memory, storage speed, and manufacturer restrictions.
  Heavy desktop or browser workloads may be slow, use substantial memory,
  increase battery use, or cause heat.
- **Storage and network:** first-run Linux provisioning downloads roughly
  700 MB–1.2 GB of packages. Use Wi-Fi and have at least 1 GB free before
  starting; additional working space is recommended.
- **Browser:** MicroOS installs **Falkon**, not the Ubuntu Chromium Snap.
  Chromium on Ubuntu arm64 is distributed as a snap, and snapd cannot run
  inside this proot environment. Falkon is a desktop browser using
  QtWebEngine (Chromium's Blink renderer and V8 engine).
- **ZRAM:** MicroOS cannot enable or configure kernel ZRAM. The proot guest
  shares Android's kernel and lacks the privileges required to manage swap.
  The app can display host memory/swap information, but it does not control
  the device's ZRAM configuration.
- **iOS:** iOS is currently a **UI shell only**. The workflow can package an
  unsigned shell IPA for experimentation, but the local Linux/proot backend
  does not run on iOS. A working Linux guest on iOS is not available.
- **Mobile window layout:** on narrow phone screens, windows use a
  full-screen/mobile presentation rather than overlapping draggable desktop
  windows. Desktop-style window management is intended for wider displays.
- **Security and distribution:** Android builds are debug-signed and intended
  for sideload testing. The current target SDK configuration is not
  Play-Store compliant. Treat credentials and device data carefully; do not
  use this alpha for sensitive workloads.

Please report reproducible bugs with your device model, Android version,
steps to reproduce, and relevant logs. Do not include passwords, access
tokens, or other secrets in issue reports.

---

## What actually works, and what does not

This matters more than the feature list, because several claims that circulate
about "Linux on a phone" are not true. Here is the honest version.

| Feature | Status |
| --- | --- |
| macOS-style shell: menu bar, Dock, draggable/resizable windows, snap-to-fullscreen on phones | Implemented; mobile layout is full-screen |
| Terminal (real PTY inside the guest, xterm rendering) | Implemented |
| Ubuntu 24.04 arm64 guest via proot | Implemented on Android |
| Developer toolchain installed on first boot | Implemented |
| Android storage visible inside the guest at `/mnt/android` | Implemented (needs All-files access) |
| GitHub PAT → `git credential.helper store` | Implemented |
| Desktop browser inside X11 | Implemented with Falkon; see below |
| X11 desktop rendered in a Flutter window | Implemented via noVNC, not via a native X surface |
| ZRAM enabled by the app | **No** — see "ZRAM" below |
| iOS build with a Linux guest | **No** — see "iOS" below |

### Falkon instead of Chromium

Ubuntu arm64 ships Chromium **only as a snap**, and snapd cannot run inside
proot. So `apt-get install chromium` cannot work on Ubuntu, no matter which
flags are passed.

The app installs **Falkon** instead: a real desktop browser, packaged as a
normal `.deb`, built on **QtWebEngine — which is Chromium's Blink renderer and
V8 engine**. It is not a WebView wrapper and it is not a mobile browser.

The memory flags still apply. Falkon receives the Chromium flags through
`QTWEBENGINE_CHROMIUM_FLAGS`. `--single-process` is available as an opt-in
toggle in Settings because upstream deprecated it and it crashes on many
pages — `--renderer-process-limit=1` gets most of the memory benefit without
the crashes.

### X11

Rendering an X11 server directly into a Flutter texture requires a native X
server (the way Termux:X11 does it). That is a native Android app, not
something a Flutter plugin can do. MicroOS therefore runs:

```
Xvfb :1  →  openbox  →  x11vnc  →  websockify  →  noVNC  →  WebView
```

Everything stays inside one APK, pointer and keyboard events map correctly,
and the desktop is a real desktop. The trade-off is a video-encoded surface
rather than raw pixels — that is the honest price of doing it without a
second app.

### ZRAM

ZRAM is a **kernel** feature. A proot guest shares Android's kernel and has
no `CAP_SYS_ADMIN`, so `swapon` returns `EPERM`. No script inside the guest
can enable it. Android manages ZRAM at the host level on devices that support
it. MicroOS displays available memory/swap information (including
`/proc/meminfo` and `/sys/block/zram0/mm_stat` when exposed); it does not
enable, disable, or tune ZRAM.

### iOS

Apple does not allow an app to `fork`/`exec` arbitrary binaries it ships,
and proot needs exactly that. The iOS workflow builds and packages the
**Flutter UI shell** as an unsigned `.ipa` for sideload experimentation, but
the Linux backend cannot run there. The architecture keeps that door open:
the UI talks to `LinuxRuntime`, so a remote backend (SSH to a real Linux
machine, or a hosted container) could be added without changing the window
manager. There is no working local Linux guest on iOS at this time.

---

## Building

### Cloud build (no local toolchain needed)

Push to `main`. GitHub Actions builds both targets:

* `Build Android APK` → `.github/workflows/build-android.yml`
* `Build iOS IPA (unsigned)` → `.github/workflows/build-ios.yml`

**Where to get the APK**

1. Open the repository on GitHub.
2. Click the **Actions** tab.
3. Select **Build Android APK** → the newest green run.
4. Download **MicroOS-apk** under *Artifacts* (you must be signed in to GitHub).
5. Or open **Releases** — every non-PR run attaches
   `MicroOS-<run>-arm64.apk` to a release tagged `apk-<run>`.

Install with `adb install -r MicroOS-…-arm64.apk`, or copy it to the phone and
allow "install unknown apps". This build is debug-signed and sideload-only; it
is not Play-Store compliant (targetSdk 28 is required for the current proot
execution arrangement).

### Local build

```bash
bash tool/fetch_fonts.sh   # JetBrains Mono bundled in the terminal APK
flutter pub get
./tool/fetch_runtime.sh      # rootfs + proot into assets/
./tool/bootstrap_android.sh  # generates android/ and patches the manifest
flutter build apk --release --target-platform android-arm64
```

`fetch_runtime.sh` needs `curl`, `tar`, `dpkg-deb` and `python3`.

---

## First run

1. Connect to Wi-Fi and confirm at least **1 GB of free storage** (more is
   recommended).
2. Launch the app → **Install Linux** (downloads roughly 700 MB–1.2 GB of
   packages; actual free-space needs can be higher while files are unpacked).
3. Grant **All files access** in Settings → Storage access.
4. Paste a GitHub PAT in Settings → GitHub. It is verified against the API,
   stored in the Android keystore, and written into the guest as
   `~/.git-credentials` with `credential.helper = store`. Only use a token
   with the minimum permissions you need, and revoke it if you suspect it
   has been exposed.
5. Open **Terminal**, **Desktop**, **Browser** or **AI Hub** from the Dock.

## Layout

```
lib/
  main.dart                     app bootstrap, AppScope, theme wiring
  app_scope.dart                dependency holder
  core/theme.dart               palette + layout constants
  models/window_state.dart      AppId, ManagedWindow
  state/desktop_state.dart      window list, z-order, move/resize/maximize
  services/
    linux_runtime.dart          rootfs install, proot launch, display, git creds
    system_stats.dart           battery / RAM / ZRAM / network polling
    github_auth.dart            PAT in keystore + API verification
    settings_store.dart         persisted preferences
  ui/
    desktop_screen.dart         wallpaper + window layer + chrome
    window_frame.dart           traffic lights, drag, resize grip
    status_bar.dart             menu bar with live stats
    dock.dart                   Dock
    install_screen.dart         first-run provisioning UI
    apps/                       terminal, desktop session, files, settings, AI hub
tool/setup.sh                   guest provisioning (apt, browser, X11, OpenCode)
tool/                           CI helpers (runtime fetch, platform scaffolding)
```
