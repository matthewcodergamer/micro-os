import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/desktop_input.dart';
import '../core/theme.dart';

/// Floating controls for the native X11 desktop.
///
/// The collapsed square is deliberately AssistiveTouch-like so it stays out of
/// the way of remote windows. Expanding it reveals the Android keyboard, the
/// pointer-mode switch, the extra-key bar and a collapse button. This is
/// original widget code; it does not embed DroidDesk's GPL sources.
class DesktopControlsOverlay extends StatefulWidget {
  const DesktopControlsOverlay({
    super.key,
    required this.pointerMode,
    required this.keyBarVisible,
    required this.onKeyboard,
    required this.onCyclePointerMode,
    required this.onToggleKeyBar,
  });

  final DesktopPointerMode pointerMode;
  final bool keyBarVisible;
  final VoidCallback onKeyboard;
  final VoidCallback onCyclePointerMode;
  final VoidCallback onToggleKeyBar;

  @override
  State<DesktopControlsOverlay> createState() =>
      _DesktopControlsOverlayState();
}

class _DesktopControlsOverlayState extends State<DesktopControlsOverlay> {
  bool _expanded = false;
  double? _left;
  double _bottom = 14;
  double _lastWidth = 0;
  double _lastHeight = 0;
  Timer? _fadeTimer;
  double _idleOpacity = 1;

  @override
  void initState() {
    super.initState();
    _scheduleFade();
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    super.dispose();
  }

  void _scheduleFade() {
    _fadeTimer?.cancel();
    if (_expanded) return;
    _fadeTimer = Timer(const Duration(milliseconds: 3800), () {
      if (mounted && !_expanded) {
        setState(() => _idleOpacity = 0.55);
      }
    });
  }

  void _wakeHandle() {
    _fadeTimer?.cancel();
    if (_idleOpacity != 1) setState(() => _idleOpacity = 1);
    _scheduleFade();
  }

  void _setExpanded(bool value) {
    HapticFeedback.selectionClick();
    _fadeTimer?.cancel();
    setState(() {
      _expanded = value;
      _idleOpacity = 1;
    });
    if (!value) _scheduleFade();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;
        if (maxWidth < 120 || maxHeight < 120) {
          return const SizedBox.shrink();
        }
        _lastWidth = maxWidth;
        _lastHeight = maxHeight;

        final left =
            (_left ?? (maxWidth - 52 - 12)).clamp(6.0, maxWidth - 58).toDouble();
        final bottom = _bottom.clamp(6.0, maxHeight - 58).toDouble();
        return Stack(
          children: [
            if (_expanded)
              Positioned(
                left: 8,
                right: 8,
                bottom: 10,
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: _buildExpanded(maxWidth),
                ),
              )
            else
              Positioned(
                left: left,
                bottom: bottom,
                child: _buildCollapsed(),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCollapsed() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _wakeHandle(),
      onTap: () => _setExpanded(true),
      onPanStart: (_) => _wakeHandle(),
      onPanUpdate: (details) {
        setState(() {
          _left = ((_left ?? (_lastWidth - 52 - 12)) + details.delta.dx)
              .clamp(6.0, _lastWidth - 58)
              .toDouble();
          _bottom = (_bottom - details.delta.dy)
              .clamp(6.0, _lastHeight - 58)
              .toDouble();
        });
      },
      onPanEnd: (_) {
        setState(() {
          final center = (_left ?? 0) + 26;
          _left = center < _lastWidth / 2 ? 8.0 : _lastWidth - 60.0;
          _bottom = _bottom.clamp(6.0, _lastHeight - 58).toDouble();
        });
        _scheduleFade();
      },
      child: Semantics(
        button: true,
        label: 'Show desktop controls',
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 240),
          opacity: _idleOpacity,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xE6222834),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.42),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                ),
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpanded(double maxWidth) {
    final compact = maxWidth < 330;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: (maxWidth - 16).clamp(150.0, 340.0).toDouble(),
      ),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xEE171B24),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.16),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.48),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ControlAction(
              icon: Icons.keyboard_rounded,
              label: 'Keyboard',
              onTap: widget.onKeyboard,
            ),
            _ControlAction(
              icon: widget.pointerMode == DesktopPointerMode.trackpad
                  ? Icons.track_changes_rounded
                  : Icons.touch_app_rounded,
              label: compact ? null : widget.pointerMode.title,
              tint: widget.pointerMode == DesktopPointerMode.trackpad
                  ? MicroColors.accent
                  : MicroColors.green,
              onTap: widget.onCyclePointerMode,
            ),
            _ControlAction(
              icon: Icons.dialpad_rounded,
              label: null,
              tint: widget.keyBarVisible ? MicroColors.accent : null,
              onTap: widget.onToggleKeyBar,
            ),
            Container(
              width: 0.8,
              height: 22,
              color: Colors.white.withValues(alpha: 0.10),
            ),
            _ControlAction(
              icon: Icons.close_rounded,
              label: 'Hide',
              onTap: () => _setExpanded(false),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlAction extends StatelessWidget {
  const _ControlAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tint,
  });

  final IconData icon;
  final String? label;
  final VoidCallback onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final color = tint ?? Colors.white;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Semantics(
        button: true,
        label: label ?? 'Desktop control',
        child: Container(
          height: 40,
          padding: EdgeInsets.symmetric(horizontal: label == null ? 10 : 11),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: color),
              if (label != null) ...[
                const SizedBox(width: 6),
                Text(
                  label!,
                  style: TextStyle(
                    color: color,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
