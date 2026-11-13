import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/terminal_profiles.dart';

/// Stores ordinary UI settings separately from secrets.
///
/// The optional lock-screen password uses Android encrypted storage backed by
/// the platform keystore. It gates the MicroOS shell only; it does not encrypt
/// Linux files or replace Android device authentication.
class SettingsStore extends ChangeNotifier {
  static const _kSingleProcess = 'browser.single_process';
  static const _kInstalledAt = 'runtime.installed_at';
  static const _kOpenCodeTheme = 'opencode.theme';
  static const _kTerminalFontSize = 'terminal.font_size';
  static const _kTerminalProfile = 'terminal.profile';
  static const _kAutoReadOpenCode = 'tts.auto_read_opencode';
  static const _kDockAutoHide = 'dock.auto_hide';
  static const _kSystemBarsVisible = 'system.bars_visible';
  static const _kUserName = 'user.name';
  static const _kLoginPassword = 'user.lock_password';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  bool singleProcessBrowser = false;
  String? installedAt;
  String openCodeTheme = 'light';
  double terminalFontSize = 13;
  String terminalProfile = kDefaultTerminalProfile;
  String userName = 'MicroOS User';
  String? loginPassword;
  bool loginPasswordStorageUnavailable = false;
  bool loginPasswordMigrationPending = false;
  bool autoReadOpenCode = false;
  bool dockAutoHide = true;
  bool systemBarsVisible = false;

  bool get hasPassword =>
      loginPasswordStorageUnavailable ||
      (loginPassword != null && loginPassword!.isNotEmpty);

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
    autoReadOpenCode = prefs.getBool(_kAutoReadOpenCode) ?? false;
    dockAutoHide = prefs.getBool(_kDockAutoHide) ?? true;
    systemBarsVisible = prefs.getBool(_kSystemBarsVisible) ?? false;

    // Migrate older installations that kept the password in plain preferences.
    final legacyPassword = prefs.getString(_kLoginPassword);
    try {
      final securePassword = await _secureStorage.read(key: _kLoginPassword);
      loginPasswordStorageUnavailable = false;
      if (securePassword != null) {
        loginPassword = securePassword;
        if (legacyPassword != null) {
          try {
            await prefs.remove(_kLoginPassword);
          } catch (_) {
            loginPasswordMigrationPending = true;
          }
        }
      } else if (legacyPassword != null) {
        loginPassword = legacyPassword;
        try {
          await _secureStorage.write(
            key: _kLoginPassword,
            value: legacyPassword,
          );
          await prefs.remove(_kLoginPassword);
          loginPasswordMigrationPending = false;
        } catch (_) {
          loginPasswordMigrationPending = true;
        }
      } else {
        loginPassword = null;
      }
    } catch (_) {
      // Fail closed if the secure password may exist but the keystore cannot
      // be read. A legacy password remains usable while migration is pending.
      loginPassword = legacyPassword;
      loginPasswordStorageUnavailable = legacyPassword == null;
      loginPasswordMigrationPending = legacyPassword != null;
    }
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
    final prefs = await SharedPreferences.getInstance();
    if (next == null) {
      await _secureStorage.delete(key: _kLoginPassword);
      await prefs.remove(_kLoginPassword);
    } else {
      // Write the encrypted value first, then remove any legacy plaintext copy.
      await _secureStorage.write(key: _kLoginPassword, value: next);
      await prefs.remove(_kLoginPassword);
    }
    loginPassword = next;
    loginPasswordStorageUnavailable = false;
    loginPasswordMigrationPending = false;
    notifyListeners();
  }

  Future<void> setSystemBarsVisible(bool value) async {
    systemBarsVisible = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSystemBarsVisible, value);
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
