import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/macos_design.dart';
import '../services/linux_runtime.dart';
import '../services/system_stats.dart';

/// macOS Sequoia-inspired Control Center.
///
/// The panel intentionally avoids a live [BackdropFilter]: on Android the
/// native X11 desktop is an AndroidView, and blurring a region that contains a
/// platform view can turn into a flat grey rectangle on several GPUs. Layered
/// gradients, hairline borders and a soft shadow give the same depth while
/// staying stable over both the wallpaper and the native desktop.
class ControlCenterOverlay extends StatelessWidget {
  const ControlCenterOverlay({
    super.key,
    required this.topPadding,
    required this.onClose,
    required this.runtime,
    required this.stats,
    this.onOpenDesktop,
    this.onLock,
  });

  final double topPadding;
  final VoidCallback onClose;
  final LinuxRuntime runtime;
  final SystemStats stats;
  final VoidCallback? onOpenDesktop;
  final VoidCallback? onLock;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final panelWidth = math.min(360.0, media.size.width - 20);
    final top = topPadding + 8;
    final maxHeight = math.max(
      260.0,
      media.size.height - top - media.padding.bottom - 12,
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: const ColoredBox(color: Color(0x26000000)),
          ),
        ),
        Positioned(
          top: top,
          right: 10,
          width: panelWidth,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Transform.scale(
              scale: 0.94 + 0.06 * value,
              alignment: Alignment.topRight,
              child: Opacity(
                opacity: value.clamp(0.0, 1.0).toDouble(),
                child: child,
              ),
            ),
            child: _panel(context, panelWidth, maxHeight),
          ),
        ),
      ],
    );
  }

  Widget _panel(BuildContext context, double width, double maxHeight) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 40,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Container(
          width: width,
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xF52A2A30), Color(0xF417171B)],
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.16),
              width: 0.8,
            ),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(),
                const SizedBox(height: 13),
                Row(
                  children: [
                    Expanded(
                      child: _QuickTile(
                        icon: Icons.wifi_rounded,
                        accent: Sequoia.blue,
                        label: 'Wi-Fi',
                        value: _connectionLabel(stats.connection),
                        active: stats.connection != 'offline',
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: _QuickTile(
                        icon: stats.charging
                            ? Icons.battery_charging_full_rounded
                            : Icons.battery_full_rounded,
                        accent: Sequoia.green,
                        label: 'Battery',
                        value: '${stats.batteryLevel}%',
                        active: stats.batteryLevel > 0,
                        footer: stats.charging ? 'Charging' : 'On battery',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                const _SectionLabel('System'),
                const SizedBox(height: 7),
                _memoryCard(),
                const SizedBox(height: 15),
                const _SectionLabel('Linux'),
                const SizedBox(height: 7),
                _linuxCard(),
                if (onOpenDesktop != null || onLock != null) ...[
                  const SizedBox(height: 13),
                  Row(
                    children: [
                      if (onOpenDesktop != null)
                        Expanded(
                          child: _PrimaryAction(
                            icon: Icons.desktop_windows_rounded,
                            label: 'Open Desktop',
                            onTap: onOpenDesktop!,
                          ),
                        ),
                      if (onOpenDesktop != null && onLock != null)
                        const SizedBox(width: 9),
                      if (onLock != null)
                        _SquareAction(
                          icon: Icons.lock_rounded,
                          tooltip: 'Lock Screen',
                          onTap: onLock!,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Control Center',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  decoration: TextDecoration.none,
                ),
              ),
              SizedBox(height: 1),
              Text(
                'Misty OS',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
        _RoundButton(
          icon: Icons.close_rounded,
          tooltip: 'Close Control Center',
          onTap: onClose,
        ),
      ],
    );
  }

  Widget _memoryCard() {
    final ramTotal = stats.ramTotalMb;
    final swapTotal = stats.swapTotalMb;
    final ramFraction = ramTotal > 0
        ? (stats.ramUsedMb / ramTotal).clamp(0.0, 1.0).toDouble()
        : null;
    final swapFraction = swapTotal > 0
        ? (stats.swapUsedMb / swapTotal).clamp(0.0, 1.0).toDouble()
        : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.075),
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          _MeterRow(
            icon: Icons.memory_rounded,
            label: 'Memory',
            value: ramTotal > 0
                ? '${_megabytes(stats.ramUsedMb)} / ${_megabytes(ramTotal)}'
                : _megabytes(stats.ramUsedMb),
            fraction: ramFraction ?? 0,
            color: Sequoia.blue,
          ),
          const SizedBox(height: 11),
          _MeterRow(
            icon: Icons.storage_rounded,
            label: 'ZRAM',
            value: swapTotal > 0
                ? '${_megabytes(stats.swapUsedMb)} / ${_megabytes(swapTotal)}'
                : 'Unavailable',
            fraction: swapFraction ?? 0,
            color: Sequoia.purple,
          ),
        ],
      ),
    );
  }

  Widget _linuxCard() {
    final ready = runtime.isReady;
    final busy = runtime.isBusy;
    final accent = ready
        ? Sequoia.green
        : busy
        ? Sequoia.orange
        : Sequoia.graphite;
    final title = busy ? 'Preparing Linux' : 'Linux environment';
    final subtitle = ready
        ? 'Ubuntu ARM64 · native X11'
        : busy
        ? 'Installing apps and desktop services…'
        : 'Finish setup to open the Linux desktop';
    final badge = ready
        ? 'Ready'
        : busy
        ? 'Setting up'
        : 'Offline';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: ready ? 0.16 : 0.10),
            Colors.white.withValues(alpha: 0.045),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accent.withValues(alpha: ready ? 0.26 : 0.16),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.terminal_rounded,
              color: accent,
              size: 21,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                    height: 1.25,
                    decoration: TextDecoration.none,
                  ),
                ),
                if (busy) ...[
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      minHeight: 4,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      color: accent,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _StatusPill(label: badge, color: accent, active: ready || busy),
        ],
      ),
    );
  }

  String _connectionLabel(String connection) {
    return switch (connection) {
      'wifi' => 'Wi-Fi',
      'mobile' => 'Mobile',
      'ethernet' => 'Ethernet',
      'unknown' => 'Unknown',
      _ => 'Offline',
    };
  }

  static String _megabytes(int mb) {
    if (mb <= 0) return '0 MB';
    if (mb >= 1024) {
      final gb = mb / 1024;
      return gb >= 10 ? '${gb.round()} GB' : '${gb.toStringAsFixed(1)} GB';
    }
    return '$mb MB';
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
    required this.active,
    this.footer,
  });

  final IconData icon;
  final Color accent;
  final String label;
  final String value;
  final bool active;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.14),
            Colors.white.withValues(alpha: 0.065),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.20),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              const Spacer(),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: active
                      ? Sequoia.green
                      : Colors.white.withValues(alpha: 0.28),
                  shape: BoxShape.circle,
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: Sequoia.green.withValues(alpha: 0.45),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.none,
            ),
          ),
          if (footer != null)
            Text(
              footer!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 10,
                decoration: TextDecoration.none,
              ),
            ),
        ],
      ),
    );
  }
}

class _MeterRow extends StatelessWidget {
  const _MeterRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.fraction,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final double? fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: Colors.white60),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 11,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 5,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            color: color,
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: Colors.white38,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.9,
        decoration: TextDecoration.none,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    required this.active,
  });

  final String label;
  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: active ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(alpha: active ? 0.32 : 0.16),
          width: 0.7,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? color : Colors.white54,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2D95FF), Color(0xFF0A6BDB)],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: Colors.white),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SquareAction extends StatelessWidget {
  const _SquareAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            width: 46,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 0.8,
              ),
            ),
            child: Icon(icon, size: 18, color: Colors.white70),
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Ink(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.10),
                width: 0.7,
              ),
            ),
            child: Icon(icon, size: 15, color: Colors.white70),
          ),
        ),
      ),
    );
  }
}
