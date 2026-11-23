import 'dart:io';

import 'package:flutter/services.dart';

/// Plays the Linux guest's PulseAudio output on Android.
///
/// The native side owns the AudioTrack and the Unix-socket reader; Flutter only
/// starts/stops it and changes volume. All audio is 48 kHz stereo PCM, so the
/// guest does not resample for the phone speaker or headphones.
class DesktopAudio {
  const DesktopAudio._();

  static const MethodChannel _channel = MethodChannel('microos/audio');
  static String? _socketPath;
  static bool _running = false;
  static double _volume = 1;

  static Future<void> start(String socketPath) async {
    if (!Platform.isAndroid || socketPath.isEmpty) return;
    if (_running && _socketPath == socketPath) return;
    try {
      await _channel.invokeMethod<void>('start', <String, Object>{
        'socketPath': socketPath,
      });
      _socketPath = socketPath;
      _running = true;
      await setVolume(_volume);
    } on PlatformException {
      _running = false;
    } on MissingPluginException {
      _running = false;
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    _running = false;
    _socketPath = null;
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // The audio worker is already gone.
    } on MissingPluginException {
      // Desktop audio is Android-only.
    }
  }

  static Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0).toDouble();
    if (!Platform.isAndroid || !_running) return;
    try {
      await _channel.invokeMethod<void>('setVolume', <String, Object>{
        'volume': _volume,
      });
    } on PlatformException {
      // Keep the requested volume; it is applied on the next reconnect.
    } on MissingPluginException {
      // Desktop audio is Android-only.
    }
  }

  static double get volume => _volume;
}
