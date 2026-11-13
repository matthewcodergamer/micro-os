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

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _password = TextEditingController();
  String? _error;
  bool _obscure = true;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _password.dispose();
    super.dispose();
  }

  void _tryUnlock() {
    final stored = widget.settings.loginPassword;
    if (stored == null || stored.isEmpty) {
      widget.onUnlock();
      return;
    }
    if (_password.text == stored) {
      widget.onUnlock();
      return;
    }
    setState(() => _error = 'Incorrect password');
    HapticFeedback.heavyImpact();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final name = widget.settings.userName;
    final screen = MediaQuery.sizeOf(context);
    final shortScreen = screen.height < 620;
    final clockSize = math.min(84.0, math.min(screen.width * 0.22, screen.height * 0.15));
    final avatarSize = shortScreen ? 68.0 : 88.0;

    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Dim overlay on top of the wallpaper.
          const ColoredBox(color: Color(0x66000000)),
          SafeArea(
            child: Column(
              children: [
                Spacer(flex: shortScreen ? 1 : 2),
                Text(
                  lockTime(now),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: clockSize,
                    fontWeight: FontWeight.w200,
                    letterSpacing: -1.5,
                    height: 1.0,
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
                Spacer(flex: shortScreen ? 1 : 3),
                // Avatar
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
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(Icons.person_rounded, color: Colors.white, size: avatarSize * 0.55),
                ),
                const SizedBox(height: 14),
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 22),
                // Password pill
                if (widget.settings.hasPassword)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Column(
                      children: [
                        Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.22),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _password,
                                  obscureText: _obscure,
                                  autofocus: true,
                                  style: const TextStyle(color: Colors.white, fontSize: 15),
                                  cursorColor: Colors.white,
                                  decoration: const InputDecoration(
                                    hintText: 'Enter Password',
                                    hintStyle: TextStyle(color: Colors.white54),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  onSubmitted: (_) => _tryUnlock(),
                                ),
                              ),
                              GestureDetector(
                                onTap: () => setState(() => _obscure = !_obscure),
                                child: Icon(
                                  _obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                                  color: Colors.white54,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _error!,
                            style: const TextStyle(color: MicroColors.red, fontSize: 13),
                          ),
                        ],
                        const SizedBox(height: 14),
                        FilledButton(
                          onPressed: _tryUnlock,
                          child: const Text('Unlock'),
                        ),
                      ],
                    ),
                  )
                else
                  FilledButton(
                    onPressed: widget.onUnlock,
                    child: const Text('Continue'),
                  ),
                Spacer(flex: shortScreen ? 1 : 2),
                Text(
                  'MicroOS · Golden Gate',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
