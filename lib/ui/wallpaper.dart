import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The "Golden Gate" wallpaper – a pure-code painted sunset over the bay.
/// No asset required.
class Wallpaper extends StatelessWidget {
  const Wallpaper({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      painter: _GoldenGatePainter(),
      size: Size.infinite,
    );
  }
}

class _GoldenGatePainter extends CustomPainter {
  const _GoldenGatePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Deep twilight sky gradient.
    final sky = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF0B1026),
          Color(0xFF1A2240),
          Color(0xFF3A2A4A),
          Color(0xFF8B4A3A),
          Color(0xFFD07040),
          Color(0xFFE8A060),
        ],
        stops: [0.0, 0.25, 0.45, 0.65, 0.82, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, sky);

    // Soft sun glow near the horizon.
    final sunCenter = Offset(size.width * 0.72, size.height * 0.62);
    final sunGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFE8A0).withValues(alpha: 0.55),
          const Color(0xFFFFB060).withValues(alpha: 0.25),
          const Color(0xFFFF8040).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: sunCenter, radius: size.width * 0.35));
    canvas.drawCircle(sunCenter, size.width * 0.35, sunGlow);

    // Sun disc.
    final sun = Paint()..color = const Color(0xFFFFF0C0);
    canvas.drawCircle(sunCenter, size.width * 0.045, sun);

    // Water / bay reflection band.
    final waterTop = size.height * 0.68;
    final water = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF1A2840).withValues(alpha: 0.7),
          const Color(0xFF0C1528),
        ],
      ).createShader(Rect.fromLTWH(0, waterTop, size.width, size.height - waterTop));
    canvas.drawRect(Rect.fromLTWH(0, waterTop, size.width, size.height - waterTop), water);

    // Subtle horizontal ripples.
    final ripple = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1.2;
    for (var i = 0; i < 8; i++) {
      final y = waterTop + 18 + i * 22.0;
      final path = Path();
      path.moveTo(0, y);
      for (var x = 0.0; x < size.width; x += 24) {
        path.quadraticBezierTo(
          x + 12,
          y + math.sin(x * 0.04 + i) * 3,
          x + 24,
          y,
        );
      }
      canvas.drawPath(path, ripple);
    }

    // Soft vignette.
    final vignette = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.1, -0.2),
        radius: 1.15,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.35),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, vignette);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
