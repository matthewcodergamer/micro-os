import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small persisted preferences that are not sensitive (unlike the PAT, which
/// lives in the platform keystore).
class SettingsStore extends ChangeNotifier {
  static const _kSingleProcess = 'browser.single_process';
  static const _kInstalledAt = 'runtime.installed_at';\n  static const _kWallpaper = 'desktop.wallpaper';\n  static const _kCustomWallpaper = 'desktop.custom_wallpaper';

  bool singleProcessBrowser = false;
  String? installedAt;\n  String wallpaper = 'big_sur';\n  String? customWallpaperPath;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    singleProcessBrowser = prefs.getBool(_kSingleProcess) ?? false;
    installedAt = prefs.getString(_kInstalledAt);\n    wallpaper = prefs.getString(_kWallpaper) ?? 'big_sur';\n    customWallpaperPath = prefs.getString(_kCustomWallpaper);
    notifyListeners();
  }

  Future<void> setSingleProcessBrowser(bool value) async {
    singleProcessBrowser = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSingleProcess, value);
  }

  Future<void> setWallpaper(String value) async {\n    wallpaper = value;\n    notifyListeners();\n    final prefs = await SharedPreferences.getInstance();\n    await prefs.setString(_kWallpaper, value);\n  }\n\n  Future<void> setCustomWallpaperPath(String? value) async {\n    customWallpaperPath = value;\n    wallpaper = 'custom';\n    notifyListeners();\n    final prefs = await SharedPreferences.getInstance();\n    if (value == null) {\n      await prefs.remove(_kCustomWallpaper);\n    } else {\n      await prefs.setString(_kCustomWallpaper, value);\n      await prefs.setString(_kWallpaper, 'custom');\n    }\n  }\n\n  Future<void> markInstalled() async {
    installedAt = DateTime.now().toIso8601String();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kInstalledAt, installedAt!);
  }
}
