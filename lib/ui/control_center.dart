import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/macos_design.dart';
import '../core/theme.dart';
import '../services/linux_runtime.dart';
import '../services/system_stats.dart';
import '../services/settings_store.dart';
import '../services/system_controls.dart';

/// Control Center panel shown from the menu bar.
class ControlCenterOverlay extends StatelessWidget {
  const ControlCenterOverlay({
    super.key,
    required this.topPadding,
    required this.onClose,
    required this.runtime,
    required this.stats,
    required this.settings,
  });

  final double topPadding;
  final VoidCallback onClose;
  final LinuxRuntime runtime;
  final SystemStats stats;
  final SettingsStore settings;

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
                _SystemControlSliders(settings: settings),
                const SizedBox(height: 10),
                _tileRow([
                  _Tile(
                    icon: Icons.wifi_rounded,
                    label: 'Wi-Fi',
                    value: stats.connection,
                    active: true,
                    onTap: () { SystemControls.openNetworkSettings(); },
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

class _SystemControlSliders extends StatefulWidget {
  const _SystemControlSliders({required this.settings});
  final SettingsStore settings;

  @override
  State<_SystemControlSliders> createState() => _SystemControlSlidersState();
}

class _SystemControlSlidersState extends State<_SystemControlSliders> {
  double _brightness = 0.75;
  double _volume = 0.5;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _brightness = widget.settings.screenBrightness;
    _load();
  }

  Future<void> _load() async {
    try {
      final state = await SystemControls.getState();
      if (!mounted) return;
      setState(() {
        _brightness = widget.settings.screenBrightness;
        _volume = (state['volume'] ?? 0.5).clamp(0.0, 1.0).toDouble();
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _setBrightness(double value) async {
    setState(() => _brightness = value);
    await widget.settings.setScreenBrightness(value);
    try { await SystemControls.setBrightness(value); } catch (_) {}
  }

  Future<void> _setVolume(double value) async {
    setState(() => _volume = value);
    try { await SystemControls.setVolume(value); } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.brightness_6_rounded, color: Colors.white70, size: 17),
          const SizedBox(width: 8),
          const SizedBox(width: 70, child: Text('Brightness', style: TextStyle(color: Colors.white, fontSize: 12, decoration: TextDecoration.none))),
          Expanded(child: Slider(min: 0.05, max: 1, value: _brightness.clamp(0.05, 1).toDouble(), onChanged: _setBrightness)),
        ]),
        Row(children: [
          const Icon(Icons.volume_up_rounded, color: Colors.white70, size: 17),
          const SizedBox(width: 8),
          const SizedBox(width: 70, child: Text('Volume', style: TextStyle(color: Colors.white, fontSize: 12, decoration: TextDecoration.none))),
          Expanded(child: Slider(min: 0, max: 1, value: _volume.clamp(0, 1).toDouble(), onChanged: _setVolume)),
        ]),
        if (!_loaded) const LinearProgressIndicator(minHeight: 1),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.value,
    required this.active,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
      constraints: const BoxConstraints(minHeight: 62),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: active ? 0.105 : 0.045),
        borderRadius: BorderRadius.circular(Sequoia.cardRadius + 2),
        border: Border.all(
          color: Colors.white.withValues(alpha: active ? 0.10 : 0.055),
          width: 0.7,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: active ? 0.10 : 0.045),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              color: active ? Colors.white : Colors.white54,
              size: 17,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? Colors.white70 : Colors.white38,
                    fontSize: 10,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}
