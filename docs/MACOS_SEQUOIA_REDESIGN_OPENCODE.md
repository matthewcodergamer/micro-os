# MicroOS — macOS Sequoia Shell Redesign (OpenCode Implementation Brief)

> Goal: replace the current generic Linux-looking Flutter shell with a cohesive, high-fidelity macOS Sequoia-inspired desktop while preserving MicroOS's real Linux runtime, applications, and Android compatibility. This is an implementation brief, not permission to ship a static mockup.

## Reference projects and reuse rules

Study these projects before changing UI architecture:

1. **ThanasOS** — https://github.com/Thanas-R/thanas-os — MIT-licensed React macOS shell with a substantial componentized desktop, window manager, menu bar, Dock, Launchpad, Control Center, Spotlight, cursors, wallpaper handling, and app registry. Use it as the primary architectural/interaction reference. Its current README describes a Tahoe-style visual language, so adapt the interaction patterns and visual tokens to Sequoia rather than copying its Tahoe styling.
2. **Musheer360/macOS Sequoia Web Clone** — https://github.com/Musheer360/macos-sequoia-clone — inspect as a Sequoia visual/interaction reference. The repository currently reports one commit and no visible license in its repository header; do not copy or vendor its source/assets unless a valid license is verified. Use screenshots/behavior as research only.
3. Preserve MicroOS's Flutter-native application/runtime architecture. Do not embed a React desktop inside a WebView, replace the Linux desktop/runtime with a simulated browser filesystem, or replace real apps with fake UI.

Use only code/assets with compatible, verified licenses. Do not copy Apple's proprietary source code, trademarks as product branding, or unlicensed wallpapers/icons. Use original or permissively licensed assets and record attribution/license notices.

## Current observed problems (from user screenshots)

- Menu bar and system status area look like a generic Linux toolbar; spacing, typography, iconography, and proportions are wrong.
- Control Center is a crude grid of generic cards rather than a refined, compact macOS-style panel.
- Dock is oversized/poorly proportioned for a portrait Android display and lacks convincing macOS behavior.
- Finder and System Settings are visually inconsistent and incomplete.
- Launchpad has placeholder apps labelled "soon", truncated labels, inconsistent icons, and weak layout.
- Terminal UI has inconsistent shell chrome and large dead space; terminal input/scroll/copy/paste and touch behavior require device-level validation.
- Wallpaper and icon systems lack a coherent curated design language.
- Overall shell has no unified visual system.

## Non-negotiable architecture rules

1. Inspect the existing Flutter app structure and runtime before editing. Identify the current desktop root, window manager, app registry, menu bar, Dock, overlays, Finder, Settings, terminal, browser, wallpaper assets, theme tokens, and Android input bridges.
2. Keep the real Linux runtime, filesystem mounts, PTY, browser engine, authentication, downloads, and installed applications working. UI redesign must not regress them.
3. Build a Flutter-native design system: semantic color/material tokens, typography scale, spacing, radii, elevation, icon sizing, animation curves/durations, and responsive breakpoints. No scattered one-off styling.
4. Refactor shared shell components once and reuse them. Avoid separate incompatible implementations of the same menu, window header, sidebar, toolbar, icon tile, or popover.
5. Treat portrait Android as a first-class layout, not a squeezed desktop screenshot. Provide adaptive density and compact Dock behavior without sacrificing desktop/tablet layouts.
6. Preserve accessibility, text scaling, keyboard navigation, screen-reader labels, and reduced-motion settings.
7. Do not mark placeholder apps as working. Either implement a functional surface or clearly label it as unavailable and hide it from the primary app grid by default.

## Visual target / implementation scope

### A. Global desktop shell
- Rebuild the menu bar with accurate height, translucent material, subtle separator/shadow, left-side app/menu affordances, right-side system status controls, and readable clock.
- Use a consistent SF-like system typography fallback stack available under redistribution-compatible fonts (e.g. system sans + bundled licensed font); tune weights and letter spacing.
- Add coherent blur/material layering with graceful fallback on Android devices where backdrop blur is expensive.
- Implement proper desktop wallpaper crop/position and dark/light readability overlays.
- Use consistent macOS-like traffic-light window controls, title-bar metrics, window shadows, rounded corners, focus states, and resize affordances.

### B. Dock
- Rebuild the Dock as a compact floating translucent shelf with correct icon scale, padding, separators, running indicators, launch/minimize animations, and optional magnification on pointer devices.
- On phones, use a compact bottom Dock with adaptive icon sizes and safe-area handling; never consume a huge fraction of vertical screen space.
- Support pinning/reordering only if persistence and app registry behavior are correct.
- Respect Android gesture/navigation insets and keyboard visibility.

### C. Control Center and menu popovers
- Replace the generic card grid with a compact, layered popover, consistent typography, iconography, grouping, separators, and clear active/disabled states.
- Controls must connect to real device/runtime APIs where available. Never show fake Wi-Fi/VPN/Bluetooth status as if it were real.
- Use adaptive panel width and scroll on portrait devices.

### D. Finder
- Rebuild Finder with a proper sidebar, toolbar, path/location controls, icon/list/column views where supported, selection, multi-selection, context menus, sorting, search, file operations, drag/drop, and preview.
- All operations must act on the real MicroOS filesystem and respect Android storage permissions. No fake sample-only filesystem.
- Keep file operations testable and report errors to the user.

### E. Launchpad and Spotlight
- Launchpad: polished full-screen app grid, consistent app icon sizes, search, pagination/scrolling, opening/closing transitions, and no misleading "soon" icons in the default view.
- Spotlight: keyboard shortcut and touch-accessible search across installed apps and available files/settings, with useful results and focus handling.

### F. System Settings
- Rebuild as a coherent settings window with searchable sidebar categories, selected-row treatment, section headers, descriptions, controls, separators, and consistent content widths.
- Every exposed setting must persist and affect real behavior. Remove dead switches or mark unavailable.
- Desktop & Dock, Appearance, Wallpaper, Display, Keyboard, Trackpad/Pointer, Network/VPN, Browser, Storage, and About should be organized consistently.

### G. Icons, wallpapers, progress/loading states
- Create one icon catalog and one rendering component with consistent optical sizing and corner treatment. Avoid mixing emoji, generic Material icons, and unrelated icon packs.
- Curate an original/licensed wallpaper collection with correct high-resolution aspect/crop behavior; support user wallpaper selection.
- Standardize progress indicators, skeletons, empty states, error states, and notifications. No endless spinners without timeout/error handling.

### H. Pointer, touch, keyboard and terminal
- Add a visible pointer/cursor mode for touch users with trackpad overlay: move, primary click, secondary click, drag, scroll, and pointer capture. Support external mouse/trackpad too.
- Validate terminal selection, copy, paste, cursor visibility, slash and punctuation input, long output scrolling, alternate-screen scrolling, keyboard resize, and large paste behavior on a real Android device.
- Ensure OpenCode interactive TUI receives correct wheel, key, resize, and focus events. Never consume terminal gestures needed for selection or scrolling.

### I. Browser and app integration
- Keep a real Chromium/WebView/browser engine, not an iframe-based imitation. Verify GitHub OAuth, cookies, redirects, file upload/download, popups, external intents, and session persistence.
- Keep browser automation/headless tests available in CI where feasible.
- Do not regress qBittorrent, Blender provisioning, VPN/network runtime, OpenCode, or other installed Linux apps.

## Implementation sequence

1. **Audit and baseline:** map existing widgets/services, take screenshots at phone portrait, phone landscape, and tablet/desktop sizes; record current tests and runtime behavior.
2. **Design foundation:** implement shared tokens, materials, typography, icon catalog, window chrome, and responsive metrics.
3. **Shell:** redesign menu bar, Dock, desktop wallpaper, window manager surfaces, Control Center, Spotlight, Launchpad, notifications.
4. **Core apps:** Finder and System Settings; then Terminal chrome and browser integration.
5. **Device interactions:** pointer/trackpad, selection, clipboard, keyboard, scroll and safe areas.
6. **Regression and release:** run formatter, analyzer, unit/widget tests, Android release build, rootfs checks, and device smoke tests.

Do not attempt a giant one-commit rewrite. Deliver small reviewable commits and preserve a working build at each stage.

## Required acceptance criteria

- [ ] Main desktop screenshot is recognizably Sequoia-inspired, not a generic Linux panel with a Dock.
- [ ] Menu bar, Dock, Control Center, Launchpad, Finder, Settings, windows, icons, and wallpaper use one consistent design system.
- [ ] Portrait Dock is compact and does not waste vertical space.
- [ ] No "soon" placeholder icons appear in the primary Launchpad by default.
- [ ] Finder reads and manipulates real files.
- [ ] Settings controls persist and affect actual settings.
- [ ] Touch pointer/trackpad supports move, click, right-click, drag, and scroll.
- [ ] Terminal copy/paste/selection/scroll/cursor/slash input pass manual Android device tests.
- [ ] OpenCode TUI remains usable through keyboard, scroll, resize, and clipboard workflows.
- [ ] Browser can sign into GitHub using the supported OAuth flow and retain a session.
- [ ] Linux runtime, Chromium, OpenCode, VPN, torrent client and Blender workflows are not regressed.
- [ ] Flutter analyze, unit/widget tests, Android release build, and rootfs validation pass.
- [ ] Attach before/after screenshots and test logs to the PR. Do not claim device-level tests passed unless actually run on a device.

## OpenCode instructions

Work directly on branch `redesign/macos-sequoia-shell`. Start by reading this brief and auditing the current code. Then implement the redesign in phases, commit each coherent phase, run the relevant tests, fix failures, and open a PR against `main`. Do not stop after writing a plan or producing mockups. Do not merge to main until CI passes and the user can review screenshots and a test report.
