// Screenshot harness for Misty OS.
//
// The Flutter shell is rendered with the real widgets, real fonts and real
// assets. Only the Linux backend is simulated: CI runners cannot start the
// Android PRoot guest, so terminal sessions and Finder listings are fed by a
// small in-memory fake. Run with:
//
//   flutter test test_screens/
//
// PNGs are written to build/screenshots/.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micro_os/app_scope.dart';
import 'package:micro_os/main.dart';
import 'package:micro_os/services/github_auth.dart';
import 'package:micro_os/services/linux_runtime.dart';
import 'package:micro_os/services/settings_store.dart';
import 'package:micro_os/services/system_stats.dart';
import 'package:micro_os/state/desktop_state.dart';
import 'package:micro_os/ui/desktop_screen.dart';

/// Loads every font declared in the app's FontManifest so text renders with
/// Inter / JetBrains Mono / Material Icons instead of the Ahem test font.
Future<void> loadAppFonts() async {
  final manifest =
      json.decode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final entry in manifest.cast<Map<String, Object?>>()) {
    final family = entry['family']! as String;
    final fonts = (entry['fonts']! as List).cast<Map<String, Object?>>();
    Future<void> loadAs(String name) async {
      final loader = FontLoader(name);
      for (final font in fonts) {
        loader.addFont(rootBundle.load(font['asset']! as String));
      }
      await loader.load();
    }

    await loadAs(family);
    // Package fonts are referenced both with and without their prefix.
    final stripped = family.replaceFirst(RegExp(r'^packages/[^/]+/'), '');
    if (stripped != family) await loadAs(stripped);
  }
}

/// A device profile for a screenshot.
class DeviceProfile {
  const DeviceProfile({
    required this.name,
    required this.size,
    required this.pixelRatio,
    this.topInset = 0,
    this.bottomGesture = 0,
  });

  final String name;
  final Size size;
  final double pixelRatio;
  final double topInset;
  final double bottomGesture;

  static const phonePortrait = DeviceProfile(
    name: 'phone',
    size: Size(412, 915),
    pixelRatio: 2,
    topInset: 26,
    bottomGesture: 18,
  );

  static const phoneLandscape = DeviceProfile(
    name: 'phone-landscape',
    size: Size(915, 412),
    pixelRatio: 2,
    bottomGesture: 14,
  );

  static const tablet = DeviceProfile(
    name: 'tablet',
    size: Size(1280, 800),
    pixelRatio: 1.25,
    topInset: 0,
    bottomGesture: 14,
  );

  void apply(WidgetTester tester) {
    tester.view.devicePixelRatio = pixelRatio;
    tester.view.physicalSize = size * pixelRatio;
    tester.view.viewPadding = FakeViewPadding(top: topInset * pixelRatio);
    tester.view.padding = FakeViewPadding(top: topInset * pixelRatio);
    tester.view.systemGestureInsets = FakeViewPadding(
      bottom: bottomGesture * pixelRatio,
    );
  }
}

/// In-memory PTY that plays back a scripted session.
class FakePty implements Pty {
  FakePty(this.executable, this.arguments, String script) {
    _controller = StreamController<Uint8List>(
      onListen: () {
        if (script.isNotEmpty) {
          _controller.add(Uint8List.fromList(utf8.encode(script)));
        }
        if (closeAfterScript) {
          scheduleMicrotask(() {
            _controller.close();
            if (!_exit.isCompleted) _exit.complete(0);
          });
        }
      },
    );
  }

  @override
  final String executable;

  @override
  final List<String> arguments;

  late final StreamController<Uint8List> _controller;
  final Completer<int> _exit = Completer<int>();
  bool closeAfterScript = false;

  @override
  Stream<Uint8List> get output => _controller.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  int get pid => 4242;

  @override
  void write(Uint8List data) {
    // Echo typed input like a cooked TTY would.
    if (!_controller.isClosed) _controller.add(data);
  }

  @override
  void resize(int rows, int cols) {}

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_exit.isCompleted) _exit.complete(0);
    if (!_controller.isClosed) _controller.close();
    return true;
  }

  @override
  void ackRead() {}
}

const String _esc = '\u001b';
const String kPrompt =
    '$_esc[1;32mroot@misty$_esc[0m:$_esc[1;34m~$_esc[0m\$ ';

/// A short, plainly illustrative shell session for terminal screenshots.
String demoShellSession() {
  final b = StringBuffer()
    ..write('\r\n  Misty OS · Ubuntu 24.04 · aarch64\r\n')
    ..write('  /mnt/android = phone storage · opencode · gh · node\r\n\r\n')
    ..write('${kPrompt}ls\r\n')
    ..write('$_esc[1;34mDesktop$_esc[0m  $_esc[1;34mDocuments$_esc[0m  '
        '$_esc[1;34mDownloads$_esc[0m  $_esc[1;34mProjects$_esc[0m\r\n')
    ..write('${kPrompt}cd Projects/misty-site && git status -sb\r\n')
    ..write('## main...origin/main\r\n')
    ..write(' $_esc[31mM$_esc[0m index.html\r\n')
    ..write('$_esc[31m??$_esc[0m notes.md\r\n')
    ..write('${kPrompt}node --version\r\n')
    ..write('v22.11.0\r\n')
    ..write(kPrompt);
  return b.toString();
}

/// Linux backend replacement for screenshots and widget tests.
///
/// It keeps the real [LinuxRuntime] API surface but never spawns PRoot.
class PreviewRuntime extends LinuxRuntime {
  PreviewRuntime(this.root) {
    status = RuntimeStatus.ready;
    stage = 'Pre-baked Linux ready';
    progress = 1;
  }

  /// Host directory standing in for the app's Linux base directory. The fake
  /// guest filesystem lives in `root/rootfs`.
  final Directory root;

  @override
  Directory get base => root;

  final List<List<String>?> shells = <List<String>?>[];

  @override
  Pty startShell({
    List<String>? argv,
    Map<String, String> extraEnv = const <String, String>{},
  }) {
    shells.add(argv);
    final joined = argv?.join(' ') ?? '';
    if (joined.contains('microos-finder')) {
      final path = argv!.last;
      final pty = FakePty('proot', argv, _findListing(path))
        ..closeAfterScript = true;
      return pty;
    }
    return FakePty('proot', argv ?? const <String>[], demoShellSession());
  }

  String _findListing(String guestPath) {
    final dir = Directory('${root.path}/rootfs$guestPath');
    if (!dir.existsSync()) return '__MICROOS_DIRECTORY_NOT_FOUND__';
    final b = StringBuffer();
    for (final entity in dir.listSync(followLinks: false)) {
      final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final type = entity is Directory ? 'd' : (entity is Link ? 'l' : 'f');
      final size = entity is File ? entity.lengthSync() : 4096;
      b.write('$type\u0000$size\u0000$name\u0000');
    }
    return b.toString();
  }

  @override
  Future<bool> ensureDisplay({bool restart = false}) async => false;

  @override
  Future<void> launchBrowser({
    String? url,
    String browser = 'chromium',
    bool singleProcess = false,
  }) async {}

  @override
  Future<bool> ensureTorrentService() async => false;
}

/// Creates a believable home directory for Finder screenshots.
Directory createPreviewRootfs() {
  final base = Directory.systemTemp.createTempSync('misty-preview-');
  final home = Directory('${base.path}/rootfs/root')..createSync(recursive: true);
  for (final folder in <String>[
    'Desktop',
    'Documents',
    'Downloads',
    'Music',
    'Pictures',
    'Projects',
    'Projects/misty-site',
  ]) {
    Directory('${home.path}/$folder').createSync(recursive: true);
  }
  File('${home.path}/README.md').writeAsStringSync('# Misty OS\n' * 40);
  File('${home.path}/notes.txt').writeAsStringSync('todo\n' * 300);
  File('${home.path}/build.sh').writeAsStringSync('#!/bin/sh\necho hi\n');
  File('${home.path}/Projects/misty-site/index.html')
      .writeAsStringSync('<h1>Misty</h1>');
  Directory('${base.path}/rootfs/etc').createSync(recursive: true);
  File('${base.path}/rootfs/etc/os-release')
      .writeAsStringSync('NAME="Ubuntu"\nVERSION="24.04"\n');
  return base;
}

/// Everything a scene needs.
class PreviewApp {
  PreviewApp._(this.runtime, this.settings, this.stats, this.auth);

  final PreviewRuntime runtime;
  final SettingsStore settings;
  final SystemStats stats;
  final GithubAuth auth;

  static PreviewApp create(Directory rootfs) {
    final runtime = PreviewRuntime(rootfs);
    final settings = SettingsStore();
    final stats = SystemStats()
      ..batteryLevel = 82
      ..charging = false
      ..connection = 'wifi'
      ..ramUsedMb = 2310
      ..ramTotalMb = 3780
      ..swapUsedMb = 640
      ..swapTotalMb = 2048;
    return PreviewApp._(runtime, settings, stats, GithubAuth());
  }

  Widget build() {
    return RepaintBoundary(
      key: shotKey,
      child: MistyOSApp(
        runtime: runtime,
        stats: stats,
        auth: auth,
        settings: settings,
      ),
    );
  }
}

final GlobalKey shotKey = GlobalKey(debugLabel: 'misty-screenshot');

DesktopState desktopOf(WidgetTester tester) {
  final element = tester.element(find.byType(DesktopScreen));
  return AppScope.of(element).desktop;
}

/// Pumps fixed frames. pumpAndSettle would never settle while a terminal
/// cursor blinks or a progress spinner turns.
Future<void> settle(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> precacheImages(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate().toList()) {
      final widget = element.widget as Image;
      try {
        await precacheImage(widget.image, element);
      } catch (_) {
        // A missing optional wallpaper falls back to the painted sky.
      }
    }
  });
  await tester.pump();
}

/// Captures the whole app into build/screenshots/[name].png.
Future<void> capture(WidgetTester tester, String name) async {
  await precacheImages(tester);
  await settle(tester, frames: 3);
  await precacheImages(tester);
  final boundary =
      shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(
      pixelRatio: tester.view.devicePixelRatio,
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  final file = File('build/screenshots/$name.png');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes!);
}

/// Runs [body] while recording Flutter errors instead of failing the scene,
/// so one broken widget still leaves a screenshot and an error report.
Future<void> recordingErrors(
  String scene,
  Future<void> Function() body,
) async {
  final errors = <String>[];
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    errors.add(details.exceptionAsString().split('\n').first);
  };
  try {
    await body();
  } finally {
    FlutterError.onError = original;
    final report = File('build/screenshots/$scene.errors.txt');
    report.parent.createSync(recursive: true);
    if (errors.isEmpty) {
      if (report.existsSync()) report.deleteSync();
    } else {
      report.writeAsStringSync('${errors.toSet().join('\n')}\n');
    }
  }
}
