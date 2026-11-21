import 'package:flutter/material.dart';

import '../core/experience_mode.dart';

/// First-run choice between pointer-first and touch-first desktop interaction.
/// Both choices use the same Ubuntu guest and installed applications.
class ExperienceModePicker extends StatelessWidget {
  const ExperienceModePicker({super.key, required this.onSelected});

  final ValueChanged<ExperienceMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 620;
    return Material(
      color: const Color(0xF20B111B),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.desktop_windows_rounded, color: Color(0xFF9FC7FF), size: 38),
                  const SizedBox(height: 14),
                  const Text('Choose your workspace', textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.6)),
                  const SizedBox(height: 8),
                  const Text('Misty OS runs the same full Linux workstation in either mode. You can change this later in Settings.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFFB6C2D2), fontSize: 13, height: 1.5)),
                  const SizedBox(height: 24),
                  Flex(
                    direction: wide ? Axis.horizontal : Axis.vertical,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ExpandedIfWide(wide: wide, child: _ModeCard(
                        icon: Icons.mouse_rounded,
                        title: 'Desktop Mode',
                        subtitle: 'Pointer-first · keyboard and mouse',
                        description: 'Experience a traditional desktop with a visible cursor, precise selection, dragging, context menus and keyboard shortcuts. Great with a Bluetooth mouse or trackpad.',
                        onTap: () => onSelected(ExperienceMode.desktop),
                      )),
                      SizedBox(width: wide ? 14 : 0, height: wide ? 0 : 14),
                      ExpandedIfWide(wide: wide, child: _ModeCard(
                        icon: Icons.touch_app_rounded,
                        title: 'Mobile Desktop',
                        subtitle: 'Touch-first · phone optimized',
                        description: 'Keep desktop windows and Linux apps, but use direct touch, larger controls, adaptive spacing and the Android keyboard when entering text.',
                        onTap: () => onSelected(ExperienceMode.mobileDesktop),
                      )),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text('One Linux installation. Two ways to use it.',
                    style: TextStyle(color: Color(0xFF8493A7), fontSize: 11)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ExpandedIfWide extends StatelessWidget {
  const ExpandedIfWide({super.key, required this.wide, required this.child});
  final bool wide;
  final Widget child;

  @override
  Widget build(BuildContext context) => wide ? Expanded(child: child) : child;
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.icon, required this.title, required this.subtitle,
    required this.description, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF182333),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          constraints: const BoxConstraints(minHeight: 220),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF34465D)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: const Color(0xFF9FC7FF), size: 30),
            const SizedBox(height: 18),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            Text(subtitle, style: const TextStyle(color: Color(0xFF9FC7FF), fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Text(description, style: const TextStyle(color: Color(0xFFB6C2D2), fontSize: 12, height: 1.5)),
            const SizedBox(height: 12),
            const Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text('Choose this mode', style: TextStyle(color: Color(0xFF9FC7FF), fontSize: 12, fontWeight: FontWeight.w600)),
              SizedBox(width: 6), Icon(Icons.arrow_forward_rounded, color: Color(0xFF9FC7FF), size: 16),
            ]),
          ]),
        ),
      ),
    );
  }
}
