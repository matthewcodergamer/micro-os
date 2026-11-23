import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/desktop_input.dart';

/// Status reported by the Android native X11 surface.
class NativeX11Status {
  const NativeX11Status({
    required this.connected,
    this.message,
    this.frameSize,
  });

  final bool connected;
  final String? message;
  final Size? frameSize;
}

/// Hosts Misty OS's own Android view for the native X11 desktop.
///
/// The Android side owns the Unix-socket connection to the guest bridge and
/// renders damaged X11 rectangles into a TextureView. Flutter sends keyboard,
/// pointer-profile and text commands over a method channel, so the desktop
/// chrome can stay entirely in Dart without embedding a WebView.
class NativeX11View extends StatefulWidget {
  const NativeX11View({
    super.key,
    required this.socketPath,
    required this.pointerMode,
    required this.cursorSpeed,
    this.onStatus,
    this.onThreeFingerTap,
  });

  final String socketPath;
  final DesktopPointerMode pointerMode;
  final double cursorSpeed;
  final ValueChanged<NativeX11Status>? onStatus;
  final VoidCallback? onThreeFingerTap;

  @override
  NativeX11ViewState createState() => NativeX11ViewState();
}

class NativeX11ViewState extends State<NativeX11View> {
  MethodChannel? _channel;
  bool _initialized = false;

  @override
  void didUpdateWidget(NativeX11View oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pointerMode != widget.pointerMode) {
      unawaited(_applyPointerMode());
    }
    if ((oldWidget.cursorSpeed - widget.cursorSpeed).abs() > 0.001) {
      unawaited(_applyCursorSpeed());
    }
  }

  @override
  void dispose() {
    unawaited(releaseAll());
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('microos/x11/$id');
    _channel = channel;
    channel.setMethodCallHandler(_onNativeMessage);
    _initialized = true;
    unawaited(_applyPointerMode());
    unawaited(_applyCursorSpeed());
  }

  Future<dynamic> _onNativeMessage(MethodCall call) async {
    switch (call.method) {
      case 'status':
        final arguments = call.arguments;
        final map = arguments is Map ? arguments : const <Object?, Object?>{};
        final state = map['state'];
        final width = map['width'];
        final height = map['height'];
        final message = map['message'];
        final frameSize = width is num && height is num
            ? Size(width.toDouble(), height.toDouble())
            : null;
        widget.onStatus?.call(
          NativeX11Status(
            connected: state == 'connected',
            message: message is String ? message : null,
            frameSize: frameSize,
          ),
        );
        break;
      case 'threeFingerTap':
        widget.onThreeFingerTap?.call();
        break;
    }
    return null;
  }

  Future<void> _applyPointerMode() {
    return _invoke('setPointerMode', <String, Object>{
      'mode': widget.pointerMode == DesktopPointerMode.direct
          ? 'direct'
          : 'trackpad',
    });
  }

  Future<void> _applyCursorSpeed() {
    return _invoke('setCursorSpeed', <String, Object>{
      'speed': widget.cursorSpeed,
    });
  }

  Future<void> _invoke(String method, [Object? arguments]) async {
    final channel = _channel;
    if (channel == null) return;
    try {
      await channel.invokeMethod<void>(method, arguments);
    } on PlatformException {
      // The surface can disappear while the desktop window is closing.
    } on MissingPluginException {
      // Desktop is only available on Android.
    }
  }

  Future<void> sendKey(int keysym, bool down) {
    return _invoke('sendKey', <String, Object>{
      'keysym': keysym,
      'down': down,
    });
  }

  Future<void> sendText(String text) {
    if (text.isEmpty) return Future<void>.value();
    return _invoke('sendText', <String, Object>{'text': text});
  }

  Future<void> rightClick() => _invoke('rightClick');

  Future<void> recenterCursor() => _invoke('recenterCursor');

  Future<void> showKeyboard() => _invoke('showKeyboard');

  Future<void> hideKeyboard() => _invoke('hideKeyboard');

  Future<void> releaseAll() => _invoke('releaseAll');

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return const ColoredBox(
        color: Color(0xFF0B0E14),
        child: Center(
          child: Text(
            'The native X11 desktop is available on Android.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      );
    }

    return AndroidView(
      viewType: 'microos/x11',
      creationParams: <String, Object>{
        'socketPath': widget.socketPath,
      },
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _onPlatformViewCreated,
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
      },
    );
  }

  /// True once the platform view has been attached. Kept for diagnostics.
  bool get isInitialized => _initialized;
}
