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
                  onQuit: () {
                    final window = desktop.windowFor(item.app);
                    if (window != null) desktop.close(window.id);
                  },
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

class _DockButton extends StatefulWidget {
  const _DockButton({
    required this.item,
    required this.compact,
    required this.running,
    required this.onTap,
    required this.onQuit,
  });

  final _DockItem item;
  final bool compact;
  final bool running;
  final VoidCallback onTap;
  final VoidCallback onQuit;

  @override
  State<_DockButton> createState() => _DockButtonState();
}

class _DockButtonState extends State<_DockButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final size = widget.compact ? 44.0 : 52.0;
    final enlarged = _hovered || _pressed;

    return Semantics(
      button: true,
      label: widget.item.app.title,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: () async {
            final choice = await showModalBottomSheet<String>(
              context: context,
              backgroundColor: MicroColors.panelSolid,
              builder: (context) => SafeArea(
                child: ListTile(
                  leading: const Icon(Icons.close),
                  title: Text('Quit ${widget.item.app.title}'),
                  onTap: () => Navigator.pop(context, 'quit'),
                ),
              ),
            );
            if (choice == 'quit') widget.onQuit();
          },
          onHighlightChanged: (value) => setState(() => _pressed = value),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.compact ? 3 : 5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: enlarged ? 1.12 : 1,
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOutCubic,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.lerp(widget.item.color, Colors.white, 0.18)!,
                          widget.item.color,
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
                    child: Icon(widget.item.icon,
                        color: Colors.white, size: size * 0.5),
                  ),
                ),
                const SizedBox(height: 3),
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: widget.running
                        ? MicroColors.accent
                        : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!widget.compact)
                  Text(
                    widget.item.app.title,
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
      ),
    );
  }
}
