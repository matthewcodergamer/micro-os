import 'package:flutter/material.dart';

import '../core/macos_design.dart';
import '../core/theme.dart';
import '../models/window_state.dart';
import '../state/desktop_state.dart';
import 'mac_icons.dart';

/// Window chrome: unified title bar with traffic lights, rounded corners,
/// soft shadow and edge/corner resize handles (hidden when maximized).
class WindowFrame extends StatelessWidget {
  const WindowFrame({
    super.key,
    required this.window,
    required this.desktop,
    required this.screen,
    required this.child,
  });

  final ManagedWindow window;
  final DesktopState desktop;
  final Size screen;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final focused = desktop.focused?.id == window.id;
    final maxed = window.maximized;
    final radius = maxed
        ? BorderRadius.zero
        : BorderRadius.circular(Sequoia.windowRadius);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 230),
      curve: Curves.easeOutCubic,
      left: window.rect.left,
      top: window.rect.top,
      width: window.rect.width,
      height: window.rect.height,
      child: IgnorePointer(
        ignoring: window.minimized,
        // No Opacity/Transform animation here: both break Android platform
        // views (the noVNC WebView) and turn the window into a blank surface.
        // Entry motion is handled by AnimatedPositioned and the shadow.
        child: Listener(
          onPointerDown: (_) => desktop.focus(window.id),
          child: RepaintBoundary(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                // Sequoia casts one wide, soft shadow per window and lifts the
                // focused window instead of recolouring its chrome.
                boxShadow: maxed
                    ? null
                    : Sequoia.panelShadow(opacity: focused ? 0.5 : 0.3),
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: Material(
                  color: MicroColors.windowBody,
                  child: Column(
                    children: [
                      _TitleBar(
                        window: window,
                        desktop: desktop,
                        screen: screen,
                        focused: focused,
                      ),
                      Expanded(child: child),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({
    required this.window,
    required this.desktop,
    required this.screen,
    required this.focused,
  });

  final ManagedWindow window;
  final DesktopState desktop;
  final Size screen;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: () => desktop.toggleMaximize(window.id, screen),
      onPanUpdate: window.maximized
          ? null
          : (d) => desktop.move(window.id, d.delta, screen),
      child: Container(
        height: Sequoia.titleBarHeight,
        decoration: BoxDecoration(
          color: focused
              ? MicroColors.windowHeader
              : Sequoia.toolbarTint.withValues(alpha: 0.92),
          border: Border(
            bottom: BorderSide(
              color: Colors.white.withValues(alpha: focused ? 0.05 : 0.03),
              width: 0.8,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            _TrafficLights(
              focused: focused,
              onClose: () => desktop.close(window.id),
              onMinimize: () => desktop.minimize(window.id),
              onZoom: () => desktop.toggleMaximize(window.id, screen),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                window.title,
                style: TextStyle(
                  color: focused ? MicroColors.text : MicroColors.subtle,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            MacAppIcon(app: window.app, size: 18),
          ],
        ),
      ),
    );
  }
}

class _TrafficLights extends StatelessWidget {
  const _TrafficLights({
    required this.focused,
    required this.onClose,
    required this.onMinimize,
    required this.onZoom,
  });

  final bool focused;
  final VoidCallback onClose;
  final VoidCallback onMinimize;
  final VoidCallback onZoom;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Light(
          color: focused ? Sequoia.closeLight : MicroColors.inactiveLight,
          onTap: onClose,
        ),
        const SizedBox(width: Sequoia.trafficLightGap),
        _Light(
          color: focused ? Sequoia.miniLight : MicroColors.inactiveLight,
          onTap: onMinimize,
        ),
        const SizedBox(width: Sequoia.trafficLightGap),
        _Light(
          color: focused ? Sequoia.zoomLight : MicroColors.inactiveLight,
          onTap: onZoom,
        ),
      ],
    );
  }
}

class _Light extends StatelessWidget {
  const _Light({required this.color, required this.onTap});

  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: Sequoia.trafficLightSize,
        height: Sequoia.trafficLightSize,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.15),
            width: 0.5,
          ),
        ),
      ),
    );
  }
}
