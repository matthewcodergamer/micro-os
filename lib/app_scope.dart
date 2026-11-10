import 'package:flutter/widgets.dart';

import 'services/github_auth.dart';
import 'services/linux_runtime.dart';
import 'services/settings_store.dart';
import 'services/system_stats.dart';
import 'state/desktop_state.dart';

/// Lightweight dependency holder. The app has exactly one of each service, so a
/// full provider package would be overkill.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.runtime,
    required this.desktop,
    required this.stats,
    required this.auth,
    required this.settings,
    required super.child,
  });

  final LinuxRuntime runtime;
  final DesktopState desktop;
  final SystemStats stats;
  final GithubAuth auth;
  final SettingsStore settings;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}
