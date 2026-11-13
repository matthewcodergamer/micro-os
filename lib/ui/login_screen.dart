import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../services/settings_store.dart';

/// Full-screen macOS-inspired lock / login surface.
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
  String? _error;
  bool _obscure = true;
  Timer? _clockTimer;

  late final AnimationController _entrance;
  late final AnimationController _shake;
  late final Animation<double> _fade;
  late final Animation<Offset> _rise;
  late final Animation<double> _avatarScale;
  late final Animation<double> _shakeX;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _rise = Tween<Offset>(
      begin: const Offset(0, 0.055),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entrance,
      curve: Curves.easeOutCubic,
    ));
    _avatarScale = Tween<double>(
      begin: 0.86,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.12, 1, curve: Curves.easeOutBack),
    ));
    _shakeX = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -11), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -11, end: 9), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 9, end: -6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6, end: 4), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 4, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shake, curve: Curves.easeOut));

    _entrance.forward();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _password.dispose();
    _entrance.dispose();
    _shake.dispose();
    super.dispose();
  }

  void _tryUnlock() {
    final stored = widget.settings.loginPassword;
    if (stored == null || stored.isEmpty) {
      widget.onUnlock();
      return;
    }
    if (_password.text == stored) {
      setState(() => _error = null);
      _password.clear();
      widget.onUnlock();
      return;
    }
    setState(() => _error = 'Incorrect password. Try again.');
    _shake.forward(from: 0);
    HapticFeedback.heavyImpact();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final name = widget.settings.userName;
    final screen = MediaQuery.sizeOf(context);
    final shortScreen = screen.height < 620;
    final clockSize = math.min(
      84.0,
      math.min(screen.width * 0.22, screen.height * 0.15),
    );
    final avatarSize = shortScreen ? 68.0 : 88.0;
    final hasPassword = widget.settings.hasPassword;

    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0x77000000)),
          FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _rise,
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: shortScreen ? 16 : 28,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            lockTime(now),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: clockSize,
                              fontWeight: FontWeight.w200,
                              letterSpacing: -1.8,
                              height: 1,
                              shadows: const [
                                Shadow(
                                  color: Color(0x55000000),
                                  blurRadius: 22,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            lockDate(now),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.82),
                              fontSize: shortScreen ? 16 : 19,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0.25,
                            ),
                          ),
                          SizedBox(height: shortScreen ? 28 : 54),
                          ScaleTransition(
                            scale: _avatarScale,
                            child: Container(
                              width: avatarSize,
                              height: avatarSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF0A84FF),
                                    Color(0xFF5E5CE6),
                                  ],
                                ),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.38),
                                  width: 1.3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.35),
                                    blurRadius: 24,
                                    offset: const Offset(0, 9),
                                  ),
                                  BoxShadow(
                                    color: MicroColors.accent.withValues(alpha: 0.25),
                                    blurRadius: 30,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.person_rounded,
                                color: Colors.white,
                                size: avatarSize * 0.55,
                              ),
                            ),
                          ),
                          const SizedBox(height: 15),
                          Text(
                            name,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.15,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            'Welcome back',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.62),
                              fontSize: 13,
                            ),
                          ),
                          SizedBox(height: shortScreen ? 18 : 26),
                          if (hasPassword)
                            AnimatedBuilder(
                              animation: _shake,
                              builder: (context, child) => Transform.translate(
                                offset: Offset(_shakeX.value, 0),
                                child: child,
                              ),
                              child: _passwordForm(),
                            )
                          else
                            FilledButton.icon(
                              onPressed: widget.onUnlock,
                              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                              label: const Text('Continue to Desktop'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(190, 46),
                              ),
                            ),
                          SizedBox(height: shortScreen ? 30 : 58),
                          Text(
                            'MicroOS  •  Golden Gate',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.48),
                              fontSize: 12,
                              letterSpacing: 0.45,
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
        ],
      ),
    );
  }

  Widget _passwordForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 50,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.28),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 18,
                offset: Offset(0, 7),
              ),
            ],
          ),
          padding: const EdgeInsets.only(left: 19, right: 7),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _password,
                  obscureText: _obscure,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  onSubmitted: (_) => _tryUnlock(),
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  cursorColor: Colors.white,
                  decoration: const InputDecoration(
                    hintText: 'Enter Password',
                    hintStyle: TextStyle(color: Colors.white70),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
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
                  size: 19,
                ),
              ),
              IconButton(
                tooltip: 'Unlock MicroOS',
                onPressed: _tryUnlock,
                icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                color: Colors.white,
                style: IconButton.styleFrom(
                  backgroundColor: MicroColors.accent,
                  minimumSize: const Size(38, 38),
                ),
              ),
            ],
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _error == null
              ? const SizedBox(height: 24, key: ValueKey('empty-error'))
              : Padding(
                  key: const ValueKey('login-error'),
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFF8B86),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: _tryUnlock,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white.withValues(alpha: 0.86),
          ),
          child: const Text('Unlock'),
        ),
      ],
    );
  }
}
