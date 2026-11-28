import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/macos_design.dart';
import '../core/theme.dart';
import '../models/window_state.dart';
import '../state/desktop_state.dart';
import 'mac_icons.dart';

/// Window chrome: unified title bar with traffic lights, rounded corners,
/// soft shadow and edge/corner resize handles (hidden when maximized).
///
/// In the mobile presentation the window is edge-to-edge and the traffic
/// lights become a thumb-sized mobile header, keeping the macOS palette while
/// giving the content the rest of the screen.
class WindowFrame extends StatelessWidget {
  const WindowFrame({
    super.key,
    required this.window,
    required this.desktop,
    required this.screen,
    required this.child,
    this.mobile = false,
  });

  final ManagedWindow window;
  final DesktopState desktop;
  final Size screen;
  final Widget child;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final focused = desktop.focused?.id == window.id;
    final maxed = window.maximized || mobile;
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
        // views (the native X11 TextureView) and turn the window into a blank surface.
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
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Column(
                        children: [
                          if (mobile)
                            _MobileTitleBar(
                              window: window,
                              desktop: desktop,
                              focused: focused,
                            )
                          else
                            _TitleBar(
                              window: window,
                              desktop: desktop,
                              screen: screen,
                              focused: focused,
                            ),
                          Expanded(child: child),
                        ],
                      ),
                      // Classic windows can be resized from the bottom corners.
                      // Full-screen windows and maximized windows have nothing
                      // to resize, so the grips disappear with the chrome.
                      if (!maxed) ...[
                        Positioned(
                          left: 0,
                          bottom: 0,
                          child: _ResizeGrip(
                            cursor: SystemMouseCursors.resizeDownLeft,
                            flip: true,
                            onDelta: (delta) => desktop.resizeEdges(
                              window.id,
                              screen,
                              left: window.rect.left + delta.dx,
                              bottom: window.rect.bottom + delta.dy,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: _ResizeGrip(
                            cursor: SystemMouseCursors.resizeDownRight,
                            onDelta: (delta) => desktop.resizeEdges(
                              window.id,
                              screen,
                              right: window.rect.right + delta.dx,
                              bottom: window.rect.bottom + delta.dy,
                            ),
                          ),
                        ),
                      ],
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

/// Touch-first header for the full-screen presentation.
///
/// It keeps the Terminal-style graphite chrome and the app's artwork, but uses
/// 44 px targets instead of 12 px traffic lights. Swiping down anywhere on the
/// header minimizes the app, matching the gesture people already use on their
/// phones.
class _MobileTitleBar extends StatelessWidget {
  const _MobileTitleBar({
    required this.window,
    required this.desktop,
    required this.focused,
  });

  final ManagedWindow window;
  final DesktopState desktop;
  final bool focused;

  void _close() {
    HapticFeedback.lightImpact();
    desktop.close(window.id);
  }

  void _minimize() {
    HapticFeedback.lightImpact();
    desktop.minimize(window.id);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 280) _minimize();
      },
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: focused
                ? const [Color(0xFF333338), Color(0xFF26262A)]
                : const [Color(0xFF2C2C31), Color(0xFF222226)],
          ),
          border: Border(
            bottom: BorderSide(
              color: Colors.white.withValues(alpha: 0.08),
              width: 0.7,
            ),
          ),
        ),
        child: Row(
          children: [
            _MobileAction(
              icon: Icons.close_rounded,
              color: Sequoia.closeLight,
              tooltip: 'Close',
              onTap: _close,
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  MacAppIcon(app: window.app, size: 16),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      window.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: focused ? MicroColors.text : MicroColors.subtle,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _MobileAction(
              icon: Icons.keyboard_arrow_down_rounded,
              color: Colors.white70,
              tooltip: 'Minimize',
              onTap: _minimize,
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileAction extends StatelessWidget {
  const _MobileAction({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        radius: 21,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 20, color: color),
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
    return MouseRegion(
      cursor: window.maximized
          ? SystemMouseCursors.basic
          : SystemMouseCursors.move,
      child: GestureDetector(
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
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
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

/// A small, discoverable corner grip. The 24 px target is comfortable on a
/// phone in Desktop mode and gives a physical-mouse user the familiar resize
/// cursor on a tablet.
class _ResizeGrip extends StatelessWidget {
  const _ResizeGrip({
    required this.cursor,
    required this.onDelta,
    this.flip = false,
  });

  final MouseCursor cursor;
  final ValueChanged<Offset> onDelta;
  final bool flip;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => onDelta(details.delta),
        child: SizedBox(
          width: 24,
          height: 24,
          child: Transform.flip(
            flipX: flip,
            child: CustomPaint(painter: const _ResizeGripPainter()),
          ),
        ),
      ),
    );
  }
}

class _ResizeGripPainter extends CustomPainter {
  const _ResizeGripPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.30)
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(size.width - 13, size.height - 3)
      ..lineTo(size.width - 3, size.height - 13)
      ..moveTo(size.width - 8, size.height - 3)
      ..lineTo(size.width - 3, size.height - 8);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
