import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:zstd_dart/zstd_dart.dart';

import 'background_session.dart';

enum RuntimeStatus { checking, missing, installing, ready, failed }

/// Owns the Linux guest: unpacks the bundled, pre-provisioned rootfs and
/// launches processes through proot. Legacy images retain a setup fallback.
///
/// Everything the UI needs is exposed as plain Dart calls so the window manager
/// never has to know whether it is talking to a local proot guest or (later) a
/// remote host.
class LinuxRuntime extends ChangeNotifier {
  static const String _rootfsAsset = 'flutter_assets/assets/rootfs/rootfs.tar.zst';
  static const int _rootfsChunkBytes = 8 * 1024 * 1024;
  static const MethodChannel _rootfsChannel = MethodChannel('microos/rootfs');
  static const String _setupAsset = 'tool/setup.sh';
  static const String _readyMarker = 'root/.microos/ready';
  // Bump this whenever the bundled Linux image changes. It forces upgrades to
  // replace an older extracted rootfs instead of silently reusing stale files.
  static const String _rootfsVersion = '8';
  static const String _imageVersionPath = 'root/.microos/image-version';

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
  final Set<Pty> _activePtys = <Pty>{};
  Future<void>? _backgroundServiceStart;
  bool _backgroundServiceActive = false;

  Directory? _base;
  bool _displayRequested = false;
  bool _torrentStartRequested = false;
  bool _provisioningFinished = false;
  bool _disposed = false;
  String? _githubToken;
  String? _huggingFaceToken;

  bool get isReady => status == RuntimeStatus.ready;
  bool get isBusy => status == RuntimeStatus.installing;
  bool get hasActiveSession => _activePtys.isNotEmpty;
  bool get canContinueManually =>
      _provisioningFinished &&
      File(p.join(rootfsPath, 'etc/os-release')).existsSync() &&
      File(prootPath).existsSync();

  /// Allows access to the desktop after provisioning has exited, even if a
  /// non-critical package failed. The user explicitly chooses this fallback.
  bool continueToDesktop() {
    if (!canContinueManually) return false;
    status = RuntimeStatus.ready;
    stage = 'Linux ready (continued manually)';
    progress = 1;
    error = null;
    _notify();
    return true;
  }

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

  bool get _hasCurrentImage {
    final versionFile = File(p.join(rootfsPath, _imageVersionPath));
    return File(_readyPath).existsSync() &&
        versionFile.existsSync() &&
        versionFile.readAsStringSync().trim() == _rootfsVersion;
  }

  /// Environment handed to every proot invocation.
  Map<String, String> get _prootEnv => <String, String>{
        'PROOT_LOADER': p.join(base.path, 'proot', 'loader'),
        'PROOT_TMP_DIR': p.join(base.path, 'tmp'),
        'PROOT_NO_SECCOMP': '1',
        'LD_LIBRARY_PATH': p.join(base.path, 'proot'),
        'HOME': '/root',
        'TERM': 'xterm-256color',
        'LANG': 'en_US.UTF-8',
        'LC_ALL': 'en_US.UTF-8',
        'DISPLAY': ':1',
        'PATH': '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:'
            '/root/.opencode/bin:/root/.local/bin',
        if (_githubToken != null && _githubToken!.isNotEmpty) ...<String, String>{
          'GH_TOKEN': _githubToken!,
          'GITHUB_TOKEN': _githubToken!,
        },
        if (_huggingFaceToken != null && _huggingFaceToken!.isNotEmpty)
          'HF_TOKEN': _huggingFaceToken!,
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

      status = _hasCurrentImage ? RuntimeStatus.ready : RuntimeStatus.missing;
      stage = status == RuntimeStatus.ready
          ? 'Pre-baked Linux ready'
          : 'Pre-baked workstation needs unpacking';
      progress = status == RuntimeStatus.ready ? 1 : 0;
      if (status == RuntimeStatus.ready) {
        await _refreshGuestDns();
        await ensureTorrentService();
      }
    } catch (e) {
      status = RuntimeStatus.failed;
      error = '$e';
    }
    _notify();
  }

  Future<void> _refreshGuestDns() async {
    try {
      final result = await Process.run(
        prootPath,
        _prootArgs(<String>[
          '/bin/bash',
          '-lc',
          "printf 'nameserver 8.8.8.8\\nnameserver 1.1.1.1\\n' > /etc/resolv.conf",
        ]),
        environment: _prootEnv,
      );
      if (result.exitCode != 0) {
        _appendLog('[microos] DNS refresh failed: ${result.stderr}');
      } else {
        _appendLog('[microos] guest DNS refreshed (8.8.8.8, 1.1.1.1)');
      }
    } catch (e) {
      _appendLog('[microos] DNS refresh could not run: $e');
    }
  }

  Future<void> install() async {
    if (isBusy || !Platform.isAndroid) return;

    status = RuntimeStatus.installing;
    _provisioningFinished = false;
    error = null;
    logLines.clear();
    progress = 0.01;
    stage = 'Preparing storage';
    _notify();

    try {
      await _extractProot();

      progress = 0.08;
      stage = 'Unpacking pre-baked Ubuntu workstation';
      _notify();
      await _extractRootfs();

      if (_hasCurrentImage) {
        // The APK already contains Firefox, OpenCode and the complete toolchain.
        // Do not run apt or download packages on the phone during first launch.
        progress = 0.95;
        stage = 'Finalising pre-baked workstation';
        _notify();
        await _refreshGuestDns();
        status = RuntimeStatus.ready;
        progress = 1;
        stage = 'Pre-baked Linux ready';
        await ensureTorrentService();
      } else {
        // Compatibility path for an older development image without a
        // recognised pre-bake marker.
        progress = 0.55;
        stage = 'Completing legacy Linux setup';
        _notify();
        await _installSetupScript();
        await _runProvisioning();
        if (File(_readyPath).existsSync()) {
          status = RuntimeStatus.ready;
          progress = 1;
          stage = 'Linux ready';
        } else {
          status = RuntimeStatus.failed;
          error = 'Linux setup stopped before it finished. Check the log below.';
        }
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
    if (target.existsSync()) await target.delete(recursive: true);
    await target.create(recursive: true);

    final archive = File(p.join(base.path, 'rootfs.tar.zst'));
    if (archive.existsSync()) await archive.delete();
    if (!archive.existsSync() || archive.lengthSync() < 1024 * 1024) {
      // AssetManager copies the compressed asset on a native worker thread.
      // Never materialize the multi-hundred-megabyte asset in the Dart heap.
      await _rootfsChannel.invokeMethod<int>('copyAssetToFile', <String, Object>{
        'assetPath': _rootfsAsset,
        'destinationPath': archive.path,
      });
    }

    await _extractZstdWithSystemTar(archive.path, target.path);
    if (!File(p.join(rootfsPath, 'etc/os-release')).existsSync()) {
      throw StateError('rootfs extraction produced no /etc/os-release');
    }

    try {
      await archive.delete();
    } catch (_) {
      // Not fatal; the next install can reuse or replace this cached archive.
    }
  }

  /// Decompress zstd in bounded 8 MiB chunks and pipe tar directly into
  /// Android tar. Neither the compressed asset nor the expanded tar is loaded
  /// wholesale into memory or written as a second giant temporary file.
  Future<void> _extractZstdWithSystemTar(
    String archivePath,
    String destination,
  ) async {
    final tar = await Process.start(
      '/system/bin/tar',
      <String>['-x', '-f', '-', '-C', destination],
    );
    final stderrText = StringBuffer();
    final stderrSubscription =
        tar.stderr.transform(utf8.decoder).listen(stderrText.write);
    final stdoutSubscription = tar.stdout.listen((_) {});
    final decoder = ZstdStreamDecoder(
      maxDecompressedMessageSize: 128 * 1024 * 1024,
    );
    RandomAccessFile? input;

    try {
      input = await File(archivePath).open();
      final buffer = Uint8List(_rootfsChunkBytes);
      while (true) {
        final count = await input.readInto(buffer);
        if (count == 0) break;

        final decoded = decoder.feed(Uint8List.sublistView(buffer, 0, count));
        if (decoded.isNotEmpty) {
          tar.stdin.add(decoded);
          // Flush each chunk to apply back-pressure to the decoder.
          await tar.stdin.flush();
        }
      }

      decoder.finish();
      if (!decoder.isFrameComplete) {
        throw StateError('The zstd rootfs archive ended before its frame completed');
      }

      await tar.stdin.close();
      final exitCode = await tar.exitCode;
      if (exitCode != 0) {
        throw StateError(
          'Android tar exited with code $exitCode: ${stderrText.toString()}',
        );
      }
    } catch (_) {
      try {
        await tar.stdin.close();
      } catch (_) {}
      tar.kill();
      rethrow;
    } finally {
      await input?.close();
      decoder.dispose();
      await stderrSubscription.cancel();
      await stdoutSubscription.cancel();
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

  Future<void> _ensureBackgroundSession() {
    if (!Platform.isAndroid || _backgroundServiceActive) {
      return Future<void>.value();
    }
    return _backgroundServiceStart ??= BackgroundSession.start().then((started) {
      _backgroundServiceActive = started;
      if (!started) {
        _appendLog('[microos] Android foreground service did not start; background protection is unavailable');
      }
    }).whenComplete(() {
      _backgroundServiceStart = null;
    });
  }

  void _trackPty(Pty pty) {
    _activePtys.add(pty);
    unawaited(
      pty.exitCode.then<void>((code) {
        _activePtys.remove(pty);
        _background.remove(pty);
        _appendLog('[microos] Linux process exited with code $code');
      }).catchError((Object error) {
        _activePtys.remove(pty);
        _background.remove(pty);
        _appendLog('[microos] Linux process monitor error: $error');
      }),
    );
  }

  /// Starts an interactive shell (or [argv]) inside the guest.
  Pty startShell({List<String>? argv}) {
    unawaited(_ensureBackgroundSession());
    final pty = Pty.start(
      prootPath,
      arguments: _prootArgs(argv ?? <String>['/bin/bash', '-l']),
      environment: _prootEnv,
    );
    _trackPty(pty);
    return pty;
  }

  /// Stops every PTY owned by this runtime and removes the foreground-service
  /// notification. This is an explicit user-requested shutdown, not app pause.
  Future<void> stopSession() async {
    final pendingStart = _backgroundServiceStart;
    if (pendingStart != null) await pendingStart;
    for (final pty in _activePtys.toList()) {
      try {
        pty.kill();
      } catch (_) {
        // The process may already have exited.
      }
    }
    _activePtys.clear();
    _background.clear();
    _displayRequested = false;
    _torrentStartRequested = false;
    await BackgroundSession.stop();
    _backgroundServiceActive = false;
    _appendLog('[microos] Linux session stopped by user');
  }

  /// Fire-and-forget process inside the guest (window manager, browser...).
  Pty runDetached(List<String> argv, {Map<String, String> extraEnv = const {}}) {
    unawaited(_ensureBackgroundSession());
    final pty = Pty.start(
      prootPath,
      arguments: _prootArgs(argv),
      environment: <String, String>{..._prootEnv, ...extraEnv},
    );
    _background.add(pty);
    _trackPty(pty);
    pty.output.listen(
      (data) => _appendLog(utf8.decode(data, allowMalformed: true)),
      onDone: () => _background.remove(pty),
    );
    return pty;
  }

  /// Starts qBittorrent-nox. The WebUI is bound to loopback only.
  Future<bool> ensureTorrentService() async {
    if (!isReady) return false;
    if (await _isPortOpen(8080)) return true;
    if (!_torrentStartRequested) {
      _torrentStartRequested = true;
      runDetached(<String>['/bin/bash', '-lc', '/root/.microos/start-torrent.sh']);
    }
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      if (await _isPortOpen(8080)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    _appendLog('[microos] qBittorrent WebUI did not open on 127.0.0.1:8080; inspect /tmp/microos-qbittorrent.log');
    return false;
  }

  /// Boots the complete X11/VNC/noVNC chain. A listening HTTP bridge is
  /// not sufficient: noVNC is unusable unless the RFB server on 5900 is alive.
  Future<bool> ensureDisplay({bool restart = false}) async {
    if (!isReady) return false;
    await _ensureBackgroundSession();

    void start() {
      _displayRequested = true;
      runDetached(<String>['/bin/bash', '-lc', '/root/.microos/start-desktop.sh']);
    }

    if (!_displayRequested || restart) start();

    var up = await _waitForDisplay(const Duration(seconds: 18));
    if (!up) {
      _appendLog('[microos] display health check failed (5900/6080); restarting X11 stack once');
      start();
      up = await _waitForDisplay(const Duration(seconds: 22));
    }
    if (!up) {
      _appendLog('[microos] DISPLAY NOT READY: require both VNC 5900 and noVNC 6080');
    }
    return up;
  }

  Future<bool> _waitForDisplay(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final vnc = await _isPortOpen(5900);
      final bridge = vnc && await _isPortOpen(6080);
      if (vnc && bridge) return true;
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    return false;
  }

  Future<bool> _isPortOpen(int port) async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 700),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Launches the desktop browser inside the guest.
  ///
  /// The heavy flags are applied inside `/usr/local/bin/microos-browse`, which
  /// picks Chromium when the distro ships a real .deb and falls back to Falkon
  /// (QtWebEngine, same Blink engine) when it does not.
  Future<void> launchBrowser({
    String? url,
    String browser = 'chromium',
    bool singleProcess = false,
  }) async {
    if (!isReady) return;
    if (browser != 'chromium' && browser != 'firefox') {
      throw ArgumentError.value(browser, 'browser', 'Use chromium or firefox');
    }
    final displayUp = await ensureDisplay();
    if (!displayUp) {
      _appendLog('[microos] browser launch blocked: the X11/VNC display is not healthy');
      return;
    }
    final requestedUrl = (url ?? '').trim();
    final normalizedUrl = requestedUrl.isEmpty
        ? 'https://www.google.com'
        : (requestedUrl.contains('://') || requestedUrl.startsWith('about:')
            ? requestedUrl
            : 'https://$requestedUrl');
    final parsedUrl = Uri.tryParse(normalizedUrl);
    if (parsedUrl == null ||
        (!const <String>['http', 'https', 'about'].contains(parsedUrl.scheme))) {
      throw ArgumentError.value(url, 'url', 'Only http, https, or about URLs are supported');
    }
    final launcher = browser == 'firefox'
        ? '/usr/local/bin/start-firefox.sh'
        : '/usr/local/bin/microos-browse';
    runDetached(
      <String>[
        '/bin/bash',
        '-lc',
        '$launcher ${_shellQuote(normalizedUrl)}',
      ],
      extraEnv: <String, String>{
        if (singleProcess) 'MICROOS_SINGLE_PROCESS': '1',
      },
    );
  }

  String _shellQuote(String value) => "'${value.replaceAll("'", "'\\"'\\"'")}'";

  /// Attempts to repair interrupted dpkg configuration and broken dependencies.
  /// Output is streamed into the same diagnostic log shown in Settings.
  Future<int> repairPackages() async {
    if (!isReady || isBusy) return -1;
    _appendLog('[microos] starting package repair');
    final pty = Pty.start(
      prootPath,
      arguments: _prootArgs(<String>[
        '/bin/bash', '-lc',
        'dpkg --configure -a && apt-get install -f -y',
      ]),
      environment: _prootEnv,
    );
    pty.output.listen((data) => _appendLog(utf8.decode(data, allowMalformed: true)));
    final code = await pty.exitCode;
    _appendLog('[microos] package repair exited with code $code');
    return code;
  }

  // --------------------------------------------------------------- credentials

  /// Keeps tokens in Android Keystore-backed storage and passes them to guest
  /// processes at launch. Never writes a PAT into .git-credentials or shell files.
  void setGithubToken(String? token) {
    _githubToken = token?.trim().isEmpty == true ? null : token?.trim();
  }

  void setHuggingFaceToken(String? token) {
    _huggingFaceToken = token?.trim().isEmpty == true ? null : token?.trim();
  }

  Future<void> applyGitCredentials(String token, String login) async {
    _githubToken = token;
    if (!isReady) return;

    final legacyCredentials = File(p.join(rootfsPath, 'root/.git-credentials'));
    if (legacyCredentials.existsSync()) await legacyCredentials.delete();

    final gitconfig = File(p.join(rootfsPath, 'root/.gitconfig'));
    await gitconfig.writeAsString('''
[user]
\tname = $login
\temail = $login@users.noreply.github.com
[credential]
\thelper = !gh auth git-credential
[init]
\tdefaultBranch = main
[safe]
\tdirectory = *
''');
    await _chmod(gitconfig.path, '600');
    _appendLog('[microos] GitHub credential helper configured for $login (token not written to disk)');
  }

  Future<void> clearGitCredentials() async {
    _githubToken = null;
    for (final name in <String>['root/.git-credentials', 'root/.gitconfig']) {
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
    for (final pty in _activePtys.toList()) {
      try {
        pty.kill();
      } catch (_) {
        // Already gone.
      }
    }
    _activePtys.clear();
    _background.clear();
    unawaited(BackgroundSession.stop());
    super.dispose();
  }
}
