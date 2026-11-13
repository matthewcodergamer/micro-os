import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Loopback-only HTTP bridge used by the OpenCode plugin in the Linux guest.
class OpenCodeTtsServer {
  static const int port = 17842;

  final FlutterTts _tts = FlutterTts();
  HttpServer? _server;
  Future<void> _speechQueue = Future<void>.value();

  Future<void> start() async {
    if (!Platform.isAndroid || _server != null) return;
    try {
      _server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: true,
      );
      _server!.listen(
        _handleRequest,
        onError: (Object error, StackTrace stack) {
          debugPrint('[microos-tts] HTTP listener error: $error');
        },
      );
      debugPrint('[microos-tts] listening on 127.0.0.1:$port');
    } catch (error, stack) {
      debugPrint('[microos-tts] could not bind 127.0.0.1:$port: $error\n$stack');
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.uri.path != '/speak') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    if (request.method != 'POST') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      request.response.headers.set(HttpHeaders.allowHeader, 'POST');
      await request.response.close();
      return;
    }
    if (request.contentLength > 1024 * 1024) {
      request.response.statusCode = HttpStatus.requestEntityTooLarge;
      await request.response.close();
      return;
    }

    try {
      final body = await utf8.decoder.bind(request).join();
      final payload = jsonDecode(body);
      if (payload is! Map<String, dynamic> ||
          payload['text'] is! String ||
          (payload['text'] as String).trim().isEmpty) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }

      final text = (payload['text'] as String).trim();
      final previous = _speechQueue;
      final completion = Completer<void>();
      _speechQueue = completion.future;
      try {
        await previous;
        await _tts.speak(text);
      } finally {
        completion.complete();
      }

      request.response.statusCode = HttpStatus.noContent;
    } on FormatException {
      request.response.statusCode = HttpStatus.badRequest;
    } catch (error, stack) {
      debugPrint('[microos-tts] speech request failed: $error\n$stack');
      request.response.statusCode = HttpStatus.internalServerError;
    }
    await request.response.close();
  }

  void dispose() {
    final server = _server;
    _server = null;
    if (server != null) {
      unawaited(server.close(force: true));
    }
  }
}
