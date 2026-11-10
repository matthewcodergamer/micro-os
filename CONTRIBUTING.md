# Contributing to MicroOS

Thanks for your interest in contributing. MicroOS is an experimental Flutter shell for a Linux desktop environment on Android. Contributions that improve reliability, documentation, accessibility, performance, and platform support are welcome.

## Before you start

1. Read the [README](README.md), especially **What actually works, and what does not**.
2. Check existing issues and pull requests before starting a large change.
3. For substantial work, open an issue first so the scope and approach can be discussed.
4. Keep changes focused. Avoid unrelated refactors in feature or bug-fix pull requests.

## Development setup

You will need:

- Flutter stable and the Dart SDK version accepted by `pubspec.yaml`
- Android SDK/NDK for Android builds
- Xcode on macOS for iOS shell builds
- Bash, curl, tar, dpkg-deb and Python 3 for preparing the Android guest runtime

Install dependencies:

```sh
flutter pub get
```

For a local Android build, prepare the bundled runtime and Android project:

```sh
./tool/fetch_runtime.sh
./tool/bootstrap_android.sh
flutter build apk --release --target-platform android-arm64
```

For an iOS shell build on macOS:

```sh
./tool/bootstrap_ios.sh
flutter pub get
flutter build ios --release --no-codesign
```

The iOS target currently packages the Flutter shell only. It does not run the local proot/Linux guest; see the README for the platform constraints and intended remote-backend direction.

## Pull request checklist

Before opening a pull request:

- [ ] Explain the user-visible problem and the behavior changed.
- [ ] Keep platform-specific code isolated where practical.
- [ ] Update README or other documentation when behavior, setup, or limitations change.
- [ ] Add or update tests for logic that can be tested independently.
- [ ] Run `dart format .`.
- [ ] Run `flutter analyze --no-fatal-infos --no-fatal-warnings`.
- [ ] Run the relevant build or test command when your environment supports it.
- [ ] Do not commit generated build output, downloaded root filesystems, credentials, tokens, or signing keys.

## Security and credentials

Never include GitHub Personal Access Tokens, passwords, private keys, keystore files, provisioning profiles, or other secrets in source code, logs, screenshots, or pull requests. Use test credentials with the minimum required permissions, and rotate any credential that may have been exposed.

Please report security vulnerabilities privately to the repository maintainer rather than opening a public issue containing exploit details.

## Architecture and platform notes

- The Flutter UI is under `lib/`; keep the desktop/window-management layer separate from runtime implementations.
- Android uses a proot guest and shares the Android host kernel. The guest cannot load kernel modules or enable ZRAM.
- Ubuntu ARM64 commonly provides Chromium through Snap, which is not suitable for this proot setup. Falkon/QtWebEngine is the supported desktop-browser fallback.
- iOS restrictions prevent the current app from spawning its bundled Linux guest binaries. Do not describe the iOS shell artifact as a working local Linux environment.
- The X11 desktop is streamed through the in-app noVNC bridge; it is not a direct native X11 texture.

Please be respectful and constructive in issues and reviews. Small, reproducible bug reports are especially helpful.
