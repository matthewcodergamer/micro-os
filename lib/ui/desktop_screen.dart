import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../core/theme.dart';
import '../models/window_state.dart';
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

class _DesktopScreenState extends State<DesktopScreen> {
  Size _lastArea = Size.zero;
  double _lastTop = -1;
  double _lastBottom = -1;
  double _lastInset = -1;

  bool _spotlight = false;
  bool _control = false;

  // Dock auto-hide
  bool _dockRevealed = false;
  Timer? _dockTimer;

  void _revealDock() {
    _dockTimer?.cancel();
    if (!_dockRevealed) setState(() => _dockRevealed = true);
    _dockTimer = Timer(const Duration(milliseconds: 3800), _hideDock);
  }

  void _hideDock() {
    _dockTimer?.cancel();
    if (mounted && _dockRevealed) setState(() => _dockRevealed = false);
  }

  @override
  void dispose() {
    _dockTimer?.cancel();
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
        final keyboard = media.viewInsets.bottom;

        final top = insets.top + kMenuBarHeight;
        final bottomReserve = settings.dockAutoHide && desktop.focused != null
            ? 0.0
            : kDockReserved;
        final bottom = math.max(0.0, insets.bottom + bottomReserve);

        // Sync geometry
        final area = Size(size.width, size.height);
        if (area != _lastArea ||
            top != _lastTop ||
            bottom != _lastBottom ||
            keyboard != _lastInset) {
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
              );
            }
          });
        }

        final hideDock = settings.dockAutoHide &&
            desktop.focused != null &&
            !_dockRevealed;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Wallpaper always edge-to-edge
            const Wallpaper(),

            // Install overlay when runtime not ready
            if (!runtime.isReady)
              const InstallScreen()
            else if (desktop.locked)
              LoginScreen(
                settings: settings,
                onUnlock: desktop.unlock,
              )
            else ...[
              // Windows
              for (final window in desktop.ordered)
                if (!window.minimized)
                  WindowFrame(
                    window: window,
                    desktop: desktop,
                    screen: size,
                    child: _contentFor(window, scope),
                  ),

              // Menu bar
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: StatusBar(
                  height: top,
                  onSpotlight: () => setState(() {
                    _spotlight = true;
                    _control = false;
                  }),
                  onControlCenter: () => setState(() {
                    _control = true;
                    _spotlight = false;
                  }),
                  onLock: desktop.lock,
                ),
              ),

              // Dock
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Dock(
                  visible: !hideDock,
                  onOpen: (app) => desktop.open(app, screen: size),
                ),
              ),

              // Swipe-up to reveal dock when auto-hidden
              if (hideDock)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 28,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onVerticalDragUpdate: (d) {
                      if (d.delta.dy < -4) _revealDock();
                    },
                  ),
                ),

              // Spotlight
              if (_spotlight)
                _animateOverlay(
                  SpotlightOverlay(
                    topPadding: top,
                    onClose: () => setState(() => _spotlight = false),
                    onOpen: (app) {
                      setState(() => _spotlight = false);
                      desktop.open(app, screen: size);
                    },
                  ),
                ),

              // Control Center
              if (_control)
                _animateOverlay(
                  ControlCenterOverlay(
                    topPadding: top,
                    onClose: () => setState(() => _control = false),
                    runtime: runtime,
                    stats: stats,
                  ),
                ),
            ],
          ],
        );
      },
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
