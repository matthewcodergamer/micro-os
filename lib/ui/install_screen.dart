import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../core/theme.dart';
import '../services/linux_runtime.dart';

/// First-run unpacking surface, styled like a macOS install window.
///
/// The whole screen is the approved Misty sky background. The progress bar is
/// deliberately thin and rounded, matching the macOS setup assistant, instead
/// of the bordered/gradient bar this screen used before.
class InstallScreen extends StatefulWidget {
  const InstallScreen({super.key});

  @override
  State<InstallScreen> createState() => _InstallScreenState();
}

class _InstallScreenState extends State<InstallScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runtime = AppScope.of(context).runtime;

    return ListenableBuilder(
      listenable: runtime,
      builder: (context, _) {
        final failed = runtime.status == RuntimeStatus.failed;
        final busy = runtime.isBusy;
        final progress = runtime.progress.clamp(0.0, 1.0);
        final percent = (progress * 100).round();
        final stage = failed
            ? (runtime.error ?? 'The workstation could not be unpacked.')
            : busy
                ? runtime.stage
                : 'Ready when you are.';

        return Material(
          color: const Color(0xFF0E1622),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Approved "option 3" sky, edge to edge, never stretched.
              Image.asset(
                'assets/wallpapers/option3.png',
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) =>
                    const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF8FB4E3), Color(0xFF7BA3D6), Color(0xFFE8C7C7)],
                      stops: [0.0, 0.62, 1.0],
                    ),
                  ),
                ),
              ),
              // Keeps white text legible over the bright sky.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x1A000000), Color(0x55000000)],
                    stops: [0.35, 1.0],
                  ),
                ),
              ),
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 24,
                    ),
                    child: FadeTransition(
                      opacity: CurvedAnimation(
                        parent: _entrance,
                        curve: Curves.easeOut,
                      ),
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.04),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(
                          parent: _entrance,
                          curve: Curves.easeOutCubic,
                        )),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Bare mark: no circular badge, no gradient plate.
                              Icon(
                                Icons.laptop_mac_rounded,
                                size: 62,
                                color: Colors.white.withValues(alpha: 0.96),
                                shadows: const [
                                  Shadow(
                                    color: Color(0x66000000),
                                    blurRadius: 18,
                                    offset: Offset(0, 6),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                'Misty OS',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  color: Colors.white,
                                  fontSize: 27,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.6,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                failed
                                    ? 'Unpacking stopped'
                                    : busy
                                        ? 'Preparing your Linux workstation'
                                        : 'Misty OS is ready',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  color: Colors.white.withValues(alpha: 0.78),
                                  fontSize: 13,
                                  height: 1.45,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                              if (busy || failed) ...[
                                const SizedBox(height: 30),
                                _MacProgressBar(
                                  value: progress,
                                  failed: failed,
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: AnimatedSwitcher(
                                        duration:
                                            const Duration(milliseconds: 220),
                                        child: Text(
                                          stage,
                                          key: ValueKey<String>(stage),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.white
                                                .withValues(alpha: 0.62),
                                            fontSize: 11,
                                            decoration: TextDecoration.none,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      '$percent%',
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.92),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (failed) ...[
                                const SizedBox(height: 26),
                                _GlassButton(
                                  label: 'Retry',
                                  onPressed: runtime.reinstall,
                                ),
                              ] else if (!busy) ...[
                                const SizedBox(height: 26),
                                _GlassButton(
                                  label: 'Install Misty OS',
                                  onPressed: runtime.install,
                                ),
                              ],
                              if (failed && runtime.logLines.isNotEmpty) ...[
                                const SizedBox(height: 18),
                                SizedBox(
                                  height: 96,
                                  child: ListView.builder(
                                    itemCount: runtime.logLines.length,
                                    itemBuilder: (_, index) => Text(
                                      runtime.logLines[index],
                                      style: const TextStyle(
                                        color: Color(0xCCFFFFFF),
                                        fontSize: 10,
                                        fontFamily: 'JetBrains Mono',
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
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
      },
    );
  }
}

/// Thin, rounded, unlabelled track/fill pair — the macOS setup progress bar.
class _MacProgressBar extends StatelessWidget {
  const _MacProgressBar({required this.value, required this.failed});

  final double value;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 4,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Colors.white.withValues(alpha: 0.28)),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: value),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              builder: (context, animated, _) => Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: animated.clamp(0.0, 1.0),
                  child: ColoredBox(
                    color: failed
                        ? MicroColors.red
                        : Colors.white.withValues(alpha: 0.96),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.black87,
        backgroundColor: Colors.white.withValues(alpha: 0.88),
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.none,
        ),
      ),
      child: Text(label),
    );
  }
}
