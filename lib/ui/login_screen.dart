import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../services/settings_store.dart';

/// Full-screen lock / login surface shown when DesktopState.locked is true.
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
  late final Animation<Offset> _slide;

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

    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _entrance.dispose();
    _shake.dispose();
    _password.dispose();
    super.dispose();
  }

  void _tryUnlock() {
    if (widget.settings.loginPasswordStorageUnavailable) {
      setState(() => _error =
          'Secure password storage is unavailable. Restart MicroOS and try again.');
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
    HapticFeedback.heavyImpact();
    _shake.forward(from: 0);
  }

  Widget _accountPanel(double avatarSize) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: avatarSize,
          height: avatarSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0A84FF), Color(0xFF5E5CE6)],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 22,
                offset: const Offset(0, 9),
              ),
            ],
          ),
          child: Icon(
            Icons.person_rounded,
            color: Colors.white,
            size: avatarSize * 0.55,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          widget.settings.userName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 22),
        if (widget.settings.hasPassword)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Column(
              children: [
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.24),
                    ),
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
                          obscureText: _obscure,
                          autofocus:
                              !widget.settings.loginPasswordStorageUnavailable,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.done,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                          cursorColor: Colors.white,
                          decoration: const InputDecoration(
                            hintText: 'Enter Password',
                            hintStyle: TextStyle(color: Colors.white60),
                            border: InputBorder.none,
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
                          ),
                        ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _tryUnlock,
                  child: const Text('Unlock MicroOS'),
                ),
              ],
            ),
          )
        else ...[
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFFFB4AB), fontSize: 12),
              ),
            ),
          FilledButton(
            onPressed: _tryUnlock,
            child: const Text('Continue'),
          ),
        ],
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

    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0x70000000)),
          FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: SafeArea(
                child: Column(
                  children: [
                    const Spacer(flex: 1),
                    Text(
                      lockTime(now),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: clockSize,
                        fontWeight: FontWeight.w200,
                        letterSpacing: -1.5,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      lockDate(now),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 20,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const Spacer(flex: 2),
                    AnimatedBuilder(
                      animation: _shake,
                      child: _accountPanel(avatarSize),
                      builder: (context, child) {
                        final progress = _shake.value;
                        final offset =
                            math.sin(progress * math.pi * 10) *
                            (1 - progress) *
                            7;
                        return Transform.translate(
                          offset: Offset(offset, 0),
                          child: child,
                        );
                      },
                    ),
                    const Spacer(flex: 2),
                    Text(
                      'MicroOS  ·  Golden Gate',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12,
                        letterSpacing: 0.25,
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
