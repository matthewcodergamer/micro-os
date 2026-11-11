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
        url: widget.url ?? 'https://www.google.com',
        singleProcess: widget.singleProcess,
      );
      // Give the browser a moment to map its window before the client connects.
      await Future<void>.delayed(const Duration(milliseconds: 900));
    }

    if (!mounted) return;
    setState(() => _status = 'Attaching to :1…');

    late final WebViewController controller;
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0B0E14))
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => _installTouchBridge(controller),
      ))
      ..loadRequest(Uri.parse(_vncUrl));

    setState(() {
      _controller = controller;
      _status = 'Connected';
    });
    _booting = false;
  }

  // noVNC runs inside the Android WebView. Translate touch gestures into
  // ordinary DOM pointer/wheel events on its canvas so the existing noVNC
  // RFB input pipeline sends them to X11. A tap is left-click, a 500ms
  // stationary press is right-click, a one-finger drag is mouse movement,
  // and a two-finger drag becomes vertical/horizontal wheel scrolling.
  Future<void> _installTouchBridge(WebViewController controller) async {
    await controller.runJavaScript(r"""
      (() => {
        if (window.__microOsTouchBridgeInstalled) return;
        const canvas = document.getElementById('noVNC_canvas');
        if (!canvas) {
          const observer = new MutationObserver(() => {
            const retry = document.getElementById('noVNC_canvas');
            if (retry) {
              observer.disconnect();
              install(retry);
            }
          });
          observer.observe(document.documentElement, {childList:true,subtree:true});
          return;
        }
        install(canvas);
        function install(target) {
          if (window.__microOsTouchBridgeInstalled) return;
          window.__microOsTouchBridgeInstalled = true;
          target.style.touchAction = 'none';
          let mode = 'idle', startX = 0, startY = 0, lastX = 0, lastY = 0;
          let timer = null, rightClick = false, moved = false;
          const point = (t) => ({x:t.clientX, y:t.clientY});
          const pointer = (type, x, y, button, buttons) => {
            target.dispatchEvent(new PointerEvent(type, {
              bubbles:true, cancelable:true, pointerId:1, pointerType:'mouse',
              isPrimary:true, clientX:x, clientY:y, button, buttons
            }));
          };
          const mouse = (type, x, y, button, buttons) => {
            target.dispatchEvent(new MouseEvent(type, {
              bubbles:true, cancelable:true, view:window,
              clientX:x, clientY:y, button, buttons
            }));
          };
          const clear = () => { if (timer) clearTimeout(timer); timer = null; };
          target.addEventListener('touchstart', e => {
            if (e.touches.length === 2) {
              clear(); mode = 'scroll';
              const a=point(e.touches[0]), b=point(e.touches[1]);
              lastX=(a.x+b.x)/2; lastY=(a.y+b.y)/2;
              return;
            }
            if (e.touches.length !== 1) return;
            const p=point(e.touches[0]);
            mode='pending'; startX=lastX=p.x; startY=lastY=p.y;
            moved=false; rightClick=false;
            clear();
            timer=setTimeout(() => {
              if (mode==='pending' && !moved) {
                rightClick=true; mode='right';
                pointer('pointerdown', startX, startY, 2, 2);
                mouse('mousedown', startX, startY, 2, 2);
              }
            }, 500);
          }, {passive:false});
          target.addEventListener('touchmove', e => {
            if (mode==='scroll' && e.touches.length >= 2) {
              e.preventDefault();
              const a=point(e.touches[0]), b=point(e.touches[1]);
              const x=(a.x+b.x)/2, y=(a.y+b.y)/2;
              target.dispatchEvent(new WheelEvent('wheel', {
                bubbles:true, cancelable:true,
                deltaX:lastX-x, deltaY:lastY-y, deltaMode:0
              }));
              lastX=x; lastY=y; return;
            }
            if ((mode==='pending' || mode==='drag') && e.touches.length===1) {
              e.preventDefault();
              const p=point(e.touches[0]);
              if (mode==='pending' && Math.hypot(p.x-startX,p.y-startY)>8) {
                clear(); moved=true; mode='drag';
                pointer('pointerdown', startX, startY, 0, 1);
                mouse('mousedown', startX, startY, 0, 1);
              }
              if (mode==='drag') {
                pointer('pointermove',p.x,p.y,-1,1);
                mouse('mousemove',p.x,p.y,-1,1);
              }
              lastX=p.x; lastY=p.y;
            }
          }, {passive:false});
          const finish = e => {
            clear();
            if (mode==='right') {
              pointer('pointerup',lastX,lastY,2,0);
              mouse('mouseup',lastX,lastY,2,0);
              target.dispatchEvent(new MouseEvent('contextmenu',{
                bubbles:true,cancelable:true,view:window,
                clientX:lastX,clientY:lastY,button:2
              }));
            } else if (mode==='drag') {
              pointer('pointerup',lastX,lastY,0,0);
              mouse('mouseup',lastX,lastY,0,0);
            } else if (mode==='pending' && !moved) {
              pointer('pointerdown',startX,startY,0,1);
              mouse('mousedown',startX,startY,0,1);
              pointer('pointerup',startX,startY,0,0);
              mouse('mouseup',startX,startY,0,0);
              mouse('click',startX,startY,0,0);
            }
            mode='idle'; rightClick=false;
          };
          target.addEventListener('touchend', finish, {passive:false});
          target.addEventListener('touchcancel', finish, {passive:false});
        }
      })();
    """);
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
