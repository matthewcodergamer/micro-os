import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/window_state.dart';
import '../state/desktop_state.dart';

/// A draggable, resizable macOS-style window. On phone-sized screens the
/// window is pinned by [DesktopState] and the chrome stays out of the way.
class WindowFrame extends StatelessWidget {
  const WindowFrame({
    super.key,
    required this.window,
    required this.screen,
    required this.desktop,
    required this.child,
  });

  final ManagedWindow window;
  final Size screen;
  final DesktopState desktop;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final focused = desktop.focused?.id == window.id;
    final compact = window.pinned;

    return GestureDetector(
      onTap: () => desktop.focus(window.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: MicroColors.windowBody,
          borderRadius: BorderRadius.circular(compact ? 0 : 12),
          border: Border.all(
            color: focused ? const Color(0x44FFFFFF) : const Color(0x22FFFFFF),
          ),
          boxShadow: focused
              ? const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 32,
                    offset: Offset(0, 16),
                  ),
                ]
              : const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(compact ? 0 : 12),
          child: Column(
            children: [
              _TitleBar(
                window: window,
                focused: focused,
                compact: compact,
                onDrag: (delta) => desktop.move(window.id, delta, screen),
                onClose: () => desktop.close(window.id),
                onMinimize: () => desktop.minimize(window.id),
                onMaximize: () => desktop.toggleMaximize(window.id, screen),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: child),
                    if (!compact)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: ResizeHandle(
                          onDrag: (delta) =>
                              desktop.resize(window.id, delta, screen),
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
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({
    required this.window,
    required this.focused,
    required this.compact,
    required this.onDrag,
    required this.onClose,
    required this.onMinimize,
    required this.onMaximize,
  });

  final ManagedWindow window;
  final bool focused;
  final bool compact;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onClose;
  final VoidCallback onMinimize;
  final VoidCallback onMaximize;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: compact ? SystemMouseCursors.basic : SystemMouseCursors.move,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: compact ? null : (details) => onDrag(details.delta),
        onDoubleTap: compact ? null : onMaximize,
        child: Container(
          height: compact ? 34 : 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: const BoxDecoration(
            color: MicroColors.windowHeader,
            border: Border(bottom: BorderSide(color: Color(0x1AFFFFFF))),
          ),
          child: Row(
            children: [
              _TrafficLight(color: MicroColors.red, onTap: onClose, icon: Icons.close),
              const SizedBox(width: 8),
              _TrafficLight(
                color: MicroColors.amber,
                onTap: onMinimize,
                icon: Icons.remove,
              ),
              const SizedBox(width: 8),
              _TrafficLight(
                color: MicroColors.green,
                onTap: onMaximize,
                icon: Icons.fullscreen,
              ),
              Expanded(
                child: Text(
                  window.title,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: focused ? MicroColors.text : MicroColors.subtle,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(width: 68),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrafficLight extends StatelessWidget {
  const _TrafficLight({
    required this.color,
    required this.onTap,
    required this.icon,
  });

  final Color color;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 13,
        height: 13,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, size: 9, color: const Color(0x66000000)),
      ),
    );
  }
}

/// Bottom-right resize grip.
class ResizeHandle extends StatelessWidget {
  const ResizeHandle({super.key, required this.onDrag});

  final ValueChanged<Offset> onDrag;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeDownRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => onDrag(details.delta),
        child: const SizedBox(
          width: 22,
          height: 22,
          child: CustomPaint(painter: _GripPainter()),
        ),
      ),
    );
  }
}

class _GripPainter extends CustomPainter {
  const _GripPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x55FFFFFF)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 3; i++) {
      final offset = 5.0 + i * 5;
      canvas.drawLine(
        Offset(size.width - offset, size.height - 4),
        Offset(size.width - 4, size.height - offset),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
