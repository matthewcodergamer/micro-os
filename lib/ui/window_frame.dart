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
    this.touchOptimized = false,
    required this.child,
  });

  final ManagedWindow window;
  final DesktopState desktop;
  final Size screen;
  final bool touchOptimized;
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
        child: Listener(
          onPointerDown: (_) => desktop.focus(window.id),
          child: RepaintBoundary(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
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
                        touchOptimized: touchOptimized,
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
    required this.touchOptimized,
  });

  final ManagedWindow window;
  final DesktopState desktop;
  final Size screen;
  final bool focused;
  final bool touchOptimized;

  Future<void> _showWindowActions(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MicroColors.panelSolid,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.vertical_split_rounded),
              title: const Text('Tile Left'),
              onTap: () => Navigator.pop(context, 'left'),
            ),
            ListTile(
              leading: const Icon(Icons.vertical_split_rounded),
              title: const Text('Tile Right'),
              onTap: () => Navigator.pop(context, 'right'),
            ),
            ListTile(
              leading: const Icon(Icons.center_focus_strong_rounded),
              title: const Text('Center Window'),
              onTap: () => Navigator.pop(context, 'center'),
            ),
            ListTile(
              leading: const Icon(Icons.open_in_full_rounded),
              title: const Text('Zoom'),
              onTap: () => Navigator.pop(context, 'zoom'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'left':
        desktop.snapToHalf(window.id, screen, left: true);
        break;
      case 'right':
        desktop.snapToHalf(window.id, screen, left: false);
        break;
      case 'center':
        desktop.centerWindow(window.id, screen);
        break;
      case 'zoom':
        desktop.toggleMaximize(window.id, screen);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: () => desktop.toggleMaximize(window.id, screen),
      onLongPress: () => _showWindowActions(context),
      onPanUpdate: window.maximized
          ? null
          : (details) => desktop.move(window.id, details.delta, screen),
      child: Container(
        height: touchOptimized ? 52 : Sequoia.titleBarHeight,
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
              touchOptimized: touchOptimized,
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
    required this.touchOptimized,
    required this.onClose,
    required this.onMinimize,
    required this.onZoom,
  });

  final bool focused;
  final bool touchOptimized;
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
          touchOptimized: touchOptimized,
        ),
        const SizedBox(width: Sequoia.trafficLightGap),
        _Light(
          color: focused ? Sequoia.miniLight : MicroColors.inactiveLight,
          onTap: onMinimize,
          touchOptimized: touchOptimized,
        ),
        const SizedBox(width: Sequoia.trafficLightGap),
        _Light(
          color: focused ? Sequoia.zoomLight : MicroColors.inactiveLight,
          onTap: onZoom,
          touchOptimized: touchOptimized,
        ),
      ],
    );
  }
}

class _Light extends StatelessWidget {
  const _Light({
    required this.color,
    required this.onTap,
    this.touchOptimized = false,
  });

  final Color color;
  final VoidCallback onTap;
  final bool touchOptimized;

  @override
  Widget build(BuildContext context) {
    final targetSize = touchOptimized ? 40.0 : Sequoia.trafficLightSize;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: targetSize,
        height: targetSize,
        child: Center(
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
        ),
      ),
    );
  }
}
