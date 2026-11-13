import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../core/theme.dart';
import '../models/window_state.dart';
import 'mac_icons.dart';

/// Glass dock with the responsive cosine magnification used by ThanasOS.
class Dock extends StatefulWidget {
  const Dock({
    super.key,
    required this.onOpen,
    required this.visible,
  });

  final ValueChanged<AppId> onOpen;
  final bool visible;

  static const _apps = [
    AppId.files,
    AppId.terminal,
    AppId.browser,
    AppId.desktop,
    AppId.aiHub,
    AppId.settings,
  ];

  @override
  State<Dock> createState() => _DockState();
}

class _DockState extends State<Dock> {
  double? _pointerX;

  void _trackPointer(double x) {
    if (_pointerX == x) return;
    setState(() => _pointerX = x);
  }

  void _clearPointer() {
    if (_pointerX == null) return;
    setState(() => _pointerX = null);
  }

  @override
  Widget build(BuildContext context) {
    final desktop = AppScope.of(context).desktop;
    final screen = MediaQuery.sizeOf(context);
    final compact = screen.width < kCompactBreakpoint;
    final smallerDimension = math.min(screen.width, screen.height);
    final iconSize = compact ? 38.0 : 52.0;
    final maxScale = smallerDimension < 480 ? 1.4 : 1.6;
    final effectWidth = smallerDimension < 480
        ? smallerDimension * 0.4
        : smallerDimension < 768
            ? smallerDimension * 0.35
            : smallerDimension < 1024
                ? smallerDimension * 0.3
                : 300.0;
    final horizontalPadding = compact ? 8.0 : 14.0;
    final spacing = compact ? 5.0 : 10.0;

    final scales = List<double>.generate(Dock._apps.length, (index) {
      final pointer = _pointerX;
      if (pointer == null || effectWidth <= 0) return 1;
      final iconCenter = index * (iconSize + spacing) + iconSize / 2;
      final minX = pointer - effectWidth / 2;
      final maxX = pointer + effectWidth / 2;
      if (iconCenter < minX || iconCenter > maxX) return 1;
      final theta = ((iconCenter - minX) / effectWidth) * 2 * math.pi;
      final scaleFactor = (1 - math.cos(theta.clamp(0, 2 * math.pi))) / 2;
      return 1 + scaleFactor * (maxScale - 1);
    });

    return AnimatedSlide(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      offset: widget.visible ? Offset.zero : const Offset(0, 1.2),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: widget.visible ? 1 : 0,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: MouseRegion(
              onHover: (event) => _trackPointer(
                event.localPosition.dx - horizontalPadding,
              ),
              onExit: (_) => _clearPointer(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (details) => _trackPointer(
                  details.localPosition.dx - horizontalPadding,
                ),
                onPanUpdate: (details) => _trackPointer(
                  details.localPosition.dx - horizontalPadding,
                ),
                onPanEnd: (_) => _clearPointer(),
                onPanCancel: _clearPointer,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    // A smaller blur keeps the translucent glass while reducing
                    // the cost of a full-screen backdrop filter on mobile GPUs.
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                        vertical: compact ? 7 : 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x991C1C1E),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.22),
                          width: 0.8,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x66000000),
                            blurRadius: 30,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var index = 0; index < Dock._apps.length; index++) ...[
                            Builder(builder: (context) {
                              final app = Dock._apps[index];
                              final scale = scales[index];
                              return SizedBox(
                                width: iconSize * scale,
                                height: iconSize * 1.42,
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Transform.scale(
                                    scale: scale,
                                    alignment: Alignment.bottomCenter,
                                    child: _DockItem(
                                      app: app,
                                      running: desktop.isRunning(app),
                                      size: iconSize,
                                      onTap: () => widget.onOpen(app),
                                      onLongPress: desktop.isRunning(app)
                                          ? () {
                                              for (final window in [...desktop.windows]) {
                                                if (window.app == app) {
                                                  desktop.close(window.id);
                                                }
                                              }
                                            }
                                          : null,
                                    ),
                                  ),
                                ),
                              );
                            }),
                            if (index != Dock._apps.length - 1)
                              SizedBox(width: spacing),
                          ],
                        ],
                      ),
                    ),
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

Widget _dockAssetIcon(AppId app, double size) {
  final asset = switch (app) {
    AppId.files => 'assets/icons/dock/finder-icon.png',
    AppId.terminal => 'assets/icons/dock/terminal-icon.png',
    AppId.browser => 'assets/icons/dock/safari-icon.png',
    AppId.settings => 'assets/icons/dock/settings-icon.png',
    AppId.desktop || AppId.aiHub => null,
  };
  if (asset == null) return MacAppIcon(app: app, size: size);
  return ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.22),
    child: Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      cacheWidth: (size * 2).round(),
      cacheHeight: (size * 2).round(),
    ),
  );
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.app,
    required this.running,
    required this.size,
    required this.onTap,
    this.onLongPress,
  });

  final AppId app;
  final bool running;
  final double size;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _dockAssetIcon(app, size),
          const SizedBox(height: 4),
          RunningDot(active: running),
        ],
      ),
    );
  }
}
