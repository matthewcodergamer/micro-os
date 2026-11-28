import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../core/desktop_input.dart';
import '../core/linux_apps.dart';
import '../core/shell_mode.dart';
import '../core/theme.dart';
import '../core/wallpapers.dart';
import '../models/window_state.dart';
import '../services/settings_store.dart';
import 'apps/ai_hub_app.dart';
import 'apps/desktop_session_app.dart';
import 'apps/files_app.dart';
import 'apps/settings_app.dart';
import 'apps/terminal_app.dart';
import 'control_center.dart';
import 'dock.dart';
import 'install_screen.dart';
import 'login_screen.dart';
import 'spotlight.dart';
import 'status_bar.dart';
import 'wallpaper.dart';
import 'window_frame.dart';
import 'mac_icons.dart';

/// The desktop: wallpaper, window layer, menu bar, Dock, Spotlight,
/// Control Center, Setup Assistant and the login window.
class DesktopScreen extends StatefulWidget {
  const DesktopScreen({super.key});

  @override
  State<DesktopScreen> createState() => _DesktopScreenState();
}

class _DesktopScreenState extends State<DesktopScreen>
    with WidgetsBindingObserver {
  Size _lastArea = Size.zero;
  double _lastTop = -1;
  double _lastBottom = -1;
  double _lastInset = -1;

  bool _spotlight = false;
  bool _launchpad = false;
  bool _control = false;

  // Dock auto-hide
  bool _dockRevealed = false;
  Timer? _dockTimer;

  // The Android keyboard reports a new inset on every animation frame. Sync
  // the desktop once the keyboard has settled; resizing windows on every frame
  // makes the terminal reflow and repaint in a visible flicker loop.
  double _keyboardInset = 0;
  double _rawKeyboardInset = 0;
  Timer? _keyboardTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final view = View.maybeOf(context);
    if (view == null) return;
    final raw = view.viewInsets.bottom / view.devicePixelRatio;
    if ((raw - _rawKeyboardInset).abs() <= 0.5) return;
    _rawKeyboardInset = raw;
    _keyboardTimer?.cancel();
    _keyboardTimer = Timer(const Duration(milliseconds: 140), () {
      if (!mounted) return;
      if ((_rawKeyboardInset - _keyboardInset).abs() <= 0.5) return;
      setState(() => _keyboardInset = _rawKeyboardInset);
    });
  }

  void _revealDock() {
    _dockTimer?.cancel();
    if (!_dockRevealed) setState(() => _dockRevealed = true);
    // Keep the Dock up long enough to read it and pick an app. Interacting
    // with the Dock calls this again, so the timer restarts on every touch.
    _dockTimer = Timer(const Duration(seconds: 6), _hideDock);
  }

  void _hideDock() {
    _dockTimer?.cancel();
    if (mounted && _dockRevealed) setState(() => _dockRevealed = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dockTimer?.cancel();
    _keyboardTimer?.cancel();
    super.dispose();
  }

  EdgeInsets _insets(BuildContext context) {
    final vp = MediaQuery.viewPaddingOf(context);
    final p = MediaQuery.paddingOf(context);
    return EdgeInsets.fromLTRB(
      math.max(vp.left, p.left),
      math.max(vp.top, p.top),
      math.max(vp.right, p.right),
      math.max(vp.bottom, p.bottom),
    );
  }

  /// Opens the native X11 desktop and starts a real Linux program inside it.
  ///
  /// Launchpad shows the program's own artwork, so tapping Blender or Chrome
  /// must not fall back to a Flutter placeholder. The desktop window is brought
  /// up first; the process then maps its own X11 window on the shared display.
  void _launchLinux(LinuxApp app) {
    final scope = AppScope.of(context);
    final size = MediaQuery.sizeOf(context);
    _hideDock();
    scope.desktop.open(AppId.desktop, screen: size);
    unawaited(
      scope.runtime.launchLinuxApp(app).catchError((Object error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${app.title} could not start: $error')),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final desktop = scope.desktop;
    final runtime = scope.runtime;
    final settings = scope.settings;
    final stats = scope.stats;

    return ListenableBuilder(
      listenable: Listenable.merge([desktop, runtime, settings]),
      builder: (context, _) {
        final insets = _insets(context);
        final media = MediaQuery.of(context);
        final size = media.size;
        final keyboard = _keyboardInset;

        final top = insets.top + kMenuBarHeight;
        // Keep the Dock above Android's mandatory system-gesture strip. This
        // avoids placing interactive controls directly under Home/Back swipes.
        final gestureBottom = media.systemGestureInsets.bottom;
        final dockBottom = math.max(insets.bottom, gestureBottom);
        final mobile = resolveMobileShell(settings.shellMode, size);
        final desktopMode = settings.shellMode == ShellMode.desktop ||
            (settings.shellMode == ShellMode.automatic &&
                size.shortestSide >= 600);
        final dockAutoHides = settings.dockVisibilityMode.shouldAutoHide(
          desktopMode: desktopMode,
        );
        final fullScreenApp =
            desktop.focused?.maximized == true ||
            desktop.focused?.pinned == true;
        final alwaysVisibleDock =
            settings.dockVisibilityMode == DockVisibilityMode.alwaysVisible;
        // An auto-hidden Dock starts tucked away on phones, even before a
        // window opens, so the home screen stays calm and the wallpaper has
        // room to breathe. Swiping up reveals it. An always-visible Dock is
        // honoured even over a full-screen app, exactly as the setting says.
        final hideDock = !_dockRevealed &&
            (dockAutoHides || (fullScreenApp && !alwaysVisibleDock));
        // Auto-hidden Docks float over the workspace; a visible, centred Dock
        // reserves space so windows never sit underneath it. A full-screen app
        // owns the screen, so the Dock floats above it only when revealed.
        final reserveForDock = !fullScreenApp && !dockAutoHides;
        final bottomReserve = reserveForDock ? kDockReserved : 0.0;
        final bottom = math.max(0.0, dockBottom + bottomReserve);

        // Sync geometry
        final area = Size(size.width, size.height);
        if (area != _lastArea ||
            top != _lastTop ||
            bottom != _lastBottom ||
            keyboard != _lastInset ||
            settings.shellMode != desktop.shellMode) {
          _lastArea = area;
          _lastTop = top;
          _lastBottom = bottom;
          _lastInset = keyboard;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              desktop.syncToScreen(
                area,
                topReserve: top,
                bottomReserve: bottom,
                bottomInset: keyboard,
                shellMode: settings.shellMode,
              );
            }
          });
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            // Wallpaper always edge-to-edge
            RepaintBoundary(child: Wallpaper(asset: settings.wallpaperAsset)),

            // Long-press anywhere on empty desktop to change the wallpaper.
            if (!desktop.locked)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPress: () => _pickWallpaper(context, settings),
                ),
              ),

            // Windows stay mounted while the screen is locked so terminal and
            // Linux sessions survive locking/unlocking, exactly like macOS.
            // WindowFrame returns an AnimatedPositioned, which must stay a
            // direct child of this Stack: wrapping it in any other widget
            // (e.g. RepaintBoundary) breaks StackParentData and makes windows
            // full-bleed, mis-stacked or invisible.
            if (runtime.isReady)
              for (final window in desktop.ordered)
                if (!window.minimized)
                  WindowFrame(
                    window: window,
                    desktop: desktop,
                    screen: size,
                    mobile: mobile,
                    child: _contentFor(window, scope),
                  ),

            if (runtime.isReady && !desktop.locked) ...[
              // Menu bar
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: StatusBar(
                  height: top,
                  onSpotlight: () => setState(() {
                    _spotlight = true;
                    _launchpad = false;
                    _control = false;
                  }),
                  onLaunchpad: () => setState(() {
                    _launchpad = true;
                    _spotlight = false;
                    _control = false;
                  }),
                  onControlCenter: () => setState(() {
                    _control = true;
                    _spotlight = false;
                    _launchpad = false;
                  }),
                  onLock: desktop.lock,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: dockBottom,
                child: Dock(
                  visible: !hideDock,
                  onInteraction: _revealDock,
                  onOpen: (app) {
                    // A picked app owns the screen; collapse the Dock at once
                    // instead of leaving it floating over the new window.
                    _hideDock();
                    desktop.open(app, screen: size);
                  },
                ),
              ),
              if (hideDock)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: dockBottom,
                  height: 40,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _revealDock,
                    onVerticalDragStart: (_) => _revealDock(),
                    onVerticalDragUpdate: (d) {
                      if (d.delta.dy < -2) _revealDock();
                    },
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
                        builder: (context, t, child) {
                          return Opacity(
                            opacity: t,
                            child: Transform.translate(
                              offset: Offset(0, (1 - t) * 8),
                              child: child,
                            ),
                          );
                        },
                        child: Container(
                          width: 58,
                          height: 4.5,
                          margin: const EdgeInsets.only(bottom: 9),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.58),
                            borderRadius: BorderRadius.circular(3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.32),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_spotlight)
                _animateOverlay(
                  SpotlightOverlay(
                    topPadding: top,
                    onClose: () => setState(() => _spotlight = false),
                    onOpen: (app) {
                      setState(() => _spotlight = false);
                      desktop.open(app, screen: size);
                    },
                    onOpenLinux: (app) {
                      setState(() => _spotlight = false);
                      _launchLinux(app);
                    },
                  ),
                ),
              if (_launchpad)
                _animateOverlay(
                  LaunchpadOverlay(
                    topPadding: top,
                    onClose: () => setState(() => _launchpad = false),
                    onOpen: (app) {
                      setState(() => _launchpad = false);
                      desktop.open(app, screen: size);
                    },
                    onOpenLinux: (app) {
                      setState(() => _launchpad = false);
                      _launchLinux(app);
                    },
                  ),
                ),
              if (_control)
                _animateOverlay(
                  ControlCenterOverlay(
                    topPadding: top,
                    onClose: () => setState(() => _control = false),
                    runtime: runtime,
                    stats: stats,
                    onOpenDesktop: () {
                      setState(() => _control = false);
                      desktop.open(AppId.desktop, screen: size);
                    },
                    onLock: () {
                      setState(() => _control = false);
                      desktop.lock();
                    },
                  ),
                ),
            ],
            // The installer fades away as soon as the rootfs is ready. The
            // login screen or desktop is already mounted underneath it.
            Positioned.fill(
              child: IgnorePointer(
                ignoring: runtime.isReady && !desktop.locked,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 650),
                  reverseDuration: const Duration(milliseconds: 420),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: !runtime.isReady
                      ? const InstallScreen(key: ValueKey('installer'))
                      : desktop.locked
                          ? LoginScreen(
                              key: const ValueKey('login'),
                              settings: settings,
                              onUnlock: desktop.unlock,
                            )
                          : const SizedBox.expand(key: ValueKey('desktop-ready')),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Desktop long-press → wallpaper picker. The choice is persisted by
  /// [SettingsStore] and re-applied on next launch.
  Future<void> _pickWallpaper(
    BuildContext context,
    SettingsStore settings,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xF21C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Wallpaper',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Tap a wallpaper to apply it to the desktop.',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 190,
                child: Row(
                  children: [
                    for (var i = 0; i < kWallpapers.length; i++) ...[
                      Expanded(
                        child: WallpaperThumbnail(
                          wallpaper: kWallpapers[i],
                          selected: settings.wallpaper == kWallpapers[i].id,
                          onTap: () {
                            settings.setWallpaper(kWallpapers[i].id);
                            Navigator.of(sheetContext).pop();
                          },
                        ),
                      ),
                      if (i != kWallpapers.length - 1)
                        const SizedBox(width: 12),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _animateOverlay(Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, -10 * (1 - value)),
          child: child,
        ),
      ),
      child: child,
    );
  }

  Widget _contentFor(ManagedWindow window, AppScope scope) {
    switch (window.app) {
      case AppId.terminal:
        return TerminalTabsApp(
          runtime: scope.runtime,
          argv: window.args,
          settings: scope.settings,
          onTitle: (t) => scope.desktop.setTitle(window.id, t),
        );
      case AppId.desktop:
        return DesktopSessionApp(runtime: scope.runtime);
      case AppId.browser:
        return DesktopSessionApp(
          runtime: scope.runtime,
          launchBrowser: true,
          singleProcess: scope.settings.singleProcessBrowser,
        );
      case AppId.files:
        return FilesApp(
          runtime: scope.runtime,
          onOpenTerminal: (args) => scope.desktop.open(
            AppId.terminal,
            screen: MediaQuery.sizeOf(context),
            args: args,
            newWindow: true,
          ),
        );
      case AppId.aiHub:
        return AiHubApp(runtime: scope.runtime, settings: scope.settings);
      case AppId.settings:
        return SettingsApp(runtime: scope.runtime);
      case AppId.maps:
      case AppId.mail:
      case AppId.notes:
      case AppId.photos:
      case AppId.music:
      case AppId.appStore:
      case AppId.calculator:
        return _placeholderApp(window.app);
    }
  }

  Widget _placeholderApp(AppId app) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        final iconSize = compact ? 68.0 : 88.0;
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MacAppIcon(app: app, size: iconSize),
                  const SizedBox(height: 22),
                  Text(
                    app.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: MicroColors.text,
                      fontSize: compact ? 23 : 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    app.subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: MicroColors.subtle, fontSize: 14),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                    decoration: BoxDecoration(
                      color: MicroColors.sidebar,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.hourglass_top_rounded, size: 17, color: MicroColors.accent),
                        SizedBox(width: 9),
                        Flexible(
                          child: Text(
                            'This app is registered. Its full native integration is coming next.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: MicroColors.text, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
