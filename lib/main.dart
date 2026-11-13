import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_scope.dart';
import 'core/theme.dart';
import 'services/github_auth.dart';
import 'services/linux_runtime.dart';
import 'services/opencode_tts_server.dart';
import 'services/settings_store.dart';
import 'services/system_stats.dart';
import 'state/desktop_state.dart';
import 'ui/desktop_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A desktop should own the whole screen, including the gesture areas.
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.black,
    ),
  );

  final runtime = LinuxRuntime();
  final stats = SystemStats();
  final auth = GithubAuth();
  final settings = SettingsStore();
  final ttsServer = OpenCodeTtsServer();

  await ttsServer.start();
  await settings.load();
  await runtime.init();
  final githubToken = await auth.readToken();
  final githubLogin = await auth.readLogin();
  final huggingFaceToken = await auth.readHuggingFaceToken();
  runtime.setGithubToken(githubToken);
  runtime.setHuggingFaceToken(huggingFaceToken);
  if (githubToken != null && githubLogin != null && runtime.isReady) {
    await runtime.applyGitCredentials(githubToken, githubLogin);
  }
  unawaited(stats.start());

  runApp(
    MicroOSApp(
      runtime: runtime,
      stats: stats,
      auth: auth,
      settings: settings,
      ttsServer: ttsServer,
    ),
  );
}

class MicroOSApp extends StatefulWidget {
  const MicroOSApp({
    super.key,
    required this.runtime,
    required this.stats,
    required this.auth,
    required this.settings,
    required this.ttsServer,
  });

  final LinuxRuntime runtime;
  final SystemStats stats;
  final GithubAuth auth;
  final SettingsStore settings;
  final OpenCodeTtsServer ttsServer;

  @override
  State<MicroOSApp> createState() => _MicroOSAppState();
}

class _MicroOSAppState extends State<MicroOSApp> {
  late final DesktopState _desktop;

  @override
  void initState() {
    super.initState();
    _desktop = DesktopState(widget.runtime);
  }

  @override
  void dispose() {
    _desktop.dispose();
    widget.stats.dispose();
    widget.runtime.dispose();
    widget.ttsServer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      runtime: widget.runtime,
      desktop: _desktop,
      stats: widget.stats,
      auth: widget.auth,
      settings: widget.settings,
      child: MaterialApp(
        title: 'MicroOS',
        debugShowCheckedModeBanner: false,
        theme: buildMicroTheme(),
        builder: (context, child) {
          final media = MediaQuery.of(context);
          // Keep the desktop chrome from exploding on phones with huge
          // accessibility font settings.
          final scale = media.textScaler.scale(1.0).clamp(0.9, 1.15).toDouble();
          return MediaQuery(
            data: media.copyWith(textScaler: TextScaler.linear(scale)),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const DesktopScreen(),
      ),
    );
  }
}
