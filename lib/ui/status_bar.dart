import 'dart:async';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../core/format.dart';
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
      child: Container(
        height: widget.height,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xCC1C1C1E),
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
        child: Row(
          children: [
            // Apple menu
            _MenuButton(
              label: '',
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
            IconButton(
              icon: const Icon(Icons.search_rounded, size: 18, color: Colors.white),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
              onPressed: widget.onSpotlight,
              tooltip: 'Spotlight',
            ),
            IconButton(
              icon: const Icon(Icons.apps_rounded, size: 19, color: Colors.white),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
              onPressed: widget.onLaunchpad,
              tooltip: 'Launchpad',
            ),
            IconButton(
              icon: const Icon(Icons.toggle_on_rounded, size: 20, color: Colors.white),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
              onPressed: widget.onControlCenter,
              tooltip: 'Control Center',
            ),
            const SizedBox(width: 4),
            Text(
              menuBarDate(_now, compact: true),
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
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
