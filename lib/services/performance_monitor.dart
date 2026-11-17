import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Read-only telemetry for the Misty Performance Engine.
///
/// Everything here is measured on the device. No value is estimated, smoothed
/// or invented: when the kernel or Android hides a source, the field stays
/// `null` and the UI says so. Sources:
///
/// * `/proc/meminfo`            — RAM and swap (Android exposes ZRAM as swap)
/// * `/proc/stat`               — CPU time counters, sampled twice
/// * `/proc/pressure/*`         — PSI stall averages (Linux 5.2+)
/// * `/sys/block/zram0/*`       — ZRAM compression ratio, when readable
/// * `/proc/<pid>/status`       — per-process RSS
/// * `SchedulerBinding` timings  — UI/raster frame durations
class MemoryInfo {
  const MemoryInfo({
    this.totalKb = 0,
    this.availableKb = 0,
    this.swapTotalKb = 0,
    this.swapFreeKb = 0,
    this.cachedKb = 0,
    this.anonKb = 0,
  });

  final int totalKb;
  final int availableKb;
  final int swapTotalKb;
  final int swapFreeKb;
  final int cachedKb;
  final int anonKb;

  bool get readable => totalKb > 0;

  int get usedKb => totalKb > availableKb ? totalKb - availableKb : 0;
  int get swapUsedKb => swapTotalKb > swapFreeKb ? swapTotalKb - swapFreeKb : 0;

  int get totalMb => totalKb ~/ 1024;
  int get usedMb => usedKb ~/ 1024;
  int get availableMb => availableKb ~/ 1024;
  int get swapTotalMb => swapTotalKb ~/ 1024;
  int get swapUsedMb => swapUsedKb ~/ 1024;

  double get usedFraction =>
      totalKb == 0 ? 0 : (usedKb / totalKb).clamp(0.0, 1.0);
}

/// Cumulative CPU jiffies from the aggregate `cpu` line of `/proc/stat`.
class CpuTimes {
  const CpuTimes({required this.idle, required this.total});

  final int idle;
  final int total;
}

class ProcessRss {
  const ProcessRss({
    required this.pid,
    required this.name,
    required this.rssKb,
  });

  final int pid;
  final String name;
  final int rssKb;

  int get rssMb => rssKb ~/ 1024;
}

/// Frame-time percentiles in milliseconds for the current sample window.
class FramePercentiles {
  const FramePercentiles({
    this.p50 = 0,
    this.p95 = 0,
    this.p99 = 0,
    this.samples = 0,
  });

  final double p50;
  final double p95;
  final double p99;
  final int samples;

  bool get hasData => samples > 0;
}

/// One immutable measurement of the whole device.
class PerformanceSnapshot {
  const PerformanceSnapshot({
    this.memory = const MemoryInfo(),
    this.cpuPercent,
    this.memoryPressureAvg10,
    this.cpuPressureAvg10,
    this.ioPressureAvg10,
    this.zramRatio,
    this.zramUsedMb,
    this.topProcesses = const <ProcessRss>[],
    this.frames = const FramePercentiles(),
    this.processListLimited = false,
    this.capturedAt,
  });

  final MemoryInfo memory;
  final double? cpuPercent;
  final double? memoryPressureAvg10;
  final double? cpuPressureAvg10;
  final double? ioPressureAvg10;
  final double? zramRatio;
  final int? zramUsedMb;
  final List<ProcessRss> topProcesses;
  final FramePercentiles frames;

  /// True when Android's `/proc` restrictions meant only a handful of
  /// processes were readable.
  final bool processListLimited;
  final DateTime? capturedAt;
}

/// Parses the subset of `/proc/meminfo` the shell needs.
MemoryInfo parseMeminfo(String text) {
  var total = 0;
  var available = 0;
  var swapTotal = 0;
  var swapFree = 0;
  var cached = 0;
  var anon = 0;

  for (final line in const LineSplitter().convert(text)) {
    final value = _firstInt(line);
    if (value == null) continue;
    if (line.startsWith('MemTotal:')) total = value;
    if (line.startsWith('MemAvailable:')) available = value;
    if (line.startsWith('SwapTotal:')) swapTotal = value;
    if (line.startsWith('SwapFree:')) swapFree = value;
    if (line.startsWith('Cached:')) cached = value;
    if (line.startsWith('AnonPages:')) anon = value;
  }

  return MemoryInfo(
    totalKb: total,
    availableKb: available,
    swapTotalKb: swapTotal,
    swapFreeKb: swapFree,
    cachedKb: cached,
    anonKb: anon,
  );
}

/// Parses the aggregate `cpu` line of `/proc/stat`.
CpuTimes? parseProcStat(String text) {
  final line = const LineSplitter()
      .convert(text)
      .firstWhere((l) => l.startsWith('cpu '), orElse: () => '');
  if (line.isEmpty) return null;

  final parts = line.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.length < 5) return null;

  final values = <int>[];
  for (var i = 1; i < parts.length && i < 9; i++) {
    final parsed = int.tryParse(parts[i]);
    if (parsed == null) return null;
    values.add(parsed);
  }
  if (values.length < 4) return null;

  // user nice system idle iowait irq softirq steal
  final idle = values[3] + (values.length > 4 ? values[4] : 0);
  final total = values.fold<int>(0, (sum, v) => sum + v);
  return CpuTimes(idle: idle, total: total);
}

/// Returns `some avg10` from a PSI file such as `/proc/pressure/memory`.
double? parsePressureSomeAvg10(String text) {
  for (final line in const LineSplitter().convert(text)) {
    if (!line.startsWith('some')) continue;
    final match = RegExp(r'avg10=([0-9.]+)').firstMatch(line);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }
  return null;
}

/// ZRAM compression ratio; `null` when either counter is unreadable or zero.
double? zramCompressionRatio({
  required int origBytes,
  required int comprBytes,
}) {
  if (origBytes <= 0 || comprBytes <= 0) return null;
  return origBytes / comprBytes;
}

/// Linear-interpolated percentile over an unsorted sample list.
double percentile(List<double> samples, double p) {
  if (samples.isEmpty) return 0;
  final sorted = List<double>.of(samples)..sort();
  final clamped = p.clamp(0.0, 1.0);
  final rank = (sorted.length - 1) * clamped;
  final lower = rank.floor();
  final upper = rank.ceil();
  if (lower == upper) return sorted[lower];
  final weight = rank - lower;
  return sorted[lower] * (1 - weight) + sorted[upper] * weight;
}

/// Human-readable memory-pressure band for a PSI `some avg10` percentage.
String pressureBand(double? someAvg10) {
  if (someAvg10 == null) return 'unavailable';
  if (someAvg10 < 1) return 'idle';
  if (someAvg10 < 10) return 'light';
  if (someAvg10 < 25) return 'moderate';
  if (someAvg10 < 50) return 'heavy';
  return 'critical';
}

/// Polls the device while a Performance page is visible.
///
/// The monitor is deliberately not global: it owns a [SchedulerBinding] timings
/// callback and per-process `/proc` scans, so it only runs while somebody is
/// looking at it and costs nothing during normal use.
class PerformanceMonitor extends ChangeNotifier {
  PerformanceMonitor({
    this.interval = const Duration(seconds: 2),
    this.topProcessCount = 5,
  });

  final Duration interval;
  final int topProcessCount;

  Timer? _timer;
  bool _running = false;
  bool _collecting = false;
  PerformanceSnapshot snapshot = const PerformanceSnapshot();

  final List<double> _frameMs = <double>[];
  static const int _maxFrameSamples = 240;

  // A `/proc` sweep reads a few hundred small files, so it runs at most every
  // ten seconds even though the cheap counters refresh every two.
  static const Duration _processScanInterval = Duration(seconds: 10);
  DateTime? _lastProcessScan;
  List<ProcessRss> _lastProcesses = const <ProcessRss>[];
  bool _lastProcessListLimited = false;

  bool get isRunning => _running;

  void start() {
    if (_running) return;
    _running = true;
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
    unawaited(refresh());
    _timer = Timer.periodic(interval, (_) => unawaited(refresh()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    if (!_running) return;
    _running = false;
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _frameMs.add(timing.totalSpan.inMicroseconds / 1000.0);
    }
    if (_frameMs.length > _maxFrameSamples) {
      _frameMs.removeRange(0, _frameMs.length - _maxFrameSamples);
    }
  }

  Future<void> refresh() async {
    if (_collecting) return;
    _collecting = true;
    try {
      final memory = await _readMemory();
      final cpu = await _readCpuPercent();
      final pressure = await _readPressure();
      final zram = await _readZram();
      final processes = await _readProcessesThrottled();
      final frames = FramePercentiles(
        p50: percentile(_frameMs, 0.50),
        p95: percentile(_frameMs, 0.95),
        p99: percentile(_frameMs, 0.99),
        samples: _frameMs.length,
      );

      snapshot = PerformanceSnapshot(
        memory: memory ?? const MemoryInfo(),
        cpuPercent: cpu,
        memoryPressureAvg10: pressure.memory,
        cpuPressureAvg10: pressure.cpu,
        ioPressureAvg10: pressure.io,
        zramRatio: zram.ratio,
        zramUsedMb: zram.usedMb,
        topProcesses: processes.list,
        processListLimited: processes.limited,
        frames: frames,
        capturedAt: DateTime.now(),
      );
      notifyListeners();
    } finally {
      _collecting = false;
    }
  }

  void resetFrameStats() {
    _frameMs.clear();
    notifyListeners();
  }

  Future<MemoryInfo?> _readMemory() async {
    try {
      return parseMeminfo(await File('/proc/meminfo').readAsString());
    } catch (_) {
      return null;
    }
  }

  Future<CpuTimes?> _readCpuTimes() async {
    try {
      return parseProcStat(await File('/proc/stat').readAsString());
    } catch (_) {
      return null;
    }
  }

  Future<double?> _readCpuPercent() async {
    final first = await _readCpuTimes();
    if (first == null) return null;
    await Future<void>.delayed(const Duration(milliseconds: 240));
    final second = await _readCpuTimes();
    if (second == null) return null;

    final totalDelta = second.total - first.total;
    final idleDelta = second.idle - first.idle;
    if (totalDelta <= 0) return null;
    final busy = ((totalDelta - idleDelta) / totalDelta) * 100.0;
    return busy.clamp(0.0, 100.0);
  }

  Future<({double? memory, double? cpu, double? io})> _readPressure() async {
    Future<double?> read(String path) async {
      try {
        return parsePressureSomeAvg10(await File(path).readAsString());
      } catch (_) {
        return null;
      }
    }

    return (
      memory: await read('/proc/pressure/memory'),
      cpu: await read('/proc/pressure/cpu'),
      io: await read('/proc/pressure/io'),
    );
  }

  Future<({double? ratio, int? usedMb})> _readZram() async {
    Future<int?> readInt(String path) async {
      try {
        final raw = (await File(path).readAsString()).trim();
        return int.tryParse(raw);
      } catch (_) {
        return null;
      }
    }

    final orig = await readInt('/sys/block/zram0/orig_data_size');
    final compr = await readInt('/sys/block/zram0/compr_data_size');
    final used = await readInt('/sys/block/zram0/mem_used_total');
    return (
      ratio: (orig == null || compr == null)
          ? null
          : zramCompressionRatio(origBytes: orig, comprBytes: compr),
      usedMb: used == null ? null : used ~/ (1024 * 1024),
    );
  }

  Future<({List<ProcessRss> list, bool limited})>
  _readProcessesThrottled() async {
    final last = _lastProcessScan;
    if (last != null &&
        DateTime.now().difference(last) < _processScanInterval) {
      return (list: _lastProcesses, limited: _lastProcessListLimited);
    }

    final result = await _readProcesses();
    _lastProcessScan = DateTime.now();
    _lastProcesses = result.list;
    _lastProcessListLimited = result.limited;
    return result;
  }

  Future<({List<ProcessRss> list, bool limited})> _readProcesses() async {
    final results = <ProcessRss>[];
    try {
      await for (final entry in Directory('/proc').list(followLinks: false)) {
        final pid = int.tryParse(entry.path.split('/').last);
        if (pid == null) continue;
        try {
          final status = await File('/proc/$pid/status').readAsLines();
          var name = '';
          var rss = 0;
          for (final line in status) {
            if (line.startsWith('Name:')) {
              name = line.substring(5).trim();
            } else if (line.startsWith('VmRSS:')) {
              final match = RegExp(r'(\d+)').firstMatch(line);
              rss = match == null ? 0 : int.tryParse(match.group(1)!) ?? 0;
            }
          }
          if (rss > 0) {
            results.add(ProcessRss(pid: pid, name: name, rssKb: rss));
          }
        } catch (_) {
          // Android hides most processes from third-party apps; skip them.
        }
      }
    } catch (_) {
      return (list: const <ProcessRss>[], limited: true);
    }

    results.sort((a, b) => b.rssKb.compareTo(a.rssKb));
    final limited = results.length < 3;
    return (
      list: results.take(topProcessCount).toList(growable: false),
      limited: limited,
    );
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

int? _firstInt(String line) {
  final match = RegExp(r'(\d+)').firstMatch(line);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

/// Utility used by the Performance page to format a ratio without lying about
/// missing data.
String formatRatio(double? ratio) =>
    ratio == null ? 'unavailable' : '${ratio.toStringAsFixed(2)}:1';

/// Formats a measured percentage, or `unavailable`.
String formatPercent(double? value) =>
    value == null ? 'unavailable' : '${value.toStringAsFixed(1)}%';

/// Formats a frame-time percentile.
String formatMs(double value) => '${value.toStringAsFixed(1)} ms';

/// Compares two snapshots so the page can flag the dominant bottleneck.
String describeBottleneck(PerformanceSnapshot s) {
  final pressure = s.memoryPressureAvg10;
  if (pressure != null && pressure >= 25) return 'Memory pressure';
  if (s.memory.readable && s.memory.usedFraction >= 0.9)
    return 'Memory saturation';
  if (s.cpuPercent != null && s.cpuPercent! >= 85) return 'CPU saturation';
  if (s.frames.hasData && s.frames.p95 >= 24) return 'Frame pacing';
  if (s.memory.swapTotalMb > 0 &&
      s.memory.swapUsedMb > 0 &&
      s.memory.swapUsedMb > s.memory.totalMb * 0.35) {
    return 'Swap activity';
  }
  return 'No dominant bottleneck';
}
