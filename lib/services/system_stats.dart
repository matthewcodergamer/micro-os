import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Polls the host Android system for the numbers shown in the menu bar.
///
/// RAM comes from /proc/meminfo, which is readable by ordinary apps. The swap
/// rows double as the ZRAM readout: Android exposes its compressed RAM as the
/// system swap device, so "swap used" is the closest honest number an app can
/// show without root.
class SystemStats extends ChangeNotifier {
  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();

  Timer? _timer;
  StreamSubscription<BatteryState>? _batterySub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  int batteryLevel = 0;
  bool charging = false;
  int ramUsedMb = 0;
  int ramTotalMb = 0;
  int swapUsedMb = 0;
  int swapTotalMb = 0;
  String connection = 'offline';
  DateTime now = DateTime.now();

  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    await _refreshBattery();
    await _refreshNetwork();
    await refreshMemory();

    _batterySub = _battery.onBatteryStateChanged.listen((state) {
      charging = state == BatteryState.charging || state == BatteryState.full;
      notifyListeners();
      _refreshBattery();
    });

    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      connection = _label(results);
      notifyListeners();
    });

    _timer = Timer.periodic(const Duration(seconds: 5), (_) async {
      now = DateTime.now();
      await refreshMemory();
      await _refreshBattery();
      notifyListeners();
    });
  }

  Future<void> _refreshBattery() async {
    try {
      batteryLevel = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      charging = state == BatteryState.charging || state == BatteryState.full;
    } catch (_) {
      // Desktop builds and some OEM ROMs do not expose battery data.
    }
  }

  Future<void> _refreshNetwork() async {
    try {
      connection = _label(await _connectivity.checkConnectivity());
    } catch (_) {
      connection = 'unknown';
    }
  }

  String _label(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi)) return 'wifi';
    if (results.contains(ConnectivityResult.mobile)) return 'mobile';
    if (results.contains(ConnectivityResult.ethernet)) return 'ethernet';
    return 'offline';
  }

  Future<void> refreshMemory() async {
    try {
      final info = await File('/proc/meminfo').readAsLines();
      var total = 0;
      var available = 0;
      var swapTotal = 0;
      var swapFree = 0;

      for (final line in info) {
        final kb = _kbValue(line);
        if (line.startsWith('MemTotal:')) total = kb;
        if (line.startsWith('MemAvailable:')) available = kb;
        if (line.startsWith('SwapTotal:')) swapTotal = kb;
        if (line.startsWith('SwapFree:')) swapFree = kb;
      }

      if (total > 0) {
        ramTotalMb = total ~/ 1024;
        ramUsedMb = (total - available) ~/ 1024;
      }
      swapTotalMb = swapTotal ~/ 1024;
      swapUsedMb = (swapTotal - swapFree) ~/ 1024;
    } catch (_) {
      // Not Android (or /proc is restricted): leave the last values in place.
    }
  }

  int _kbValue(String line) {
    final match = RegExp(r'(\d+)').firstMatch(line);
    return match == null ? 0 : int.tryParse(match.group(1)!) ?? 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _batterySub?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }
}
