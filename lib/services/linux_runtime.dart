import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum RuntimeStatus { checking, missing, installing, ready, failed }

/// Owns the Linux guest: unpacks the bundled rootfs, runs first-boot
/// provisioning, and launches processes inside it through proot.
///
/// Everything the UI needs is exposed as plain Dart calls so the window manager
/// never has to know whether it is talking to a local proot guest or (later) a
/// remote host.
class LinuxRuntime extends ChangeNotifier {
  static const String _rootfsAsset = 'assets/rootfs/rootfs.tar.gz';
  static const String _setupAsset = 'tool/setup.sh';
  static const String _readyMarker = 'root/.microos/ready';

  /// proot and the pieces it needs at runtime. They are extracted next to the
  /// rootfs instead of being executed straight out of the APK, because Android
  /// will not execve() a file that lives inside an archive.
  static const List<String> _prootFiles = <String>[
    'proot',
    'loader',
    'libtalloc.so.2',
    'libandroid-shmem.so',
  ];

  RuntimeStatus status = RuntimeStatus.checking;
  String stage = 'Starting up';
  double progress = 0;
  String? error;

  final List<String> logLines = <String>[];
  final List<Pty> _background = <Pty>[];

  Directory? _base;
  bool _displayRequested = false;
  bool _disposed = false;

  bool get isReady => status == RuntimeStatus.ready;
  bool get isBusy => status == RuntimeStatus.installing;

  Directory get base {
    final dir = _base;
    if (dir == null) {
      throw StateError('LinuxRuntime.init() has not completed yet');
    }
    return dir;
  }

  String get rootfsPath => p.join(base.path, 'rootfs');
  String get prootPath => p.join(base.path, 'proot', 'proot');
  String get _readyPath => p.join(rootfsPath, _readyMarker);

  /// Environment handed to every proot invocation.
  Map<String, String> get _prootEnv => <String, String>{
        'PROOT_LOADER': p.join(base.path, 'proot', 'loader'),
        'PROOT_TMP_DIR': p.join(base.path, 'tmp'),
        'PROOT_NO_SECCOMP': '1',
        'LD_LIBRARY_PATH': p.join(base.path, 'proot'),
        'HOME': '/root',
        'TERM': 'xterm-256color',
        'LANG': 'C.UTF-8',
        'DISPLAY': ':1',
        'PATH': '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:'
            '/root/.opencode/bin:/root/.local/bin',
      };

  // ---------------------------------------------------------------- lifecycle

  Future<void> init() async {
    if (!Platform.isAndroid) {
      status = RuntimeStatus.failed;
      error = 'The bundled Linux guest requires Android. On iOS the same UI '
          'runs against a remote host instead.';
      _notify();
      return;
    }

    try {
      // Application Support is app-private internal storage on Android.
      // Do not unpack the Linux guest into shared external storage, which
      // cannot represent the Unix links and permissions used by Ubuntu.
      final support = await getApplicationSupportDirectory();
      _base = Directory(p.join(support.path, 'linux'));
      await _base!.create(recursive: true);
      await Directory(p.join(base.path, 'tmp')).create(recursive: true);

      status = File(_readyPath).existsSync()
          ? RuntimeStatus.ready
          : RuntimeStatus.missing;
      stage = status == RuntimeStatus.ready ? 'Linux ready' : 'Linux not installed';
      progress = status == RuntimeStatus.ready ? 1 : 0;
    } catch (e) {
      status = RuntimeStatus.failed;
      error = '$e';
    }
    _notify();
  }

  Future<void> install() async {
    if (isBusy || !Platform.isAndroid) return;

    status = RuntimeStatus.installing;
    error = null;
    logLines.clear();
    progress = 0.01;
    stage = 'Preparing storage';
    _notify();

    try {
      await _extractProot();

      progress = 0.08;
      stage = 'Unpacking Ubuntu rootfs';
      _notify();
      await _extractRootfs();

      progress = 0.55;
      stage = 'Installing developer toolchain';
      _notify();
      await _installSetupScript();
      await _runProvisioning();

      if (File(_readyPath).existsSync()) {
        status = RuntimeStatus.ready;
        progress = 1;
        stage = 'Linux ready';
      } else {
        status = RuntimeStatus.failed;
        error = 'Provisioning stopped before it finished. Check the log below.';
      }
    } catch (e, stack) {
      status = RuntimeStatus.failed;
      error = '$e';
      _appendLog('install failed: $e\n$stack');
    }

    _notify();
  }

  Future<void> reinstall() async {
    if (isBusy) return;
    try {
      final dir = Directory(rootfsPath);
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (e) {
      _appendLog('could not remove old rootfs: $e');
    }
    status = RuntimeStatus.missing;
    _notify();
    await install();
  }

  // ---------------------------------------------------------------- extraction

  Future<void> _extractProot() async {
    final prootDir = Directory(p.join(base.path, 'proot'));
    await prootDir.create(recursive: true);

    for (final name in _prootFiles) {
      final asset = await rootBundle.load('assets/proot/$name');
      final file = File(p.join(prootDir.path, name));
      await file.writeAsBytes(
        asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
        flush: true,
      );
      await _chmod(file.path, name == 'proot' || name == 'loader' ? '755' : '644');
    }

    if (!File(prootPath).existsSync()) {
      throw StateError('proot binary is missing from the APK assets');
    }
  }

  Future<void> _extractRootfs() async {
    final target = Directory(rootfsPath);
    await target.create(recursive: true);

    final tarFile = File(p.join(base.path, 'rootfs.tar.gz'));
    if (!tarFile.existsSync() || tarFile.lengthSync() < 1024 * 1024) {
      final data = await rootBundle.load(_rootfsAsset);
      await tarFile.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }

    // Use the in-process extractor: Android toybox tar rejects Ubuntu
    // absolute symlink targets. The Dart extractor re-roots them in rootfs.
    await _extractWithDart(tarFile.path, target.path);

    if (!File(p.join(rootfsPath, 'etc/os-release')).existsSync()) {
      throw StateError('rootfs extraction produced no /etc/os-release');
    }

    try {
      await tarFile.delete();
    } catch (_) {
      // Not fatal, just wasted space.
    }
  }

  Future<bool> _extractWithSystemTar(String tarPath, String destination) async {
    try {
      final result = await Process.run(
        '/system/bin/tar',
        <String>['-xzf', tarPath, '-C', destination],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (result.exitCode != 0) {
        _appendLog('system tar exited ${result.exitCode}: ${result.stderr}');
        return false;
      }
      return File(p.join(destination, 'etc/os-release')).existsSync();
    } catch (e) {
      _appendLog('system tar failed: $e');
      return false;
    }
  }

  Future<void> _extractWithDart(String tarPath, String destination) async {
    final raw = await File(tarPath).readAsBytes();
    final decompressed = GZipDecoder().decodeBytes(raw);
    final archive = TarDecoder().decodeBytes(decompressed);

    for (final entry in archive.files) {
      final name = p.posix.normalize(entry.name.replaceFirst(RegExp(r'^\./'), ''));
      if (name.isEmpty || name == '.' || name.startsWith('/') ||
          name == '..' || name.startsWith('../')) continue;
      final outPath = p.join(destination, name);

      if (entry.isSymbolicLink) {
        final link = Link(outPath);
        await link.parent.create(recursive: true);
        if (link.existsSync()) await link.delete();
        final target = entry.nameOfLinkedFile;
        final safeTarget = target.startsWith('/')
            ? p.posix.relative(
                p.posix.normalize(target),
                from: p.posix.dirname('/$name'),
              )
            : target;
        await link.create(safeTarget);
        continue;
      }

      if (!entry.isFile) {
        await Directory(outPath).create(recursive: true);
        continue;
      }

      final file = File(outPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(_bytesOf(entry), flush: false);
      final mode = entry.unixPermissions;
      if (mode != 0) await _chmod(outPath, mode.toRadixString(8));
    }
  }


  Uint8List _bytesOf(ArchiveFile entry) {
    final content = entry.content;
    if (content is Uint8List) return content;
    if (content is List<int>) return Uint8List.fromList(content);
    try {
      final dynamic stream = content;
      return Uint8List.fromList(stream.toUint8Array() as List<int>);
    } catch (_) {
      return Uint8List(0);
    }
  }

  Future<void> _chmod(String path, String mode) async {
    try {
      await Process.run('/system/bin/chmod', <String>[mode, path]);
    } catch (_) {
      // Non-fatal: the app data dir is already 0700 and proot runs as root.
    }
  }

  // -------------------------------------------------------------- provisioning

  Future<void> _installSetupScript() async {
    final script = await rootBundle.loadString(_setupAsset);
    final dir = Directory(p.join(rootfsPath, 'root/.microos'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, 'setup.sh'));
    await file.writeAsString(script);
    await _chmod(file.path, '755');

    // apt refuses to run as a non-root sandbox user under proot.
    final aptConf = File(p.join(rootfsPath, 'etc/apt/apt.conf.d/99microos'));
    await aptConf.parent.create(recursive: true);
    await aptConf.writeAsString('APT::Sandbox::User "root";\n');
  }

  Future<void> _runProvisioning() async {
    final pty = Pty.start(
      prootPath,
      arguments: _prootArgs(<String>['/bin/bash', '/root/.microos/setup.sh']),
      environment: _prootEnv,
    );

    pty.output.listen((data) {
      _appendLog(utf8.decode(data, allowMalformed: true));
    });

    final code = await pty.exitCode;
    _appendLog('\n[microos] provisioning exited with code $code');
  }

  // ------------------------------------------------------------------ sessions

  List<String> _prootArgs(List<String> argv) {
    final shared = Directory('/storage/emulated/0');
    final downloads = Directory('/storage/emulated/0/Download');

    return <String>[
      '--link2symlink',
      '-0',
      '-r',
      rootfsPath,
      '-b',
      '/dev',
      '-b',
      '/proc',
      '-b',
      '/sys',
      // Android shared storage, so the guest sees the phone's real files.
      // Binds are only added when the path exists: a missing bind aborts proot.
      if (shared.existsSync()) ...<String>['-b', '/storage/emulated/0:/mnt/android'],
      if (downloads.existsSync())
        ...<String>['-b', '/storage/emulated/0/Download:/root/Downloads'],
      '-b',
      '${base.path}/tmp:/tmp',
      '-w',
      '/root',
      ...argv,
    ];
  }

  /// Starts an interactive shell (or [argv]) inside the guest.
  Pty startShell({List<String>? argv}) {
    final pty = Pty.start(
      prootPath,
      arguments: _prootArgs(argv ?? <String>['/bin/bash', '-l']),
      environment: _prootEnv,
    );
    return pty;
  }

  /// Fire-and-forget process inside the guest (window manager, browser...).
  Pty runDetached(List<String> argv, {Map<String, String> extraEnv = const {}}) {
    final pty = Pty.start(
      prootPath,
      arguments: _prootArgs(argv),
      environment: <String, String>{..._prootEnv, ...extraEnv},
    );
    _background.add(pty);
    pty.output.listen(
      (data) => _appendLog(utf8.decode(data, allowMalformed: true)),
      onDone: () => _background.remove(pty),
    );
    return pty;
  }

  /// Boots Xvfb + openbox + x11vnc + noVNC, then waits until the web socket
  /// port actually accepts connections before the UI tries to connect.
  Future<bool> ensureDisplay({bool restart = false}) async {
    if (!isReady) return false;

    void start() {
      _displayRequested = true;
      runDetached(<String>['/bin/bash', '-lc', '/root/.microos/start-gui.sh']);
    }

    if (!_displayRequested || restart) start();

    var up = await _waitForPort(6080, const Duration(seconds: 14));

    // A previous attempt may have died (or Xvfb lost a race with the socket).
    // Give it one clean restart before reporting failure to the UI.
    if (!up) {
      _appendLog('[microos] display bridge not up, restarting it once');
      start();
      up = await _waitForPort(6080, const Duration(seconds: 18));
    }
    return up;
  }

  Future<bool> _waitForPort(int port, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final socket = await Socket.connect('127.0.0.1', port,
            timeout: const Duration(seconds: 1));
        socket.destroy();
        return true;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    _appendLog('[microos] display bridge did not open port $port in time');
    return false;
  }

  /// Launches the desktop browser inside the guest.
  ///
  /// The heavy flags are applied inside `/usr/local/bin/microos-browse`, which
  /// picks Chromium when the distro ships a real .deb and falls back to Falkon
  /// (QtWebEngine, same Blink engine) when it does not.
  Future<void> launchBrowser({String? url, bool singleProcess = false}) async {
    if (!isReady) return;
    await ensureDisplay();
    runDetached(
      <String>['/bin/bash', '-lc', '/usr/local/bin/microos-browse "${url ?? ''}"'],
      extraEnv: <String, String>{
        if (singleProcess) 'MICROOS_SINGLE_PROCESS': '1',
      },
    );
  }

  // --------------------------------------------------------------- credentials

  /// Writes `~/.git-credentials` + `~/.gitconfig` straight into the rootfs so
  /// git (and therefore OpenCode) can push without an interactive prompt.
  Future<void> applyGitCredentials(String token, String login) async {
    if (!isReady) return;

    final credentials = File(p.join(rootfsPath, 'root/.git-credentials'));
    await credentials.writeAsString('https://$login:$token@github.com\n');
    await _chmod(credentials.path, '600');

    final gitconfig = File(p.join(rootfsPath, 'root/.gitconfig'));
    await gitconfig.writeAsString('''
[user]
\tname = $login
\temail = $login@users.noreply.github.com
[credential]
\thelper = store
[init]
\tdefaultBranch = main
[safe]
\tdirectory = *
''');
    await _chmod(gitconfig.path, '600');

    _appendLog('[microos] GitHub credentials stored for $login');
  }

  Future<void> clearGitCredentials() async {
    for (final name in <String>['root/.git-credentials']) {
      final file = File(p.join(rootfsPath, name));
      if (file.existsSync()) await file.delete();
    }
  }

  // --------------------------------------------------------------------- misc

  void _appendLog(String chunk) {
    if (chunk.isEmpty) return;

    for (final line in const LineSplitter().convert(chunk)) {
      final progressMatch = RegExp(r'^\[progress\]\s*(\d+)').firstMatch(line);
      if (progressMatch != null) {
        progress = (int.parse(progressMatch.group(1)!) / 100).clamp(0.0, 1.0);
        _notify();
        continue;
      }

      final stageMatch = RegExp(r'^\[stage\]\s*(.+)$').firstMatch(line);
      if (stageMatch != null) {
        stage = stageMatch.group(1)!;
        _notify();
        continue;
      }

      logLines.add(line);
    }

    if (logLines.length > 800) {
      logLines.removeRange(0, logLines.length - 800);
    }
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final pty in _background) {
      try {
        pty.kill();
      } catch (_) {
        // Already gone.
      }
    }
    super.dispose();
  }
}
