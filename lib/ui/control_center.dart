import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/macos_design.dart';
import '../core/theme.dart';
import '../services/linux_runtime.dart';
import '../services/system_stats.dart';

/// Control Center panel shown from the menu bar.
class ControlCenterOverlay extends StatelessWidget {
  const ControlCenterOverlay({
    super.key,
    required this.topPadding,
    required this.onClose,
    required this.runtime,
    required this.stats,
  });

  final double topPadding;
  final VoidCallback onClose;
  final LinuxRuntime runtime;
  final SystemStats stats;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([runtime, stats]),
      builder: (context, _) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClose,
              child: const ColoredBox(color: Color(0x33000000)),
            ),
          ),
          Positioned(top: topPadding + 6, right: 12, child: _panel(context)),
        ],
      ),
    );
  }

  Widget _panel(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: Sequoia.panelShadow(),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            width: math.min(336.0, MediaQuery.sizeOf(context).width - 24),
            padding: const EdgeInsets.all(14),
            decoration: Sequoia.glass(radius: 22, tint: 0.72, borderAlpha: 0.2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(),
                const SizedBox(height: 12),
                _tileRow([
                  _Tile(
                    icon: Icons.wifi_rounded,
                    label: 'Wi-Fi',
                    value: stats.connection,
                    active: true,
                  ),
                  _Tile(
                    icon: Icons.battery_full_rounded,
                    label: 'Battery',
                    value: '${stats.batteryLevel}%',
                    active: true,
                  ),
                ]),
                const SizedBox(height: 8),
                _tileRow([
                  _Tile(
                    icon: Icons.memory_rounded,
                    label: 'RAM',
                    value: '${stats.ramUsedMb} MB',
                    active: true,
                  ),
                  _Tile(
                    icon: Icons.storage_rounded,
                    label: 'ZRAM',
                    value: '${stats.swapUsedMb} MB',
                    active: runtime.isReady,
                  ),
                ]),
                const SizedBox(height: 8),
                _linuxTile(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return const Row(
      children: [
        Text(
          'Control Center',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }

  Widget _tileRow(List<Widget> children) {
    return Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: children[i]),
        ],
      ],
    );
  }

  Widget _linuxTile() {
    final ready = runtime.isReady;
    final busy = runtime.isBusy;
    final label = ready
        ? 'Linux Ready'
        : busy
        ? 'Installing…'
        : 'Linux Offline';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            ready ? Icons.check_circle_rounded : Icons.pending_rounded,
            color: ready ? MicroColors.green : MicroColors.amber,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.value,
    required this.active,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: active ? 0.13 : 0.06),
        borderRadius: BorderRadius.circular(Sequoia.cardRadius + 4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: active ? Colors.white : Colors.white54, size: 22),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: active ? Colors.white70 : Colors.white38,
              fontSize: 11,
              decoration: TextDecoration.none,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
