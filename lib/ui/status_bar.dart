import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/system_stats.dart';
import '../state/desktop_state.dart';

/// macOS menu bar: active app on the left, live system readouts on the right.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key, required this.desktop, required this.stats, required this.compact, required this.onSpotlight, required this.onControlCenter});

  final DesktopState desktop;
  final SystemStats stats;
  final bool compact;
  final VoidCallback onSpotlight;
  final VoidCallback onControlCenter;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          height: kStatusBarHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(
            color: Color(0xB30B0D13),
            border: Border(bottom: BorderSide(color: Color(0x1AFFFFFF))),
          ),
          child: AnimatedBuilder(
            animation: stats,
            builder: (context, _) {
              final focused = desktop.focused;
              return Row(
                children: [
                  const Icon(Icons.laptop_mac, size: 15, color: MicroColors.text),
                  const SizedBox(width: 8),
                  Text(
                    focused?.title ?? 'MicroOS',
                    style: const TextStyle(
                      color: MicroColors.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (!compact)
                    _Stat(
                      icon: Icons.memory,
                      label: stats.ramTotalMb == 0
                          ? '--'
                          : '${stats.ramUsedMb}/${stats.ramTotalMb} MB',
                    ),
                  if (!compact && stats.swapTotalMb > 0)
                    _Stat(
                      icon: Icons.compress,
                      label: 'zram ${stats.swapUsedMb} MB',
                      color: MicroColors.amber,
                    ),
                  _Stat(
                    icon: stats.connection == 'wifi'
                        ? Icons.wifi
                        : stats.connection == 'mobile'
                            ? Icons.signal_cellular_alt
                            : Icons.wifi_off,
                    label: stats.connection,
                  ),
                  _Stat(
                    icon: stats.charging ? Icons.battery_charging_full : Icons.battery_5_bar,
                    label: '${stats.batteryLevel}%',
                    color: stats.batteryLevel <= 15 ? MicroColors.red : null,
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: MicroColors.panelSolid,
                        title: const Text('Battery'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${stats.batteryLevel}% remaining',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            Text(stats.charging ? 'Charging or fully charged' : 'Discharging'),
                            const SizedBox(height: 10),
                            const Text('Android does not expose battery health or cycle count through the current app interface. This panel shows the live charge level and charging state.',
                              style: TextStyle(color: MicroColors.subtle, fontSize: 12)),
                          ],
                        ),
                        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Spotlight',
                    onPressed: onSpotlight,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                    icon: const Icon(Icons.search_rounded, color: MicroColors.text, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Control Center',
                    onPressed: onControlCenter,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                    icon: const Icon(Icons.tune_rounded, color: MicroColors.text, size: 17),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _clock(stats.now),
                    style: const TextStyle(
                      color: MicroColors.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String _clock(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, this.color, this.onTap});

  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? MicroColors.text;
    return Padding(
      padding: const EdgeInsets.only(left: 14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
          Icon(icon, size: 13, color: tint),
          const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: tint,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}
