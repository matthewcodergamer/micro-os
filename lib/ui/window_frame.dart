import 'package:flutter/material.dart';

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

    return Positioned(
      left: window.rect.left,
      top: window.rect.top,
      width: window.rect.width,
      height: window.rect.height,
      child: IgnorePointer(
        ignoring: window.minimized,
        child: Opacity(
          opacity: window.minimized ? 0 : 1,
          child: Listener(
            onPointerDown: (_) => desktop.focus(window.id),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(maxed ? 0 : 12),
                boxShadow: maxed
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: focused ? 0.45 : 0.28),
                          blurRadius: focused ? 28 : 18,
                          offset: const Offset(0, 10),
                        ),
                      ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(maxed ? 0 : 12),
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
        height: 38,
        color: MicroColors.windowHeader,
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
        _Light(color: focused ? MicroColors.red : MicroColors.inactiveLight, onTap: onClose),
        const SizedBox(width: 8),
        _Light(color: focused ? MicroColors.amber : MicroColors.inactiveLight, onTap: onMinimize),
        const SizedBox(width: 8),
        _Light(color: focused ? MicroColors.green : MicroColors.inactiveLight, onTap: onZoom),
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
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black.withValues(alpha: 0.15), width: 0.5),
        ),
      ),
    );
  }
}
