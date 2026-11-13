import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/terminal_profiles.dart';

/// Small persisted preferences that are not sensitive (unlike the PAT, which
/// lives in the platform keystore).
///
/// The lock-screen password is a cosmetic gate for the MicroOS shell only. It
/// is stored on this device and does not encrypt anything.
class SettingsStore extends ChangeNotifier {
  static const _kSingleProcess = 'browser.single_process';
  static const _kInstalledAt = 'runtime.installed_at';
  static const _kOpenCodeTheme = 'opencode.theme';
  static const _kTerminalFontSize = 'terminal.font_size';
  static const _kTerminalProfile = 'terminal.profile';
  static const _kAutoReadOpenCode = 'tts.auto_read_opencode';
  static const _kDockAutoHide = 'dock.auto_hide';
  static const _kUserName = 'user.name';
  static const _kLoginPassword = 'user.lock_password';

  bool singleProcessBrowser = false;
  String? installedAt;
  String openCodeTheme = 'light';
  double terminalFontSize = 13;
  String terminalProfile = kDefaultTerminalProfile;
  String userName = 'MicroOS User';
  String? loginPassword;
  bool autoReadOpenCode = false;
  bool dockAutoHide = true;

  bool get hasPassword => loginPassword != null && loginPassword!.isNotEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    singleProcessBrowser = prefs.getBool(_kSingleProcess) ?? false;
    installedAt = prefs.getString(_kInstalledAt);
    openCodeTheme = prefs.getString(_kOpenCodeTheme) ?? 'light';
    terminalFontSize =
        (prefs.getDouble(_kTerminalFontSize) ?? 13).clamp(10, 18).toDouble();
    terminalProfile =
        prefs.getString(_kTerminalProfile) ?? kDefaultTerminalProfile;
    userName = prefs.getString(_kUserName) ?? 'MicroOS User';
    loginPassword = prefs.getString(_kLoginPassword);
    autoReadOpenCode = prefs.getBool(_kAutoReadOpenCode) ?? false;
    dockAutoHide = prefs.getBool(_kDockAutoHide) ?? true;
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

  Future<void> setTerminalProfile(String value) async {
    terminalProfile = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTerminalProfile, value);
  }

  Future<void> setUserName(String value) async {
    final trimmed = value.trim();
    userName = trimmed.isEmpty ? 'MicroOS User' : trimmed;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUserName, userName);
  }

  Future<void> setLoginPassword(String? value) async {
    final next = (value == null || value.isEmpty) ? null : value;
    loginPassword = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (next == null) {
      await prefs.remove(_kLoginPassword);
    } else {
      await prefs.setString(_kLoginPassword, next);
    }
  }

  Future<void> setDockAutoHide(bool value) async {
    dockAutoHide = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDockAutoHide, value);
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
