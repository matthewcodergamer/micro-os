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
