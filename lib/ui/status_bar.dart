import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../app_scope.dart';
import '../core/format.dart';
import '../core/macos_design.dart';
import '../core/theme.dart';
import '../models/window_state.dart';
import '../state/desktop_state.dart';

/// The macOS-style menu bar (Apple menu, app menus, status items, clock).
class StatusBar extends StatefulWidget {
  const StatusBar({
    super.key,
    required this.height,
    required this.onSpotlight,
    required this.onLaunchpad,
    required this.onControlCenter,
    required this.onLock,
  });

  final double height;
  final VoidCallback onSpotlight;
  final VoidCallback onLaunchpad;
  final VoidCallback onControlCenter;
  final VoidCallback onLock;

  @override
  State<StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends State<StatusBar> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final desktop = scope.desktop;
    final focused = desktop.focused;

    return Material(
      color: Colors.transparent,
      // Tint only, deliberately no BackdropFilter: the menu bar spans the same
      // pixels as maximised windows, and blurring a region that contains an
      // Android platform view (the noVNC surface) blanks that region on some
      // GPUs. A translucent gradient gives the Sequoia look without the risk.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 390;
          final showDate = constraints.maxWidth >= 340;
          return Container(
        height: widget.height,
        padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Sequoia.chromeBase.withValues(alpha: 0.72),
              Sequoia.chromeBase.withValues(alpha: 0.58),
            ],
          ),
          border: Border(
            bottom: BorderSide(
              color: Colors.white.withValues(alpha: 0.10),
              width: 0.8,
            ),
          ),
        ),
        child: Row(
          children: [
            // Apple menu
            _MenuButton(
              label: 'Misty',
              items: [
                PopupMenuItem(
                  onTap: () {},
                  child: const Text('About Misty OS'),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  onTap: widget.onLock,
                  child: const Text('Lock Screen'),
                ),
              ],
            ),
            const SizedBox(width: 6),
            // Focused app name
            Text(
              focused?.title ?? 'Finder',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            // Status items
            _StatusAction(
              tooltip: 'Spotlight',
              onPressed: widget.onSpotlight,
              icon: CupertinoIcons.search,
              size: compact ? 17 : 18,
            ),
            _StatusAction(
              tooltip: 'Launchpad',
              onPressed: widget.onLaunchpad,
              icon: CupertinoIcons.square_grid_2x2,
              size: compact ? 17 : 18,
            ),
            _StatusAction(
              tooltip: 'Control Center',
              onPressed: widget.onControlCenter,
              icon: CupertinoIcons.slider_horizontal_3,
              size: compact ? 17 : 18,
            ),
            if (showDate) ...[
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  menuBarDate(_now, compact: true),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: compact ? 11 : 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.15,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
        },
      ),
    );
  }
}

class _StatusAction extends StatelessWidget {
  const _StatusAction({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    required this.size,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(icon, size: size, color: Colors.white),
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 30, minHeight: 28),
    visualDensity: VisualDensity.compact,
    splashRadius: 17,
    onPressed: onPressed,
    tooltip: tooltip,
  );
}



class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.label, required this.items});

  final String label;
  final List<PopupMenuEntry<void>> items;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<void>(
      padding: EdgeInsets.zero,
      offset: const Offset(0, 28),
      itemBuilder: (_) => items,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
