import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../core/macos_design.dart';
import '../core/theme.dart';
import '../models/window_state.dart';
import '../state/desktop_state.dart';
import 'mac_icons.dart';

/// Floating macOS-style Dock with touch-sized artwork.
///
/// The Dock keeps the same application set in every orientation. It appears
/// with a short spring-like rise, magnifies the hovered icon and never leaves
/// an invisible hit target behind once it has auto-hidden.
class Dock extends StatefulWidget {
  const Dock({
    super.key,
    required this.onOpen,
    required this.visible,
    this.onInteraction,
  });

  final ValueChanged<AppId> onOpen;
  final bool visible;

  /// Called when the user touches or hovers the Dock so the owner can keep the
  /// auto-hide timer alive while the Dock is in use.
  final VoidCallback? onInteraction;

  static const _apps = <AppId>[
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

class _DockState extends State<Dock> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _slide;
  late final Animation<double> _scale;
  int? _hoveredIndex;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      reverseDuration: const Duration(milliseconds: 260),
      value: widget.visible ? 1 : 0,
    );
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.05, 0.82, curve: Curves.easeOut),
      reverseCurve: Curves.easeIn,
    );
    _slide = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _scale = Tween<double>(begin: 0.90, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      ),
    );
  }

  @override
  void didUpdateWidget(Dock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible == oldWidget.visible) return;
    if (widget.visible) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setHovered(int? index) {
    if (_hoveredIndex == index) return;
    setState(() => _hoveredIndex = index);
    if (index != null) widget.onInteraction?.call();
  }

  /// Long-press menu for a running app. Quitting is destructive, so it should
  /// never be a one-finger slip on the Dock.
  Future<void> _showAppMenu(
    BuildContext context,
    DesktopState desktop,
    AppId app,
  ) async {
    if (!desktop.isRunning(app)) return;
    HapticFeedback.mediumImpact();
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        void run(VoidCallback action) {
          Navigator.of(sheetContext).pop();
          action();
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xF71C1C1F),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.10),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 32,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(top: 9, bottom: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                  child: Row(
                    children: [
                      MacAppIcon(app: app, size: 34),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              app.title,
                              style: const TextStyle(
                                color: MicroColors.text,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Running',
                              style: TextStyle(
                                color: Sequoia.green.withValues(alpha: 0.9),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close menu',
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: MicroColors.subtle,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.07),
                ),
                const SizedBox(height: 4),
                _DockMenuItem(
                  icon: Icons.open_in_new_rounded,
                  label: 'Bring to front',
                  onTap: () => run(() {
                    final window = desktop.windowFor(app);
                    if (window != null) desktop.focus(window.id);
                  }),
                ),
                _DockMenuItem(
                  icon: Icons.keyboard_arrow_down_rounded,
                  label: 'Minimize',
                  onTap: () => run(() {
                    final window = desktop.windowFor(app);
                    if (window != null) desktop.minimize(window.id);
                  }),
                ),
                _DockMenuItem(
                  icon: Icons.power_settings_new_rounded,
                  label: 'Quit',
                  destructive: true,
                  onTap: () => run(() {
                    for (final window in [...desktop.windows]) {
                      if (window.app == app) desktop.close(window.id);
                    }
                  }),
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        );
      },
    );
  }

  double _magnification(int index) {
    final hovered = _hoveredIndex;
    if (hovered == null) return 1;
    final distance = (index - hovered).abs();
    if (distance == 0) return 1.20;
    if (distance == 1) return 1.08;
    if (distance == 2) return 1.025;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final desktop = AppScope.of(context).desktop;
    final screen = MediaQuery.sizeOf(context);
    final landscape = screen.width > screen.height;
    final compact = screen.width < 600;
    final iconSize = landscape
        ? (screen.height < 420 ? 34.0 : 40.0)
        : compact
        ? (screen.width < 360 ? 38.0 : (screen.width < 380 ? 42.0 : 46.0))
        : 54.0;
    final spacing = landscape ? 5.0 : (compact ? 7.0 : 10.0);
    final horizontalPadding = landscape ? 10.0 : 12.0;
    // Hug the artwork instead of stretching a mostly empty bar across a
    // tablet. Six icons and their gaps define the Dock's natural width.
    final contentWidth =
        iconSize * Dock._apps.length +
        spacing * (Dock._apps.length - 1) +
        horizontalPadding * 2;
    final dockWidth = math.min(screen.width - 20, contentWidth);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return IgnorePointer(
          ignoring: !widget.visible,
          child: ExcludeSemantics(
            excluding: !widget.visible,
            child: Opacity(
              opacity: _fade.value.clamp(0.0, 1.0).toDouble(),
              child: Transform.translate(
                offset: Offset(0, (1 - _slide.value) * 68),
                child: Transform.scale(
                  scale: _scale.value,
                  alignment: Alignment.bottomCenter,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
      child: Center(
        child: Padding(
          padding: EdgeInsets.only(bottom: landscape ? 4 : 8),
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => widget.onInteraction?.call(),
            child: MouseRegion(
              onEnter: (_) => widget.onInteraction?.call(),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Container(
                  width: dockWidth,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xE62E2E33), Color(0xD91A1A1E)],
                    ),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                      width: 0.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.42),
                        blurRadius: 32,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // Fine top highlight: the frosted edge catches light even
                      // when a native Android surface sits behind the Dock.
                      Positioned(
                        top: 0,
                        left: 18,
                        right: 18,
                        child: Container(
                          height: 0.8,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0),
                                Colors.white.withValues(alpha: 0.34),
                                Colors.white.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                          vertical: landscape ? 6 : 8,
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: dockWidth - horizontalPadding * 2,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                for (
                                  var index = 0;
                                  index < Dock._apps.length;
                                  index++
                                ) ...[
                                  MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    onEnter: (_) => _setHovered(index),
                                    onExit: (_) {
                                      if (_hoveredIndex == index) {
                                        _setHovered(null);
                                      }
                                    },
                                    child: _DockItem(
                                      app: Dock._apps[index],
                                      running: desktop.isRunning(
                                        Dock._apps[index],
                                      ),
                                      size: iconSize,
                                      scale: _magnification(index),
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        widget.onInteraction?.call();
                                        widget.onOpen(Dock._apps[index]);
                                      },
                                      onLongPress:
                                          desktop.isRunning(Dock._apps[index])
                                          ? () => _showAppMenu(
                                              context,
                                              desktop,
                                              Dock._apps[index],
                                            )
                                          : null,
                                    ),
                                  ),
                                  if (index != Dock._apps.length - 1)
                                    SizedBox(width: spacing),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
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

class _DockItem extends StatefulWidget {
  const _DockItem({
    required this.app,
    required this.running,
    required this.size,
    required this.scale,
    required this.onTap,
    this.onLongPress,
  });

  final AppId app;
  final bool running;
  final double size;
  final double scale;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  State<_DockItem> createState() => _DockItemState();
}

class _DockItemState extends State<_DockItem> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final visualScale = widget.scale * (_pressed ? 0.90 : 1);
    return Semantics(
      button: true,
      label: widget.app.title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: SizedBox(
          width: widget.size,
          height: widget.size + 18,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // The artwork can grow past its slot while hovered. Reserve the
              // extra vertical room so the Dock never changes height mid-hover.
              SizedBox(
                width: widget.size,
                height: widget.size + 8,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedScale(
                    scale: visualScale,
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.bottomCenter,
                    child: MacAppIcon(app: widget.app, size: widget.size),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              RunningDot(active: widget.running),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockMenuItem extends StatelessWidget {
  const _DockMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Sequoia.closeLight : MicroColors.text;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          child: Row(
            children: [
              Icon(icon, size: 19, color: color),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
