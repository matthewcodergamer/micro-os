import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../core/theme.dart';
import '../services/system_stats.dart';
import '../state/desktop_state.dart';

/// macOS menu bar: active app on the left, live system readouts on the right.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key, required this.desktop, required this.stats});

  final DesktopState desktop;
  final SystemStats stats;

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
                  const Icon(CupertinoIcons.apple_logo, size: 15, color: MicroColors.text),
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
                  _Stat(
                    icon: Icons.memory,
                    label: stats.ramTotalMb == 0
                        ? '--'
                        : '${stats.ramUsedMb}/${stats.ramTotalMb} MB',
                  ),
                  if (stats.swapTotalMb > 0)
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
  const _Stat({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? MicroColors.text;
    return Padding(
      padding: const EdgeInsets.only(left: 14),
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
    );
  }
}
