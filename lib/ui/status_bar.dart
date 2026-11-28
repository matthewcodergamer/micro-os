import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../core/format.dart';
import '../core/macos_design.dart';
import '../core/shell_mode.dart';
import '../core/theme.dart';

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
    final settings = scope.settings;
    final focused = desktop.focused;

    return Material(
      color: Colors.transparent,
      // Tint only, deliberately no BackdropFilter: the menu bar spans the same
      // pixels as maximised windows, and blurring a region that contains an
      // Android platform view (the native X11 TextureView) blanks that region
      // on some GPUs. A translucent gradient gives the Sequoia look without the risk.
      child: Container(
        height: widget.height,
        // The status bar includes the cutout inset, but the menu items must sit
        // in the clear strip below a notch or camera island.
        padding: EdgeInsets.only(
          top: math.max(0, widget.height - kMenuBarHeight),
          left: 10,
          right: 10,
        ),
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
              label: '\uF8FF',
              items: [
                PopupMenuItem(
                  onTap: () {},
                  child: const Text('About Misty OS'),
                ),
                const PopupMenuDivider(),
                PopupMenuItem<void>(
                  enabled: false,
                  child: Text(
                    'Window Style',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                for (final mode in ShellMode.values)
                  CheckedPopupMenuItem(
                    checked: settings.shellMode == mode,
                    onTap: () => settings.setShellMode(mode),
                    child: Text(mode.title),
                  ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  onTap: widget.onLock,
                  child: const Text('Lock Screen'),
                ),
              ],
            ),
            const SizedBox(width: 4),
            // Focused app name
            Flexible(
              child: Text(
                focused?.title ?? 'Finder',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            // Status items
            IconButton(
              icon: const Icon(
                Icons.search_rounded,
                size: 18,
                color: Colors.white,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
              onPressed: widget.onSpotlight,
              tooltip: 'Spotlight',
            ),
            IconButton(
              icon: const Icon(
                Icons.apps_rounded,
                size: 19,
                color: Colors.white,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
              onPressed: widget.onLaunchpad,
              tooltip: 'Launchpad',
            ),
            IconButton(
              icon: const Icon(
                Icons.tune_rounded,
                size: 19,
                color: Colors.white,
              ),
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
