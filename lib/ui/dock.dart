import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/window_state.dart';
import '../state/desktop_state.dart';
import 'mac_icons.dart';

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

  Future<void> _showLaunchpad(BuildContext context) async {
    final apps = AppId.values;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xF0181D29),
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 38, height: 4, decoration: BoxDecoration(
                color: Colors.white30, borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 16),
              const Align(alignment: Alignment.centerLeft, child: Text(
                'Launchpad', style: TextStyle(color: MicroColors.text,
                  fontSize: 22, fontWeight: FontWeight.w700))),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: apps.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, mainAxisSpacing: 18, crossAxisSpacing: 12,
                  childAspectRatio: 0.92),
                itemBuilder: (context, index) {
                  final app = apps[index];
                  final item = _itemFor(app);
                  return InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () { Navigator.pop(sheetContext); onOpen(app); },
                    child: Column(mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        MacAppIcon(app: app, size: 62),
                        const SizedBox(height: 8),
                        Text(app.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: MicroColors.text, fontSize: 11)),
                        if (desktop.isRunning(app)) const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: CircleAvatar(radius: 2, backgroundColor: MicroColors.accent)),
                      ]));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  _DockItem _itemFor(AppId app) => switch (app) {
    AppId.terminal => _DockItem(app, Icons.terminal, const Color(0xFF2B2F3A)),
    AppId.desktop => _DockItem(app, Icons.desktop_windows, const Color(0xFF1F6FEB)),
    AppId.browser => _DockItem(app, Icons.travel_explore, const Color(0xFF7C4DFF)),
    AppId.files => _DockItem(app, Icons.folder_rounded, const Color(0xFFF0A32B)),
    AppId.torrents => _DockItem(app, Icons.downloading_rounded, const Color(0xFF36B7A5)),
    AppId.aiHub => _DockItem(app, Icons.auto_awesome, const Color(0xFF00A67E)),
    AppId.settings => _DockItem(app, Icons.settings, const Color(0xFF5A6472)),
  };

  @override
  Widget build(BuildContext context) {
    final items = <_DockItem>[
      _DockItem(AppId.terminal, Icons.terminal, const Color(0xFF2B2F3A)),
      _DockItem(AppId.desktop, Icons.desktop_windows, const Color(0xFF1F6FEB)),
      _DockItem(AppId.browser, Icons.travel_explore, const Color(0xFF7C4DFF)),
      _DockItem(AppId.files, Icons.folder_rounded, const Color(0xFFF0A32B)),
      _DockItem(AppId.torrents, Icons.downloading_rounded, const Color(0xFF36B7A5)),
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
              _LaunchpadButton(compact: compact, onTap: () => _showLaunchpad(context)),
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
    final size = widget.compact ? 38.0 : 52.0;
    final enlarged = _hovered || _pressed;

    return Semantics(
      button: true,
      label: widget.item.app.title,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          onTap: widget.onTap,
          onDoubleTap: widget.onQuit,
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
            padding: EdgeInsets.symmetric(horizontal: widget.compact ? 1 : 5),
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


class _LaunchpadButton extends StatelessWidget {
  const _LaunchpadButton({required this.compact, required this.onTap});
  final bool compact;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Launchpad',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 1 : 5),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: compact ? 38 : 52, height: compact ? 38 : 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF6C7CFF), Color(0xFF9B55E8)]),
              borderRadius: BorderRadius.circular(14)),
            child: Icon(Icons.apps_rounded, color: Colors.white, size: compact ? 23 : 27)),
          const SizedBox(height: 3),
          const SizedBox(height: 4),
          if (!compact) const Text('Launchpad', style: TextStyle(color: MicroColors.subtle, fontSize: 9)),
        ]),
      ),
    ),
  );
}
