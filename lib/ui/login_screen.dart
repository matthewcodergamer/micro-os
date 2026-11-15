import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../services/settings_store.dart';

/// Full-screen lock / login surface shown when DesktopState.locked is true.
///
/// Behaviour follows macOS: the account is shown first, then a tap or an upward
/// swipe slides the profile up and fades the password field into view. A wrong
/// password shakes the panel instead of silently doing nothing.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.settings,
    required this.onUnlock,
  });

  final SettingsStore settings;
  final VoidCallback onUnlock;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final TextEditingController _password = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();
  String? _error;
  bool _obscure = true;
  bool _revealed = false;
  Timer? _clockTimer;

  late final AnimationController _entrance;
  late final AnimationController _shake;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  bool get _needsPassword => widget.settings.hasPassword;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.035),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic));
    _entrance.forward();

    // A password-less system skips the second stage entirely.
    _revealed = !_needsPassword;

    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _entrance.dispose();
    _shake.dispose();
    _passwordFocus.dispose();
    _password.dispose();
    super.dispose();
  }

  void _reveal() {
    if (_revealed) return;
    setState(() {
      _revealed = true;
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _passwordFocus.requestFocus();
    });
  }

  void _tryUnlock() {
    if (widget.settings.loginPasswordStorageUnavailable) {
      setState(
        () => _error = 'Secure password storage is unavailable. Restart Misty OS and try again.',
      );
      _shake.forward(from: 0);
      return;
    }
    final stored = widget.settings.loginPassword;
    if (stored == null || stored.isEmpty) {
      HapticFeedback.selectionClick();
      widget.onUnlock();
      return;
    }
    if (_password.text == stored) {
      HapticFeedback.selectionClick();
      widget.onUnlock();
      return;
    }
    setState(() => _error = 'Incorrect password. Try again.');
    _password.clear();
    HapticFeedback.heavyImpact();
    _shake.forward(from: 0);
    _passwordFocus.requestFocus();
  }

  Widget _avatar(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A84FF), Color(0xFF5E5CE6)],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.35),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 22,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Icon(Icons.person_rounded, color: Colors.white, size: size * 0.55),
    );
  }

  Widget _revealHint() {
    return TextButton(
      onPressed: _reveal,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          decoration: TextDecoration.none,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(
            Icons.keyboard_arrow_up_rounded,
            size: 18,
            color: Colors.white70,
          ),
          SizedBox(width: 4),
          Text('Tap or swipe up to unlock'),
        ],
      ),
    );
  }

  Widget _passwordPanel() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Column(
        children: [
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 18,
                ),
              ],
            ),
            padding: const EdgeInsets.only(left: 18, right: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _password,
                    focusNode: _passwordFocus,
                    obscureText: _obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      decoration: TextDecoration.none,
                    ),
                    cursorColor: Colors.white,
                    decoration: const InputDecoration(
                      hintText: 'Enter Password',
                      hintStyle: TextStyle(
                        color: Colors.white60,
                        decoration: TextDecoration.none,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onSubmitted: (_) => _tryUnlock(),
                  ),
                ),
                IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    color: Colors.white70,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _error == null
                ? const SizedBox.shrink(key: ValueKey('no-error'))
                : Text(
                    _error!,
                    key: ValueKey(_error),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFFB4AB),
                      fontSize: 12,
                      height: 1.35,
                      decoration: TextDecoration.none,
                    ),
                  ),
          ),
          const SizedBox(height: 14),
          Tooltip(
            message: 'Unlock Misty OS',
            child: FilledButton(
              onPressed: _tryUnlock,
              child: const Text('Unlock Misty OS'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _continuePanel() {
    return Column(
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFFFB4AB),
                fontSize: 12,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        FilledButton(
          onPressed: _tryUnlock,
          child: const Text('Continue to Desktop'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final screen = MediaQuery.sizeOf(context);
    final shortScreen = screen.height < 620;
    final clockSize = math.min(
      84.0,
      math.min(screen.width * 0.22, screen.height * 0.15),
    );
    final avatarSize = shortScreen ? 68.0 : 88.0;
    // Explicit gaps instead of Spacer: the content lives in a scroll view so a
    // short screen (landscape phone, split screen, keyboard open) can never
    // overflow or push the Unlock button out of reach.
    final topGap = shortScreen
        ? 8.0
        : (screen.height * 0.07).clamp(16.0, 96.0).toDouble();

    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Readability scrim over the wallpaper.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x4D000000), Color(0x99000000)],
              ),
            ),
          ),
          FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(height: topGap),
                            // The clock lifts slightly as the profile reveals.
                            AnimatedSlide(
                              duration: const Duration(milliseconds: 420),
                              curve: Curves.easeOutCubic,
                              offset: _revealed && _needsPassword
                                  ? const Offset(0, -0.08)
                                  : Offset.zero,
                              child: Column(
                                children: [
                                  Text(
                                    lockTime(now),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: clockSize,
                                      fontWeight: FontWeight.w200,
                                      letterSpacing: -1.5,
                                      height: 1,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    lockDate(now),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w400,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: shortScreen ? 26 : 44),
                            AnimatedBuilder(
                              animation: _shake,
                              builder: (context, child) {
                                final progress = _shake.value;
                                final offset =
                                    math.sin(progress * math.pi * 10) *
                                    (1 - progress) *
                                    8;
                                return Transform.translate(
                                  offset: Offset(offset, 0),
                                  child: child,
                                );
                              },
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _needsPassword ? _reveal : null,
                                onVerticalDragEnd: (details) {
                                  // Swipe up (negative dy) on the profile reveals
                                  // the password panel, matching macOS.
                                  if (details.velocity.pixelsPerSecond.dy <
                                      -20) {
                                    _reveal();
                                  }
                                },
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _avatar(avatarSize),
                                    const SizedBox(height: 14),
                                    Text(
                                      widget.settings.userName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                    Text(
                                      'Welcome back',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.66,
                                        ),
                                        fontSize: 13,
                                        letterSpacing: 0.2,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    if (!_needsPassword)
                                      _continuePanel()
                                    else
                                      AnimatedSize(
                                        duration: const Duration(
                                          milliseconds: 340,
                                        ),
                                        curve: Curves.easeOutCubic,
                                        alignment: Alignment.topCenter,
                                        child: AnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 220,
                                          ),
                                          child: _revealed
                                              ? _passwordPanel()
                                              : _revealHint(),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(height: shortScreen ? 26 : 48),
                            Text(
                              'Misty OS  ·  Lightweight. Cloud-Native. Powerful.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 12,
                                letterSpacing: 0.25,
                                decoration: TextDecoration.none,
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
          ),
        ],
      ),
    );
  }
}
