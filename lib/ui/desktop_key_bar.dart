import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';

/// Row of keys a phone keyboard lacks: Escape, Tab, Ctrl, Alt, arrows and the
/// navigation cluster. DroidDesk's native desktop is the interaction reference;
/// this is Misty OS's own implementation over the native X11 surface.
///
/// Ctrl and Alt are sticky: tap once to hold them for the next key, tap a
/// second time to lock them, and a third time to release them. The bar talks
/// to the X11 surface through callbacks; it never sends shell commands.
class DesktopKeyBar extends StatefulWidget {
  const DesktopKeyBar({
    super.key,
    required this.onKeyEvent,
    required this.onText,
    this.onHide,
  });

  /// Sends an X11 key press/release through the native surface.
  final Future<void> Function(int keysym, String code, bool down) onKeyEvent;

  /// Types an arbitrary Unicode string, including symbols that need Shift.
  final Future<void> Function(String text) onText;

  /// Removes the bar from the layout (the user can bring it back).
  final VoidCallback? onHide;

  @override
  State<DesktopKeyBar> createState() => DesktopKeyBarState();
}

class _DesktopKey {
  const _DesktopKey.code(this.label, this.code, this.keyCode)
      : text = null,
        isModifier = false;

  const _DesktopKey.text(this.label, this.text)
      : code = null,
        keyCode = null,
        isModifier = false;

  const _DesktopKey.modifier(this.label, this.code, this.keyCode)
      : text = null,
        isModifier = true;

  final String label;
  final String? code;
  final int? keyCode;
  final String? text;
  final bool isModifier;
}

enum _StickyState { off, once, locked }

class DesktopKeyBarState extends State<DesktopKeyBar> {
  static const List<_DesktopKey> _keys = <_DesktopKey>[
    _DesktopKey.code('ESC', 'Escape', 27),
    _DesktopKey.code('TAB', 'Tab', 9),
    _DesktopKey.modifier('CTRL', 'ControlLeft', 17),
    _DesktopKey.modifier('ALT', 'AltLeft', 18),
    _DesktopKey.code('←', 'ArrowLeft', 37),
    _DesktopKey.code('↓', 'ArrowDown', 40),
    _DesktopKey.code('↑', 'ArrowUp', 38),
    _DesktopKey.code('→', 'ArrowRight', 39),
    _DesktopKey.code('HOME', 'Home', 36),
    _DesktopKey.code('END', 'End', 35),
    _DesktopKey.code('PGUP', 'PageUp', 33),
    _DesktopKey.code('PGDN', 'PageDown', 34),
    _DesktopKey.code('⌫', 'Backspace', 8),
    _DesktopKey.code('⏎', 'Enter', 13),
    _DesktopKey.text('-', '-'),
    _DesktopKey.text('/', '/'),
    _DesktopKey.text('|', '|'),
  ];

  static const Map<String, int> _keysyms = <String, int>{
    'Escape': 0xff1b,
    'Tab': 0xff09,
    'ControlLeft': 0xffe3,
    'AltLeft': 0xffe9,
    'ArrowLeft': 0xff51,
    'ArrowDown': 0xff52,
    'ArrowUp': 0xff53,
    'ArrowRight': 0xff54,
    'Home': 0xff50,
    'End': 0xff57,
    'PageUp': 0xff55,
    'PageDown': 0xff56,
    'Backspace': 0xff08,
    'Enter': 0xff0d,
  };

  final Map<String, _StickyState> _modifiers = <String, _StickyState>{
    'ControlLeft': _StickyState.off,
    'AltLeft': _StickyState.off,
  };
  final Set<String> _heldCodes = <String>{};

  static int _keysymFor(String code) => _keysyms[code] ?? 0;

  @override
  void dispose() {
    // Best effort: never leave a stuck Ctrl/Alt in the remote X server when
    // the desktop window closes or the session reconnects.
    for (final entry in _modifiers.entries) {
      if (entry.value != _StickyState.off) {
        unawaited(widget.onKeyEvent(_keysymFor(entry.key), entry.key, false));
      }
    }
    super.dispose();
  }

  Future<void> _cycleModifier(_DesktopKey key) async {
    final code = key.code;
    if (code == null) return;
    final current = _modifiers[code] ?? _StickyState.off;
    HapticFeedback.selectionClick();
    switch (current) {
      case _StickyState.off:
        await widget.onKeyEvent(_keysymFor(code), code, true);
        if (!mounted) return;
        setState(() => _modifiers[code] = _StickyState.once);
        break;
      case _StickyState.once:
        setState(() => _modifiers[code] = _StickyState.locked);
        break;
      case _StickyState.locked:
        await widget.onKeyEvent(_keysymFor(code), code, false);
        if (!mounted) return;
        setState(() => _modifiers[code] = _StickyState.off);
        break;
    }
  }

  Future<void> _releaseOneShot() async {
    var changed = false;
    for (final entry in _modifiers.entries.toList()) {
      if (entry.value != _StickyState.once) continue;
      await widget.onKeyEvent(_keysymFor(entry.key), entry.key, false);
      _modifiers[entry.key] = _StickyState.off;
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  /// Called when the Android keyboard types a real key, so a one-shot Ctrl or
  /// Alt is released exactly like a hardware modifier.
  Future<void> releaseOneShotModifiers() => _releaseOneShot();

  /// Releases every held modifier. Called when the bar is hidden.
  Future<void> releaseAllModifiers() async {
    var changed = false;
    for (final entry in _modifiers.entries.toList()) {
      if (entry.value == _StickyState.off) continue;
      await widget.onKeyEvent(_keysymFor(entry.key), entry.key, false);
      _modifiers[entry.key] = _StickyState.off;
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  void _pressCode(_DesktopKey key) {
    final code = key.code;
    if (code == null || !_heldCodes.add(code)) return;
    HapticFeedback.selectionClick();
    unawaited(widget.onKeyEvent(_keysymFor(code), code, true));
  }

  void _releaseCode(_DesktopKey key) {
    final code = key.code;
    if (code == null || !_heldCodes.remove(code)) return;
    unawaited(widget.onKeyEvent(_keysymFor(code), code, false));
    unawaited(_releaseOneShot());
  }

  void _typeText(_DesktopKey key) {
    final text = key.text;
    if (text == null) return;
    HapticFeedback.selectionClick();
    unawaited(widget.onText(text));
    unawaited(_releaseOneShot());
  }

  Color _keyColor(_DesktopKey key) {
    final code = key.code;
    if (code == null) return const Color(0xFF2A3342);
    final state = _modifiers[code];
    return switch (state) {
      _StickyState.once => const Color(0xFF1D6BC4),
      _StickyState.locked => const Color(0xFF128A68),
      _ => const Color(0xFF2A3342),
    };
  }

  Widget _buildKey(_DesktopKey key) {
    final isModifier = key.isModifier;
    final state = key.code == null ? null : _modifiers[key.code];
    final isLocked = state == _StickyState.locked;

    Widget keyCap = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      height: 32,
      constraints: const BoxConstraints(minWidth: 38),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _keyColor(key),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: Colors.white.withValues(alpha: isModifier ? 0.16 : 0.08),
          width: 0.8,
        ),
      ),
      child: Text(
        key.label,
        maxLines: 1,
        style: TextStyle(
          color: isLocked ? const Color(0xFFB6FFE8) : Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          decoration: isLocked ? TextDecoration.underline : TextDecoration.none,
          decorationColor: const Color(0xFFB6FFE8),
        ),
      ),
    );

    if (key.text != null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _typeText(key),
        child: Semantics(button: true, label: 'Type ${key.label}', child: keyCap),
      );
    }

    if (isModifier) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(_cycleModifier(key)),
        child: Semantics(
          button: true,
          toggled: state == _StickyState.locked,
          label: '${key.label} modifier',
          child: keyCap,
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _pressCode(key),
      onTapUp: (_) => _releaseCode(key),
      onTapCancel: () => _releaseCode(key),
      child: Semantics(button: true, label: key.label, child: keyCap),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xF2181D27),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.10), width: 0.8),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Row(
                children: [
                  for (final key in _keys)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.5),
                      child: _buildKey(key),
                    ),
                ],
              ),
            ),
          ),
          if (widget.onHide != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                unawaited(releaseAllModifiers());
                widget.onHide?.call();
              },
              child: Semantics(
                button: true,
                label: 'Hide extra keys',
                child: Container(
                  width: 40,
                  height: 44,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.keyboard_hide_rounded,
                    color: MicroColors.subtle,
                    size: 18,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
