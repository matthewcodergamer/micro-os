import 'package:flutter_test/flutter_test.dart';
import 'package:micro_os/services/performance_monitor.dart';

const _meminfo = '''
MemTotal:        7584240 kB
MemFree:          214120 kB
MemAvailable:    1876300 kB
Buffers:            9044 kB
Cached:          1903120 kB
SwapCached:       128400 kB
AnonPages:       3201410 kB
SwapTotal:       4194300 kB
SwapFree:        3145728 kB
''';

const _procStat = '''
cpu  12345 678 9012 456789 1234 56 78 0 0 0
cpu0 1234 67 901 45678 123 5 7 0 0 0
''';

void main() {
  group('parseMeminfo', () {
    test('reads total, available and swap in KiB', () {
      final info = parseMeminfo(_meminfo);

      expect(info.totalKb, 7584240);
      expect(info.availableKb, 1876300);
      expect(info.swapTotalKb, 4194300);
      expect(info.swapFreeKb, 3145728);
      expect(info.cachedKb, 1903120);
      expect(info.anonKb, 3201410);
    });

    test('derives used memory and a bounded fraction', () {
      final info = parseMeminfo(_meminfo);

      expect(info.usedKb, 7584240 - 1876300);
      expect(info.swapUsedKb, 4194300 - 3145728);
      expect(info.usedFraction, inInclusiveRange(0.0, 1.0));
      expect(info.readable, isTrue);
    });

    test('empty input is reported as unreadable instead of zero-used', () {
      final info = parseMeminfo('');

      expect(info.readable, isFalse);
      expect(info.totalMb, 0);
      expect(info.usedFraction, 0);
    });
  });

  group('parseProcStat', () {
    test('sums every jiffy field and counts iowait as idle', () {
      final times = parseProcStat(_procStat);

      expect(times, isNotNull);
      // user + nice + system + idle + iowait + irq + softirq + steal
      expect(times!.total, 12345 + 678 + 9012 + 456789 + 1234 + 56 + 78 + 0);
      expect(times.idle, 456789 + 1234);
    });

    test('returns null when the cpu line is missing', () {
      expect(parseProcStat('intr 12345\nctxt 9999\n'), isNull);
    });
  });

  group('parsePressureSomeAvg10', () {
    test('reads the some avg10 value', () {
      const psi =
          'some avg10=12.34 avg60=4.10 avg300=1.02 total=999\n'
          'full avg10=0.00 avg60=0.00 avg300=0.00 total=0\n';

      expect(parsePressureSomeAvg10(psi), closeTo(12.34, 0.001));
    });

    test('returns null for unparsable content', () {
      expect(parsePressureSomeAvg10('full avg10=1.00\n'), isNull);
      expect(parsePressureSomeAvg10(''), isNull);
    });
  });

  group('zramCompressionRatio', () {
    test('is orig/compr for real counters', () {
      expect(
        zramCompressionRatio(origBytes: 4194304, comprBytes: 1048576),
        closeTo(4.0, 0.0001),
      );
    });

    test('is null when a counter is missing or zero', () {
      expect(zramCompressionRatio(origBytes: 0, comprBytes: 10), isNull);
      expect(zramCompressionRatio(origBytes: 10, comprBytes: 0), isNull);
    });
  });

  group('percentile', () {
    test('interpolates between samples', () {
      final samples = [4.0, 1.0, 3.0, 2.0];

      expect(percentile(samples, 0), 1.0);
      expect(percentile(samples, 1), 4.0);
      expect(percentile(samples, 0.5), closeTo(2.5, 0.0001));
      expect(percentile(<double>[], 0.95), 0);
    });
  });

  group('pressureBand', () {
    test('maps PSI averages to bands', () {
      expect(pressureBand(null), 'unavailable');
      expect(pressureBand(0.4), 'idle');
      expect(pressureBand(4), 'light');
      expect(pressureBand(12), 'moderate');
      expect(pressureBand(30), 'heavy');
      expect(pressureBand(80), 'critical');
    });
  });

  group('describeBottleneck', () {
    test('flags memory pressure before anything else', () {
      expect(
        describeBottleneck(
          const PerformanceSnapshot(
            memory: MemoryInfo(totalKb: 1000, availableKb: 900),
            memoryPressureAvg10: 31,
            cpuPercent: 95,
          ),
        ),
        'Memory pressure',
      );
    });

    test('flags frame pacing when CPU and memory are healthy', () {
      expect(
        describeBottleneck(
          const PerformanceSnapshot(
            memory: MemoryInfo(totalKb: 1000, availableKb: 600),
            cpuPercent: 20,
            frames: FramePercentiles(p50: 12, p95: 31, p99: 40, samples: 60),
          ),
        ),
        'Frame pacing',
      );
    });

    test('reports a clean bill of health', () {
      expect(
        describeBottleneck(
          const PerformanceSnapshot(
            memory: MemoryInfo(totalKb: 1000, availableKb: 700),
            cpuPercent: 15,
          ),
        ),
        'No dominant bottleneck',
      );
    });
  });
}
