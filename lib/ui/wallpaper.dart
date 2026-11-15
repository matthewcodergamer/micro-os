import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/wallpapers.dart';

/// Full-bleed desktop wallpaper.
///
/// The image is always drawn with [BoxFit.cover] so its aspect ratio is
/// preserved in both orientations. Decoding is capped at the physical display
/// width to keep memory sane on 4 GB phones.
class Wallpaper extends StatelessWidget {
  const Wallpaper({super.key, this.asset = 'assets/wallpapers/option3.png'});

  final String asset;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final dpr = media.devicePixelRatio;
    // Decode by the longest display edge only. Supplying both cacheWidth and
    // cacheHeight can force a non-matching source aspect ratio during decode.
    // BoxFit.cover then crops the original image naturally in either
    // orientation.
    final decodeWidth =
        (math.max(media.size.width, media.size.height) * dpr)
            .round()
            .clamp(1, 1440)
            .toInt();
    return Image.asset(
      asset,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      cacheWidth: decodeWidth,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      // Keep a deterministic local fallback for development environments
      // where the asset-fetch script has not been run yet.
      errorBuilder: (context, error, stackTrace) => const CustomPaint(
        painter: _MistySkyPainter(),
        size: Size.infinite,
      ),
    );
  }
}

/// A calm Misty sky, used only when the wallpaper asset cannot be decoded.
class _MistySkyPainter extends CustomPainter {
  const _MistySkyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final sky = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFB6CFEE),
          Color(0xFF8FB4E3),
          Color(0xFF7BA3D6),
          Color(0xFF9FB4D9),
          Color(0xFFE3C4C6),
        ],
        stops: [0.0, 0.28, 0.58, 0.82, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, sky);

    final haze = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.55, 0.92),
        radius: 0.9,
        colors: [
          const Color(0xFFFFD9D9).withValues(alpha: 0.55),
          const Color(0xFFFFD9D9).withValues(alpha: 0.0),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, haze);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Small preview tile used by the wallpaper picker.
class WallpaperThumbnail extends StatelessWidget {
  const WallpaperThumbnail({
    super.key,
    required this.wallpaper,
    required this.selected,
    required this.onTap,
  });

  final MistyWallpaper wallpaper;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? Colors.white : Colors.white24,
                  width: selected ? 2.5 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  wallpaper.asset,
                  fit: BoxFit.cover,
                  cacheWidth: 320,
                  filterQuality: FilterQuality.low,
                  errorBuilder: (context, error, stackTrace) => const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF8FB4E3), Color(0xFFE3C4C6)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            wallpaper.name,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}
