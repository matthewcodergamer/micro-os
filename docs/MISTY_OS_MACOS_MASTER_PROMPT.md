# Misty OS — macOS Experience & Engineering Master Prompt

Repository: https://github.com/matthewcodergamer/micro-os  
Target: ARM64 Android phone (including Galaxy A07 / Android 16 / 4 GB RAM)

## Mission

Make Misty OS a polished macOS-inspired mobile workstation while preserving its defining capability: a real Linux userspace and real developer tools running on Android.

Use these repositories as reference implementations:

- https://github.com/Musheer360/macos-sequoia-clone — Sequoia desktop shell, window manager, Dock magnification/bounce, menu bar, Finder presentation, Launchpad, Spotlight, Mission Control, context menus, tiling, shortcuts.
- https://github.com/LikhithSP/MacOS-Web-Simulator — boot/setup flow, login/lock screen, desktop reveal, Finder/Notes/Settings presentation, Dock, top bar, app transitions.
- https://github.com/matthewcodergamer/micro-os — authoritative implementation for Flutter, Android lifecycle, PRoot, Linux filesystem, PTY, browser, VNC/noVNC, OpenCode, credentials, and CI.

The two reference repositories are React/TypeScript web simulations. Do not merge their React apps wholesale into Flutter, embed them in a WebView as the OS shell, or replace real Linux functionality with fake browser/localStorage demos. Port suitable UI patterns, assets, animation timings, interaction models, and layouts into native Flutter widgets. Preserve attribution and licenses. Inspect each repository's license and asset provenance before copying anything.

## Non-negotiable architecture

1. Flutter is the native Android shell: windows, Dock, menu bar, Settings, login, Finder UI, and touch controls.
2. PRoot Ubuntu is a Linux userspace sharing Android's kernel, not a separate kernel or VM.
3. Terminal remains connected to a real PTY in the Linux guest.
4. Finder browses real guest and Android-shared files, not an in-memory fake filesystem.
5. Browser launches a real Linux desktop browser inside X11/noVNC. Do not substitute a Flutter WebView or simulated Safari.
6. OpenCode works with real project files and terminal; GitHub/Hugging Face credentials must not be exposed.
7. Android Home, Back, and recents gestures must remain usable. Never hijack system edge gestures.
8. Optimize for a 4 GB phone without sacrificing correctness or essential features.

## Phase 0 — Audit before editing

- Fetch latest main; inspect working tree, branches, open PRs, recent commits, and active Actions runs.
- Inspect the full source trees and licenses of both reference repositories. Record suitable components, assets, and interaction patterns.
- Inspect app/icon registries, window state/frame, Dock, menu bar, wallpaper, login/install screens, Finder, terminal, desktop session, Settings, LinuxRuntime, Android manifest/bootstrap, rootfs scripts, and workflows.
- Identify existing implementations and tests before editing. Reuse them; do not create duplicate app registries, window managers, PTYs, or services.
- Produce a feature/file/status/test audit matrix. Preserve user changes.

## Phase 1 — Visual system, wallpapers, and glass

Wallpaper sources:
- https://github.com/benediktkr/Deeeee-macOS-Wallpapers
- https://github.com/moonlitcat2022/macOS-Modern-Wallpapers

Inspect licenses, source URLs, dimensions, and file sizes before bundling. Prefer high-resolution sources but generate device-sized variants. Store approved assets under assets/wallpapers and declare them in pubspec.yaml. Add Settings → Wallpaper with preview, categories, and persistent selection using the existing settings store where possible. Include at least 10 legally usable wallpapers if licensing and APK size permit. Decode to display dimensions and avoid loading many full-resolution images at once.

Create a consistent macOS-inspired material system for Dock, menu bar, title bars, Control Center, context menus, and dialogs: translucency, subtle borders/highlights, background blur, depth, rounded geometry, and readable contrast. The wallpaper should visibly show through the glass. Evaluate real_liquid_glass and liquid_glass_widgets for Android support, maintenance, shader cost, and compatibility before adopting them; native iOS/macOS-only behavior does not meet Android requirements. Prewarm shaders only if required and measure first-frame cost. Keep blur sigma at or below 15 on the 4 GB target unless measurements justify otherwise. Provide a reduced-effects fallback.

## Phase 2 — macOS shell behavior

### Desktop, Dock, menu bar

Port useful behavior from both references:
- Dynamic menu bar showing active app name and contextual File/Edit/View menus.
- Apple-style system menu: About, Settings, Lock, Sleep, Restart, Shut Down.
- Restart/shutdown confirmation; no destructive action without explicit confirmation.
- Centered, horizontally scrollable Dock on phones; cosine neighbor magnification, pointer tooltip, one-shot launch bounce, running-app indicators, minimized-window restore, configurable size, optional auto-hide.
- Launchpad, Spotlight search/calculator, Mission Control/window overview, notifications, context menus, and touch equivalents for desktop actions.
- Centralized IconRegistry; coherent icon family and sizing. Replace mismatched launcher/app icons with a consistent Misty OS identity. Preserve licenses and attribution.
- Every Dock icon launches a real app implementation; no dead icons or white placeholder screens.

### Window manager and chrome

- Three 12px traffic lights on the leading edge: red close, yellow minimize, green maximize/zoom. Reveal symbols on hover/focus with about 150ms fade and provide touch feedback.
- Correct close/minimize/maximize/restore; no ghost windows or blocked state.
- Drag, resize, focus, z-order, double-click title bar to zoom, restore prior geometry.
- Snap to halves/quarters with preview; cancellation restores original geometry.
- Use spring/rubber-band feedback only when responsive on touch.
- Cmd/Ctrl+W closes focused window; Cmd/Ctrl+Q is a distinct app-level quit/return flow.
- On narrow portrait screens use deliberate full-screen/mobile presentation, not tiny overlapping windows. On landscape/tablet use desktop-style overlapping windows.
- Reposition windows and Dock safely on rotation. Do not reintroduce the AnimatedPositioned/RepaintBoundary layout bug.

### Android navigation

Respect SafeArea and MediaQuery.viewPadding. Keep the Dock above the system gesture area with enough spacing. Do not block Home, Back, or recents gestures or claim Flutter can override Android. Offer a Show/Hide Dock setting and, if useful, an immersive/status-bar preference while keeping a reliable route to system navigation. Test gesture and three-button navigation if available.

## Phase 3 — Boot, install, login, lock

- Native-feeling boot/initialization animation with Misty OS branding.
- First-run install screen with actual extraction bytes / total bytes progress, not a fake percentage.
- Show a finishing state while permissions/setup complete.
- On success fade into login; on failure show actionable error and Retry without destroying valid installed data.
- Login/lock screen with wallpaper/parallax, avatar/profile, clock, password/PIN field, reveal toggle, wrong-password shake, haptics, and successful unlock transition.
- Show login on cold start when configured; retain safe recovery if authentication storage is unavailable.
- Secure credential storage; never log secrets.
- Dispose animation controllers and avoid expensive effects during boot.

## Phase 4 — Finder and real file workflow

Finder must use LinuxRuntime/storage APIs:
- Sidebar: Home, Downloads, Desktop, Documents, Pictures, Android shared storage, favorites.
- Grid/list views, sorting, search, breadcrumbs, back/forward, hidden files, metadata, safe preview.
- Create folder/file, rename, copy, move, delete/trash where supported, restore, multi-select.
- Verify the actual Android shared mount path from scripts; do not assume it.
- Browser downloads must be visible to Finder and OpenCode through one verified shared Downloads location. Verify Chromium/Firefox preferences and PRoot bind mounts.
- Virtualize large directory listings; do not load file contents just to list names.

## Phase 5 — Real browser and automation

### Visible browser

- Keep the genuine Linux browser inside X11/Openbox and displayed through noVNC.
- Provide real desktop browser chrome: tabs, new/close/switch tab, address/search bar, back/forward/reload/home, bookmarks, downloads, zoom, and engine selection only where engines are actually installed.
- It must look and behave like a desktop browser, not a mobile toolbar around a page.
- Configure downloads to the verified shared Android Downloads directory and test OpenCode can read/edit/extract/run downloaded files.
- Discover actual browser packages in the ARM64 rootfs. A launcher script is not proof of installation.
- Tune Chromium/QtWebEngine conservatively. Never force-disable software rasterization unless a working GPU path is proven.
- Tune x11vnc/noVNC only after measuring. Validate flags against installed versions; do not blindly use undocumented speed tuples or query parameters.
- Measure input-to-display latency, FPS, CPU, memory, and image quality. Fast Starlink throughput does not remove X11/VNC rendering overhead.

### Headless automation

- Add Playwright for OpenCode only if Node and browser dependencies work in the actual ARM64/PRoot environment.
- Verify install and headless launch in CI/rootfs; npm install alone is not proof.
- Prefer compatible system browser binaries if Playwright's downloaded browser is too large or incompatible.
- Bound headless processes and clean them up. Test navigation, screenshot, DOM extraction, and download to shared Downloads.

## Phase 6 — Terminal and OpenCode

### Terminal

- One real PTY per tab; support installed shells such as bash, Python, and Node.
- Tabs create/close/rename/switch; closing disposes the correct PTY and UI state immediately.
- Finger scrolling, two-finger history scroll, selection, copy, paste, shortcuts.
- Large paste must not freeze UI: queue input, chunk without splitting Unicode code points, apply PTY backpressure, and never press Enter after paste.
- Process large payloads off the UI isolate where appropriate. Avoid repeated huge string copies.
- Bound scrollback (target ≤1,000 lines) and output queues.
- Shift+PageUp/PageDown scrollback; visual bell on BEL; preserve UTF-8.
- Test 5 KB, 50 KB, multiline, emoji, source code, paste during output, reconnect, and cancellation.

### OpenCode and developer workflow

- OpenCode accesses the same project directories and Downloads as Finder and browser.
- Preserve working directory and project files across sessions.
- Bound command retries and filter noisy progress output without hiding real diagnostics.
- Avoid rereading whole repositories/files unnecessarily; inspect targeted functions.
- Require confirmation for destructive operations and expensive multi-stage work, not every harmless test.
- Verify the installed OpenCode version's actual /clear command; do not invent commands.
- Add GitHub CLI and Hugging Face CLI only if ARM64 install paths/versions are verified.
- Store GitHub/Hugging Face tokens using Android secure storage/keystore. Never store tokens in plaintext preferences, source, logs, or commits.
- Pass secrets via secure stdin/environment/restricted temporary files where supported; avoid shell interpolation and delete temporary secrets.
- Use least-privilege scopes. Provide test-auth/disconnect guidance and status without displaying token values.

## Phase 7 — macOS behavioral quirks

Implement in separate logical commits/PRs where practical:

1. Traffic lights: hover/focus symbols, correct actions, disabled state.
2. Dock: cosine magnification, tooltip pointer, one-shot bounce, open-app dot, optional ~1s auto-hide, reveal on edge touch.
3. Terminal: safe large paste, Shift+PageUp/PageDown, no auto-execute, visual bell.
4. Window tiling: half/quarter snap, preview, cancellation, restore.
5. Menu bar: active-app menus, system menu, restart/shutdown confirmation.
6. Responsiveness: title-bar double-click zoom, distinct close/quit shortcuts, safe drag bounds/inertia.

Do not replicate macOS's cooked-mode 1,024-byte paste limitation as a bug. Use queued/raw PTY delivery where needed and restore terminal mode safely.

## Phase 8 — Performance and reliability

- Measure PSS/RSS, CPU, frame timing, disk use, rootfs size, and browser memory.
- Use const constructors, isolate rebuilds, dispose controllers/listeners, virtualize lists, cache images responsibly.
- Bound blur/effects; avoid rebuilding the entire desktop during Dock animation.
- Prevent duplicate PRoot, X11, Openbox, VNC, websockify, browser, and OpenCode processes.
- Supervise processes with bounded restart/backoff and useful logs.
- Add Android foreground service only with correct target-SDK permissions/types and explicit stop control. It improves background reliability but cannot defeat force-stop or every OEM policy.
- Never claim physical-device testing unless performed on the actual device.
- No unsupported claims of 60 FPS, hardware acceleration, native-speed browsing, or zero crashes.

## Phase 9 — Tests and release

Run supported checks:

~~~bash
flutter pub get
dart format --output=none --set-exit-if-changed lib
flutter analyze
flutter test
bash -n tool/setup.sh
bash -n tool/prebake_rootfs.sh
bash -n tool/bootstrap_android.sh
flutter build apk --release --target-platform android-arm64
~~~

Also:
- Add unit/widget/integration tests for window state, Dock, terminal paste, file operations, install progress, and settings persistence.
- Validate ARM64 rootfs packages and browser startup.
- Validate X11 → Openbox → VNC → websockify → noVNC and actual pointer/keyboard input.
- Verify APK artifact, size, SHA-256, and upload.
- Inspect active Actions runs before pushing; do not accidentally cancel useful builds.
- Fix actual failures; do not suppress diagnostics.
- Review diffs for secrets, generated files, accidental large binaries, and license compliance.

## Acceptance checklist

- [ ] Latest main audited; both reference repositories and licenses inspected.
- [ ] Native Flutter macOS-style shell is coherent and responsive.
- [ ] Dock magnification, tooltip, bounce, indicators, auto-hide work.
- [ ] Menu bar follows focused app; system menu and confirmations work.
- [ ] Finder reads/writes real Linux and Android-shared files.
- [ ] Terminal is a real PTY with tabs, scrollback, clipboard, Unicode, safe large paste.
- [ ] OpenCode edits/runs files in shared project and Downloads directories.
- [ ] Real Linux desktop browser works in noVNC with tabs/navigation/downloads.
- [ ] Headless Playwright verified on target architecture, or documented tested fallback.
- [ ] Login, lock, install progress, retry, and transitions work.
- [ ] Wallpaper picker persists selection; assets have verified licensing.
- [ ] Android Home/Back/recents remain usable.
- [ ] No tested keyboard flicker, stuck overlays, ghost windows, or blocked close buttons.
- [ ] Rotation does not crash.
- [ ] Flutter analysis/tests pass; ARM64 APK and checksum recorded.
- [ ] Physical-device results are clearly separated from CI results.

## OpenCode execution protocol

1. Read this entire document.
2. Audit latest main and both reference repositories. Report a concise feature/file/status matrix before editing.
3. Create a feature branch from latest main; preserve user work.
4. Implement in small, testable commits. Prioritize core workflows before decorative polish.
5. Run focused tests after each logical phase and record evidence.
6. Open a PR to main. Do not force-push or merge over failing checks.
7. Monitor Actions, inspect logs, fix regressions, rebuild.
8. Deliver PR URL, commit SHA, changed-file summary, test evidence, known limitations, APK artifact/release link, APK size, and SHA-256.
9. For anything blocked by Android, PRoot, package, hardware, license, or CI limits, explain the exact blocker and provide the best tested alternative. Never fake completion.

**Start now. Do not stop at planning.**
