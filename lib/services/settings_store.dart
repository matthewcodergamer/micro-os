import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small persisted preferences that are not sensitive (unlike the PAT, which
/// lives in the platform keystore).
class SettingsStore extends ChangeNotifier {
  static const _kSingleProcess = 'browser.single_process';
  static const _kInstalledAt = 'runtime.installed_at';
  static const _kOpenCodeTheme = 'opencode.theme';
  static const _kTerminalFontSize = 'terminal.font_size';
  static const _kAutoReadOpenCode = 'tts.auto_read_opencode';

  bool singleProcessBrowser = false;
  String? installedAt;
  String openCodeTheme = 'light';
  double terminalFontSize = 13;
  bool autoReadOpenCode = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    singleProcessBrowser = prefs.getBool(_kSingleProcess) ?? false;
    installedAt = prefs.getString(_kInstalledAt);
    openCodeTheme = prefs.getString(_kOpenCodeTheme) ?? 'light';
    terminalFontSize = (prefs.getDouble(_kTerminalFontSize) ?? 13).clamp(10, 18).toDouble();
    autoReadOpenCode = prefs.getBool(_kAutoReadOpenCode) ?? false;
    notifyListeners();
  }

  Future<void> setSingleProcessBrowser(bool value) async {
    singleProcessBrowser = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSingleProcess, value);
  }

  Future<void> setTerminalFontSize(double value) async {
    terminalFontSize = value.clamp(10, 18).toDouble();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kTerminalFontSize, terminalFontSize);
  }

  Future<void> setAutoReadOpenCode(bool value) async {
    autoReadOpenCode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoReadOpenCode, value);
  }

  Future<void> setOpenCodeTheme(String value) async {
    openCodeTheme = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kOpenCodeTheme, value);
  }

  Future<void> markInstalled() async {
    installedAt = DateTime.now().toIso8601String();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kInstalledAt, installedAt!);
  }
}
