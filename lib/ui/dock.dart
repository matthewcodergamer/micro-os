import 'dart:ui';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../core/theme.dart';
import '../models/window_state.dart';
import '../state/desktop_state.dart';
import 'mac_icons.dart';

/// Glass dock with squircle icons, running indicators, Launchpad and Trash.
class Dock extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final desktop = scope.desktop;

    return AnimatedSlide(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      offset: visible ? Offset.zero : const Offset(0, 1.2),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: visible ? 1 : 0,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                    children: [
                      for (final app in _apps) ...[
                        _DockItem(
                          app: app,
                          running: desktop.isRunning(app),
                          onTap: () => onOpen(app),
                          onLongPress: desktop.isRunning(app)
                              ? () {
                                  for (final w in [...desktop.windows]) {
                                    if (w.app == app) desktop.close(w.id);
                                  }
                                }
                              : null,
                        ),
                        if (app != _apps.last) const SizedBox(width: 10),
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

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.app,
    required this.running,
    required this.onTap,
    this.onLongPress,
  });

  final AppId app;
  final bool running;
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
          MacAppIcon(app: app, size: 52),
          const SizedBox(height: 4),
          RunningDot(active: running),
        ],
      ),
    );
  }
}
