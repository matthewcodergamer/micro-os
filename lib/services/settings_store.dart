import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/terminal_profiles.dart';
import '../core/wallpapers.dart';

/// Stores ordinary UI settings separately from secrets.
///
/// The optional lock-screen password uses Android encrypted storage backed by
/// the platform keystore. It gates the Misty OS shell only; it does not encrypt
/// Linux files or replace Android device authentication.
class SettingsStore extends ChangeNotifier {
  static const _kSingleProcess = 'browser.single_process';
  static const _kBrowserEngine = 'browser.engine';
  static const _kBrowserHomePage = 'browser.home_page';
  static const _kInstalledAt = 'runtime.installed_at';
  static const _kOpenCodeTheme = 'opencode.theme';
  static const _kTerminalFontSize = 'terminal.font_size';
  static const _kTerminalProfile = 'terminal.profile';
  static const _kDockAutoHide = 'dock.auto_hide';
  static const _kDockScale = 'dock.scale';
  static const _kDockMagnification = 'dock.magnification';
  static const _kSystemBarsVisible = 'system.bars_visible';
  static const _kUserName = 'user.name';
  static const _kLoginPassword = 'user.lock_password';
  static const _kWallpaper = 'desktop.wallpaper';
  static const _kAccentColor = 'appearance.accent_color';
  static const _kDisplayResolution = 'display.resolution';
  static const _kScreenBrightness = 'display.brightness';
  static const _kTrackpadMode = 'desktop.trackpad_mode';
  static const _kTrackpadSpeed = 'desktop.trackpad_speed';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  bool singleProcessBrowser = false;
  String browserEngine = 'chromium';
  String browserHomePage = 'https://www.google.com';
  String? installedAt;
  String openCodeTheme = 'light';
  double terminalFontSize = 13;
  String terminalProfile = kDefaultTerminalProfile;
  String userName = 'Misty OS User';
  String wallpaper = kDefaultWallpaperId;
  int accentColorValue = 0xFF0A84FF;
  String displayResolution = '1280x720';
  double screenBrightness = 0.75;
  bool screenBrightnessConfigured = false;
  Color get accentColor => Color(accentColorValue);
  String? loginPassword;
  bool loginPasswordStorageUnavailable = false;
  bool loginPasswordMigrationPending = false;
  bool dockAutoHide = true;
  double dockScale = 1.0;
  bool dockMagnification = true;
  bool systemBarsVisible = false;
  bool trackpadMode = true;
  double trackpadSpeed = 1.35;

  bool get hasPassword =>
      loginPasswordStorageUnavailable ||
      (loginPassword != null && loginPassword!.isNotEmpty);

  /// Asset path for the selected desktop wallpaper.
  String get wallpaperAsset => wallpaperAssetFor(wallpaper);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    singleProcessBrowser = prefs.getBool(_kSingleProcess) ?? false;
    browserEngine = prefs.getString(_kBrowserEngine) == 'firefox' ? 'firefox' : 'chromium';
    browserHomePage = _validHomePage(prefs.getString(_kBrowserHomePage)) ?? 'https://www.google.com';
    installedAt = prefs.getString(_kInstalledAt);
    openCodeTheme = prefs.getString(_kOpenCodeTheme) ?? 'light';
    terminalFontSize =
        (prefs.getDouble(_kTerminalFontSize) ?? 13).clamp(10, 18).toDouble();
    terminalProfile =
        prefs.getString(_kTerminalProfile) ?? kDefaultTerminalProfile;
    userName = prefs.getString(_kUserName) ?? 'Misty OS User';
    dockAutoHide = prefs.getBool(_kDockAutoHide) ?? true;
    dockScale = (prefs.getDouble(_kDockScale) ?? 1.0).clamp(0.8, 1.2).toDouble();
    dockMagnification = prefs.getBool(_kDockMagnification) ?? true;
    systemBarsVisible = prefs.getBool(_kSystemBarsVisible) ?? false;
    wallpaper = prefs.getString(_kWallpaper) ?? kDefaultWallpaperId;
    accentColorValue = prefs.getInt(_kAccentColor) ?? 0xFF0A84FF;
    final savedResolution = prefs.getString(_kDisplayResolution) ?? '1280x720';
    displayResolution = const {'1024x768', '1280x720', '1600x900', '1920x1080'}.contains(savedResolution) ? savedResolution : '1280x720';
    screenBrightnessConfigured = prefs.containsKey(_kScreenBrightness);
    screenBrightness = (prefs.getDouble(_kScreenBrightness) ?? 0.75).clamp(0.05, 1.0).toDouble();
    trackpadMode = prefs.getBool(_kTrackpadMode) ?? true;
    trackpadSpeed = (prefs.getDouble(_kTrackpadSpeed) ?? 1.35).clamp(0.7, 2.2).toDouble();

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

  String? _validHomePage(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasAuthority || !{'http', 'https'}.contains(uri.scheme.toLowerCase())) return null;
    return uri.toString();
  }

  Future<void> setBrowserEngine(String value) async {
    browserEngine = value == 'firefox' ? 'firefox' : 'chromium';
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBrowserEngine, browserEngine);
  }

  Future<void> setBrowserHomePage(String value) async {
    final next = _validHomePage(value);
    if (next == null) throw ArgumentError('Enter a valid http or https URL.');
    browserHomePage = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBrowserHomePage, next);
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

  Future<void> setDockMagnification(bool value) async {
    dockMagnification = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDockMagnification, value);
  }

  Future<void> setDockScale(double value) async {
    dockScale = value.clamp(0.8, 1.2).toDouble();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kDockScale, dockScale);
  }

  Future<void> setDockAutoHide(bool value) async {
    dockAutoHide = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDockAutoHide, value);
  }

  Future<void> setOpenCodeTheme(String value) async {
    openCodeTheme = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kOpenCodeTheme, value);
  }

  Future<void> setScreenBrightness(double value) async {
    screenBrightness = value.clamp(0.05, 1.0).toDouble();
    screenBrightnessConfigured = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kScreenBrightness, screenBrightness);
  }

  Future<void> setDisplayResolution(String value) async {
    const supported = {'1024x768', '1280x720', '1600x900', '1920x1080'};
    if (!supported.contains(value)) throw ArgumentError('Unsupported display resolution.');
    displayResolution = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDisplayResolution, value);
  }

  Future<void> setAccentColor(int value) async {
    accentColorValue = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kAccentColor, value);
  }

  Future<void> setWallpaper(String value) async {
    wallpaper = wallpaperById(value).id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kWallpaper, wallpaper);
  }

  Future<void> setTrackpadMode(bool value) async {
    trackpadMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTrackpadMode, value);
  }

  Future<void> setTrackpadSpeed(double value) async {
    trackpadSpeed = value.clamp(0.7, 2.2).toDouble();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kTrackpadSpeed, trackpadSpeed);
  }

  Future<void> markInstalled() async {
    installedAt = DateTime.now().toIso8601String();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kInstalledAt, installedAt!);
  }
}
