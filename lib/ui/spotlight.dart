import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/linux_apps.dart';
import '../core/macos_design.dart';
import '../core/theme.dart';
import '../models/window_state.dart';
import 'mac_icons.dart';

/// One searchable Launchpad/Spotlight result, native or a real Linux app.
class _LauncherEntry {
  const _LauncherEntry.native(AppId app)
    : native = app,
      linux = null;

  const _LauncherEntry.linux(LinuxApp app)
    : native = null,
      linux = app;

  final AppId? native;
  final LinuxApp? linux;

  String get title => native?.title ?? linux!.title;
  String get subtitle => native?.subtitle ?? linux!.subtitle;

  bool get available => native == null || isAppAvailable(native!);

  String get label =>
      native != null && !isAppAvailable(native!) ? '$title · soon' : title;

  Widget icon(double size) {
    final linuxApp = linux;
    if (linuxApp != null) {
      return LinuxAppIcon(app: linuxApp, size: size);
    }
    return MacAppIcon(app: native!, size: size);
  }
}


/// Spotlight: tap the magnifier in the menu bar, type, hit Return to launch.
class SpotlightOverlay extends StatefulWidget {
  const SpotlightOverlay({
    super.key,
    required this.topPadding,
    required this.onClose,
    required this.onOpen,
    required this.onOpenLinux,
  });

  final double topPadding;
  final VoidCallback onClose;
  final ValueChanged<AppId> onOpen;
  final ValueChanged<LinuxApp> onOpenLinux;

  @override
  State<SpotlightOverlay> createState() => _SpotlightOverlayState();
}

class _SpotlightOverlayState extends State<SpotlightOverlay> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_LauncherEntry> get _results {
    final q = _query.trim().toLowerCase();
    final all = <_LauncherEntry>[
      for (final app in AppId.values) _LauncherEntry.native(app),
      for (final app in kLinuxApps) _LauncherEntry.linux(app),
    ];
    if (q.isEmpty) return all;
    return all
        .where(
          (entry) =>
              entry.title.toLowerCase().contains(q) ||
              entry.subtitle.toLowerCase().contains(q),
        )
        .toList(growable: false);
  }

  void _open(_LauncherEntry entry) {
    final linuxApp = entry.linux;
    if (linuxApp != null) {
      widget.onOpenLinux(linuxApp);
    } else {
      widget.onOpen(entry.native!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onClose,
            child: const ColoredBox(color: Color(0x55000000)),
          ),
        ),
        Positioned(
          top: widget.topPadding + 14,
          left: 14,
          right: 14,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: Sequoia.spotlightMaxWidth,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _glass(
                    radius: Sequoia.sheetRadius,
                    child: SizedBox(
                      height: 52,
                      child: Row(
                        children: [
                          const SizedBox(width: 16),
                          const Icon(
                            Icons.search_rounded,
                            color: Colors.white70,
                            size: 24,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              autofocus: true,
                              textInputAction: TextInputAction.go,
                              cursorColor: Colors.white,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Spotlight Search',
                                hintStyle: TextStyle(color: Colors.white54),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onChanged: (v) => setState(() => _query = v),
                              onSubmitted: (_) {
                                if (results.isNotEmpty) {
                                  _open(results.first);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                      ),
                    ),
                  ),
                  if (results.isNotEmpty) const SizedBox(height: 8),
                  if (results.isNotEmpty)
                    _glass(
                      radius: Sequoia.popoverRadius,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < results.length && i < 6; i++)
                            _row(results[i], highlighted: i == 0),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(_LauncherEntry entry, {required bool highlighted}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _open(entry),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: highlighted && _query.isNotEmpty
              ? MicroColors.accent.withValues(alpha: 0.85)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(Sequoia.cardRadius),
        ),
        child: Row(
          children: [
            entry.icon(30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  Text(
                    entry.subtitle,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glass({required double radius, required Widget child}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: Sequoia.panelShadow(),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            decoration: Sequoia.glass(
              radius: radius,
              tint: 0.74,
              borderAlpha: 0.24,
              base: const Color(0xFF202024),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Launchpad-style app grid for the complete Misty OS app registry.
class LaunchpadOverlay extends StatefulWidget {
  const LaunchpadOverlay({
    super.key,
    required this.topPadding,
    required this.onClose,
    required this.onOpen,
    required this.onOpenLinux,
  });

  final double topPadding;
  final VoidCallback onClose;
  final ValueChanged<AppId> onOpen;
  final ValueChanged<LinuxApp> onOpenLinux;

  @override
  State<LaunchpadOverlay> createState() => _LaunchpadOverlayState();
}

class _LaunchpadOverlayState extends State<LaunchpadOverlay> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(_LauncherEntry entry) {
    final linuxApp = entry.linux;
    if (linuxApp != null) {
      widget.onOpenLinux(linuxApp);
    } else {
      widget.onOpen(entry.native!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final apps = <_LauncherEntry>[
      for (final app in AppId.values) _LauncherEntry.native(app),
      for (final app in kLinuxApps) _LauncherEntry.linux(app),
    ]
        .where(
          (entry) =>
              query.isEmpty ||
              entry.title.toLowerCase().contains(query) ||
              entry.subtitle.toLowerCase().contains(query),
        )
        .toList(growable: false);
    return Stack(
      children: [
        Positioned.fill(
          child: Material(
            color: const Color(0xD9101014),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        18,
                        widget.topPadding > 0 ? 14 : 20,
                        18,
                        10,
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Launchpad',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close Launchpad',
                            onPressed: widget.onClose,
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search apps',
                            hintStyle: const TextStyle(color: Colors.white54),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: Colors.white70,
                            ),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.12),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.16),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.16),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth;
                          final columns = width < 380
                              ? 3
                              : width < 620
                              ? 4
                              : 6;
                          return GridView.builder(
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  mainAxisSpacing: 14,
                                  crossAxisSpacing: 8,
                                  childAspectRatio: 0.82,
                                ),
                            itemCount: apps.length,
                            itemBuilder: (context, index) {
                              final entry = apps[index];
                              return Semantics(
                                button: true,
                                label: entry.title,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(18),
                                  onTap: () => _open(entry),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                      vertical: 7,
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Opacity(
                                          opacity: entry.available ? 1.0 : 0.42,
                                          child: entry.icon(58),
                                        ),
                                        const SizedBox(height: 9),
                                        Text(
                                          entry.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            decoration: TextDecoration.none,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
