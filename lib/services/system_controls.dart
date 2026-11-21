import 'package:flutter/services.dart';

/// Native Android controls for the MicroOS app window and media stream.
/// Brightness is scoped to this app's window; volume uses Android's media stream.
class SystemControls {
  SystemControls._();

  static const MethodChannel _channel = MethodChannel('microos/system_controls');

  static Future<Map<String, double>> getState() async {
    final values = await _channel.invokeMapMethod<String, dynamic>('getState') ?? const {};
    return <String, double>{
      'brightness': (values['brightness'] as num?)?.toDouble() ?? 0.75,
      'volume': (values['volume'] as num?)?.toDouble() ?? 0.5,
    };
  }

  static Future<void> openNetworkSettings() async {
    await _channel.invokeMethod<bool>('openNetworkSettings');
  }

  static Future<double> setBrightness(double value) async {
    final applied = await _channel.invokeMethod<num>(
      'setBrightness',
      <String, double>{'value': value.clamp(0.05, 1.0).toDouble()},
    );
    return (applied ?? value).toDouble();
  }

  static Future<double> setVolume(double value) async {
    final applied = await _channel.invokeMethod<num>(
      'setVolume',
      <String, double>{'value': value.clamp(0.0, 1.0).toDouble()},
    );
    return (applied ?? value).toDouble();
  }
}
