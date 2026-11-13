import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/theme.dart';
import '../../services/linux_runtime.dart';

class TorrentsApp extends StatefulWidget {
  const TorrentsApp({super.key, required this.runtime});
  final LinuxRuntime runtime;
  @override
  State<TorrentsApp> createState() => _TorrentsAppState();
}
class _TorrentsAppState extends State<TorrentsApp> {
  WebViewController? _controller;
  String _status = 'Starting torrent engine…';
  bool _failed = false;
  bool _starting = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }
  Future<void> _connect() async {
    if (_starting) return;
    _starting = true;
    if (!widget.runtime.isReady) {
      if (mounted) setState(() { _failed = true; _status = 'Install Linux before opening Torrents.'; });
      _starting = false;
      return;
    }
    if (mounted) setState(() { _failed = false; _status = 'Starting qBittorrent-nox…'; });
    final ready = await widget.runtime.ensureTorrentService();
    if (!mounted) { _starting = false; return; }
    if (!ready) {
      setState(() { _failed = true; _status = 'Torrent engine failed to start. Check Settings → Runtime log.'; });
      _starting = false;
      return;
    }
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF10141D))
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) { if (mounted) setState(() => _status = 'Loading qBittorrent…'); },
        onPageFinished: (_) { if (mounted) setState(() => _status = 'Connected · saves to Phone/Download'); },
        onWebResourceError: (_) { if (mounted) setState(() { _failed = true; _status = 'WebUI connection interrupted. Tap Retry.'; }); },
      ))
      ..loadRequest(Uri.parse('http://127.0.0.1:8080'));
    setState(() { _controller = controller; _status = 'Connecting to qBittorrent WebUI…'; });
    _starting = false;
  }
  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Container(
      color: const Color(0xFF10141D),
      child: Column(children: [
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: const Color(0xFF171E2A),
          child: Row(children: [
            const Icon(Icons.downloading_rounded, color: Color(0xFF55D6C2), size: 18),
            const SizedBox(width: 9),
            Expanded(child: Text(_status, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: MicroColors.subtle, fontSize: 11))),
            IconButton(visualDensity: VisualDensity.compact, onPressed: controller?.reload,
              icon: const Icon(Icons.refresh_rounded, size: 17), color: MicroColors.subtle),
          ]),
        ),
        Expanded(child: controller != null && !_failed
          ? WebViewWidget(controller: controller)
          : Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(_failed ? Icons.cloud_off_rounded : Icons.downloading_rounded,
                  color: _failed ? MicroColors.red : const Color(0xFF55D6C2), size: 34),
                const SizedBox(height: 12),
                Text(_status, textAlign: TextAlign.center,
                  style: const TextStyle(color: MicroColors.subtle, fontSize: 12)),
                if (_failed) ...[
                  const SizedBox(height: 14),
                  FilledButton.tonal(onPressed: _connect, child: const Text('Retry')),
                ],
              ]),
            ))),
      ]),
    );
  }
}
