import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Big Sur wallpaper from the pinned ThanasOS asset set.
class Wallpaper extends StatelessWidget {
  const Wallpaper({super.key});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final dpr = media.devicePixelRatio;
    // Decode near the physical display resolution, capped for mobile RAM.
    final decodeWidth = (media.size.width * dpr).round().clamp(1, 1440).toInt();
    final decodeHeight = (media.size.height * dpr).round().clamp(1, 3200).toInt();
    return Image.asset(
      'assets/wallpapers/wallpaper-bigsur.jpg',
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      cacheWidth: decodeWidth,
      cacheHeight: decodeHeight,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      // Keep a deterministic local fallback for development environments
      // where the asset-fetch script has not been run yet.
      errorBuilder: (context, error, stackTrace) => const CustomPaint(
        painter: _GoldenGatePainter(),
        size: Size.infinite,
      ),
    );
  }
}

class _GoldenGatePainter extends CustomPainter {
  const _GoldenGatePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
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
    canvas.drawCircle(sunCenter, size.width * 0.045, Paint()..color = const Color(0xFFFFF0C0));

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

    final ripple = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1.2;
    for (var i = 0; i < 8; i++) {
      final y = waterTop + 18 + i * 22.0;
      final path = Path()..moveTo(0, y);
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
