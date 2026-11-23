import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/desktop_input.dart';
import '../core/terminal_profiles.dart';
import '../core/wallpapers.dart';

/// Stores ordinary UI settings separately from secrets.
///
/// The optional lock-screen password uses Android encrypted storage backed by
/// the platform keystore. It gates the Misty OS shell only; it does not encrypt
/// Linux files or replace Android device authentication.
class SettingsStore extends ChangeNotifier {
  static const _kSingleProcess = 'browser.single_process';
  static const _kInstalledAt = 'runtime.installed_at';
  static const _kOpenCodeTheme = 'opencode.theme';
  static const _kTerminalFontSize = 'terminal.font_size';
  static const _kTerminalProfile = 'terminal.profile';
  static const _kDockAutoHide = 'dock.auto_hide';
  static const _kDockVisibility = 'dock.visibility';
  static const _kSystemBarsVisible = 'system.bars_visible';
  static const _kUserName = 'user.name';
  static const _kLoginPassword = 'user.lock_password';
  static const _kWallpaper = 'desktop.wallpaper';
  static const _kDesktopPointerMode = 'desktop.pointer_mode';
  static const _kDesktopCursorSpeed = 'desktop.cursor_speed';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  bool singleProcessBrowser = false;
  String? installedAt;
  String openCodeTheme = 'light';
  double terminalFontSize = 13;
  String terminalProfile = kDefaultTerminalProfile;
  String userName = 'Misty OS User';
  String wallpaper = kDefaultWallpaperId;
  String? loginPassword;
  bool loginPasswordStorageUnavailable = false;
  bool loginPasswordMigrationPending = false;
  bool systemBarsVisible = false;
  DockVisibilityMode dockVisibilityMode = DockVisibilityMode.automatic;
  DesktopPointerMode desktopPointerMode = DesktopPointerMode.trackpad;
  double desktopCursorSpeed = 1.35;

  bool get hasPassword =>
      loginPasswordStorageUnavailable ||
      (loginPassword != null && loginPassword!.isNotEmpty);

  /// Asset path for the selected desktop wallpaper.
  String get wallpaperAsset => wallpaperAssetFor(wallpaper);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    singleProcessBrowser = prefs.getBool(_kSingleProcess) ?? false;
    installedAt = prefs.getString(_kInstalledAt);
    openCodeTheme = prefs.getString(_kOpenCodeTheme) ?? 'light';
    terminalFontSize =
        (prefs.getDouble(_kTerminalFontSize) ?? 13).clamp(10, 18).toDouble();
    terminalProfile =
        prefs.getString(_kTerminalProfile) ?? kDefaultTerminalProfile;
    userName = prefs.getString(_kUserName) ?? 'Misty OS User';
    final storedDockVisibility = prefs.getString(_kDockVisibility);
    dockVisibilityMode = storedDockVisibility == null
        // Migrate the old boolean: auto-hide was on by default, so it maps to
        // Automatic (which keeps the Dock visible on desktop-size screens).
        ? (prefs.getBool(_kDockAutoHide) ?? true
              ? DockVisibilityMode.automatic
              : DockVisibilityMode.alwaysVisible)
        : DockVisibilityModeInfo.fromStorage(storedDockVisibility);
    systemBarsVisible = prefs.getBool(_kSystemBarsVisible) ?? false;
    wallpaper = prefs.getString(_kWallpaper) ?? kDefaultWallpaperId;
    desktopPointerMode = DesktopPointerModeInfo.fromStorage(
      prefs.getString(_kDesktopPointerMode),
    );
    desktopCursorSpeed =
        (prefs.getDouble(_kDesktopCursorSpeed) ?? 1.35).clamp(0.8, 2.0).toDouble();

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
    userName = trimmed.isEmpty ? 'Misty OS User' : trimmed;
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

  Future<void> setDockVisibilityMode(DockVisibilityMode value) async {
    if (dockVisibilityMode == value) return;
    dockVisibilityMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDockVisibility, value.storageValue);
  }

  Future<void> setOpenCodeTheme(String value) async {
    openCodeTheme = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kOpenCodeTheme, value);
  }

  Future<void> setWallpaper(String value) async {
    wallpaper = wallpaperById(value).id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kWallpaper, wallpaper);
  }

  Future<void> setDesktopPointerMode(DesktopPointerMode value) async {
    if (desktopPointerMode == value) return;
    desktopPointerMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDesktopPointerMode, value.storageValue);
  }

  Future<void> setDesktopCursorSpeed(double value) async {
    final next = value.clamp(0.8, 2.0).toDouble();
    if ((desktopCursorSpeed - next).abs() < 0.001) return;
    desktopCursorSpeed = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kDesktopCursorSpeed, desktopCursorSpeed);
  }

  Future<void> markInstalled() async {
    installedAt = DateTime.now().toIso8601String();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kInstalledAt, installedAt!);
  }
}
