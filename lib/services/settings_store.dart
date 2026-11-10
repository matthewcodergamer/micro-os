import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small persisted preferences that are not sensitive (unlike the PAT, which
/// lives in the platform keystore).
class SettingsStore extends ChangeNotifier {
  static const _kSingleProcess = 'browser.single_process';
  static const _kInstalledAt = 'runtime.installed_at';

  bool singleProcessBrowser = false;
  String? installedAt;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    singleProcessBrowser = prefs.getBool(_kSingleProcess) ?? false;
    installedAt = prefs.getString(_kInstalledAt);
    notifyListeners();
  }

  Future<void> setSingleProcessBrowser(bool value) async {
    singleProcessBrowser = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSingleProcess, value);
  }

  Future<void> markInstalled() async {
    installedAt = DateTime.now().toIso8601String();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kInstalledAt, installedAt!);
  }
}
