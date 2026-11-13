import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

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
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: const ColoredBox(color: Color(0x33000000)),
          ),
        ),
        Positioned(
          top: topPadding + 6,
          right: 12,
          child: _panel(context),
        ),
      ],
    );
  }

  Widget _panel(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 10)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            width: math.min(320.0, MediaQuery.sizeOf(context).width - 24),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xCC1C1C1E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
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
                    label: 'Memory',
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
              style: const TextStyle(color: Colors.white, fontSize: 13),
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
        color: Colors.white.withValues(alpha: active ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(12),
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
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: active ? Colors.white70 : Colors.white38,
              fontSize: 11,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
