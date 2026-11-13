import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Controls the native Android foreground service that keeps MicroOS's app
/// process important while a PRoot session is active.
class BackgroundSession {
  static const MethodChannel _channel = MethodChannel('microos/session');

  static Future<bool> start() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('start') ?? false;
    } catch (error, stack) {
      debugPrint('[microos-session] start failed: $error\n$stack');
      return false;
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (error, stack) {
      debugPrint('[microos-session] stop failed: $error\n$stack');
    }
  }
}
