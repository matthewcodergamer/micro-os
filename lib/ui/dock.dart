import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/window_state.dart';
import '../state/desktop_state.dart';

/// The Dock. Icons are intentionally large (touch targets >= 48 dp) because
/// this is the primary navigation surface on a phone.
class Dock extends StatelessWidget {
  const Dock({
    super.key,
    required this.desktop,
    required this.compact,
    required this.onOpen,
  });

  final DesktopState desktop;
  final bool compact;
  final ValueChanged<AppId> onOpen;

  @override
  Widget build(BuildContext context) {
    final items = <_DockItem>[
      _DockItem(AppId.terminal, Icons.terminal, const Color(0xFF2B2F3A)),
      _DockItem(AppId.desktop, Icons.desktop_windows, const Color(0xFF1F6FEB)),
      _DockItem(AppId.browser, Icons.travel_explore, const Color(0xFF7C4DFF)),
      _DockItem(AppId.files, Icons.folder_rounded, const Color(0xFFF0A32B)),
      _DockItem(AppId.aiHub, Icons.auto_awesome, const Color(0xFF00A67E)),
      _DockItem(AppId.settings, Icons.settings, const Color(0xFF5A6472)),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 14,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: const Color(0xB3141720),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: MicroColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in items)
                _DockButton(
                  item: item,
                  compact: compact,
                  running: desktop.isRunning(item.app),
                  onTap: () => onOpen(item.app),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockItem {
  const _DockItem(this.app, this.icon, this.color);

  final AppId app;
  final IconData icon;
  final Color color;
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.item,
    required this.compact,
    required this.running,
    required this.onTap,
  });

  final _DockItem item;
  final bool compact;
  final bool running;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 44.0 : 52.0;

    return Semantics(
      button: true,
      label: item.app.title,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 3 : 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(item.color, Colors.white, 0.18)!,
                      item.color,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0x22FFFFFF)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x44000000),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(item.icon, color: Colors.white, size: size * 0.5),
              ),
              const SizedBox(height: 3),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: running ? MicroColors.accent : Colors.transparent,
                  shape: BoxShape.circle,
                ),
              ),
              if (!compact)
                Text(
                  item.app.title,
                  style: const TextStyle(
                    color: MicroColors.subtle,
                    fontSize: 9,
                    height: 1.1,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
