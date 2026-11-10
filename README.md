# MicroOS

A Flutter shell that runs a real Ubuntu desktop on Android, with a macOS-style
window manager, a PTY terminal, a desktop browser, and a pre-installed developer
toolchain (Python, Node, Rust, git, GitHub CLI, OpenCode).

The UI and the Linux guest are deliberately separated: `lib/` is pure Flutter,
`tool/setup.sh` is pure bash running inside the guest.

---

## What actually works, and what does not

This matters more than the feature list, because several claims that circulate
about "Linux on a phone" are not true. Here is the honest version.

| Feature | Status |
| --- | --- |
| macOS-style shell: menu bar, Dock, draggable/resizable windows, snap-to-fullscreen on phones | Works, pure Flutter |
| Terminal (real PTY inside the guest, xterm rendering) | Works |
| Ubuntu 24.04 arm64 guest via proot | Works |
| Developer toolchain installed on first boot | Works |
| Android storage visible inside the guest at `/mnt/android` | Works (needs All-files access) |
| GitHub PAT → `git credential.helper store` | Works |
| Desktop browser inside X11 | Works, but see "Chromium" below |
| X11 desktop rendered in a Flutter window | Works via noVNC, not via a native X surface |
| ZRAM enabled by the app | **No** — see "ZRAM" below |
| iOS build with a Linux guest | **No** — see "iOS" below |

### Chromium

Ubuntu arm64 ships Chromium **only as a snap**, and snapd cannot run inside
proot. So `apt-get install chromium` cannot work on Ubuntu, no matter which
flags are passed.

The app installs **Falkon** instead: a real desktop browser, packaged as a
normal `.deb`, built on **QtWebEngine — which is Chromium's Blink renderer and
V8 engine**. It is not a WebView wrapper and it is not a mobile browser.

The memory flags still apply. Chromium accepts them on the command line; Falkon
receives the same set through `QTWEBENGINE_CHROMIUM_FLAGS`. `--single-process`
is available as an opt-in toggle in Settings because upstream deprecated it and
it crashes on many pages — `--renderer-process-limit=1` gets most of the memory
benefit without the crashes.

### X11

Rendering an X11 server directly into a Flutter texture requires a native X
server (the way Termux:X11 does it). That is a native Android app, not something
a Flutter plugin can do. MicroOS therefore runs:

```
Xvfb :1  →  openbox  →  x11vnc  →  websockify  →  noVNC  →  WebView
```

Everything stays inside one APK, pointer and keyboard events map correctly, and
the desktop is a real desktop. The trade-off is a video-encoded surface rather
than raw pixels — that is the honest price of doing it without a second app.

### ZRAM

ZRAM is a **kernel** feature. A proot guest shares Android's kernel and has no
`CAP_SYS_ADMIN`, so `swapon` returns `EPERM`. No script inside the guest can
enable it. Android already runs ZRAM on most devices; MicroOS shows the real
numbers in the menu bar (swap rows from `/proc/meminfo`, plus
`/sys/block/zram0/mm_stat` via `microos-mem`) instead of pretending to configure
it.

### iOS

Apple does not allow an app to `fork`/`exec` binaries it ships, and proot needs
exactly that. The iOS workflow builds and packages the **shell** as an unsigned
`.ipa` so it can be side-loaded, but the Linux backend cannot run there. The
architecture keeps that door open: the UI talks to `LinuxRuntime`, so a remote
backend (SSH to a real Linux machine, or a hosted container) can be dropped in
without touching the window manager.

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
is not Play-Store compliant (targetSdk 28 is required for proot to exec).

### Local build

```bash
flutter pub get
./tool/fetch_runtime.sh      # rootfs + proot into assets/
./tool/bootstrap_android.sh  # generates android/ and patches the manifest
flutter build apk --release --target-platform android-arm64
```

`fetch_runtime.sh` needs `curl`, `tar`, `dpkg-deb` and `python3`.

---

## First run

1. Launch the app → **Install Linux** (~700 MB – 1.2 GB of packages; use Wi-Fi).
2. Grant **All files access** in Settings → Storage access.
3. Paste a GitHub PAT in Settings → GitHub. It is verified against the API,
   stored in the Android keystore, and written into the guest as
   `~/.git-credentials` with `credential.helper = store`.
4. Open **Terminal**, **Desktop**, **Browser** or **AI Hub** from the Dock.

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
