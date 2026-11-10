import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme.dart';
import '../../services/linux_runtime.dart';

/// Shows the real X11 desktop.
///
/// The guest runs Xvfb + openbox + x11vnc + noVNC; this widget is the noVNC
/// client. That indirection is deliberate: drawing X11 pixels directly into a
/// Flutter texture would require a native X server, which is a separate app
/// (Termux:X11) and cannot be done in pure Dart. noVNC keeps everything inside
/// one APK and gives correct pointer/keyboard mapping for free.
class DesktopSessionApp extends StatefulWidget {
  const DesktopSessionApp({
    super.key,
    required this.runtime,
    this.launchBrowser = false,
    this.url,
    this.singleProcess = false,
  });

  final LinuxRuntime runtime;
  final bool launchBrowser;
  final String? url;
  final bool singleProcess;

  @override
  State<DesktopSessionApp> createState() => _DesktopSessionAppState();
}

class _DesktopSessionAppState extends State<DesktopSessionApp> {
  WebViewController? _controller;
  String _status = 'Connecting to the X11 display…';
  bool _failed = false;
  bool _booting = false;
  int _attempts = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    if (_booting) return;
    _booting = true;

    if (!widget.runtime.isReady) {
      setState(() {
        _failed = true;
        _status = 'Linux is not installed yet. Finish setup first.';
      });
      _booting = false;
      return;
    }

    setState(() {
      _failed = false;
      _status = 'Starting Xvfb and the window manager…';
    });

    final up = await widget.runtime.ensureDisplay(restart: _attempts > 0);
    _attempts++;
    if (!mounted) return;

    if (!up) {
      setState(() {
        _failed = true;
        _status = 'The display bridge did not start. Open Settings → Runtime log '
            'to see why (usually the toolchain install did not finish).';
      });
      _booting = false;
      return;
    }

    if (widget.launchBrowser) {
      setState(() => _status = 'Launching the browser…');
      await widget.runtime.launchBrowser(
        url: widget.url,
        singleProcess: widget.singleProcess,
      );
      // Give the browser a moment to map its window before the client connects.
      await Future<void>.delayed(const Duration(milliseconds: 900));
    }

    if (!mounted) return;
    setState(() => _status = 'Attaching to :1…');

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0B0E14))
      ..loadRequest(Uri.parse(_vncUrl));

    setState(() {
      _controller = controller;
      _status = 'Connected';
    });
    _booting = false;
  }

  String get _vncUrl {
    final base = 'http://127.0.0.1:6080/vnc.html';
    final query = <String>[
      'autoconnect=1',
      'resize=scale',
      'reconnect=1',
      'reconnect_delay=1500',
      'path=websockify',
    ];
    return '$base?${query.join('&')}';
  }

  void _reload() {
    _controller?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Container(
      color: const Color(0xFF0B0E14),
      child: Column(
        children: [
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            color: const Color(0xFF141822),
            child: Row(
              children: [
                const Icon(Icons.circle, size: 8, color: MicroColors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _status,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: MicroColors.subtle, fontSize: 11),
                  ),
                ),
                if (controller != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh, size: 16),
                    color: MicroColors.subtle,
                  ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: _boot,
                  icon: const Icon(Icons.restart_alt, size: 16),
                  color: MicroColors.subtle,
                ),
              ],
            ),
          ),
          Expanded(
            child: controller == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!_failed)
                            const SizedBox(
                              width: 26,
                              height: 26,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          if (_failed)
                            const Icon(Icons.error_outline,
                                color: MicroColors.red, size: 28),
                          const SizedBox(height: 16),
                          Text(
                            _status,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: MicroColors.subtle,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                          if (_failed) ...[
                            const SizedBox(height: 16),
                            FilledButton.tonal(
                              onPressed: _boot,
                              child: const Text('Try again'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : WebViewWidget(controller: controller),
          ),
        ],
      ),
    );
  }
}
