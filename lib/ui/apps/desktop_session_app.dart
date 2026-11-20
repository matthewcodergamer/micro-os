import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app_scope.dart';
import '../../core/macos_design.dart';
import '../../core/theme.dart';
import '../../services/linux_runtime.dart';
import '../../services/settings_store.dart';

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
  Timer? _vncRetryTimer;
  Timer? _vncRecoveryTimer;
  int _vncRetryCount = 0;
  int _vncRecoveryAttempts = 0;
  bool _vncRecoveryInFlight = false;
  bool _vncRetryCheckInFlight = false;
  bool _displayDiagnosticsRequested = false;
  bool _trackpadMode = true;
  double _trackpadSpeed = 1.35;
  SettingsStore? _settingsStore;
  bool _settingsInitialized = false;
  String _selectedBrowser = 'chromium';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settingsInitialized) return;
    _settingsStore = AppScope.of(context).settings;
    _selectedBrowser = _settingsStore!.browserEngine;
    _trackpadMode = _settingsStore!.trackpadMode;
    _trackpadSpeed = _settingsStore!.trackpadSpeed;
    _settingsStore!.addListener(_syncTrackpadSettings);
    _settingsInitialized = true;
  }

  void _syncTrackpadSettings() {
    final settings = _settingsStore;
    if (settings == null || !mounted) return;
    final modeChanged = _trackpadMode != settings.trackpadMode;
    final speedChanged = _trackpadSpeed != settings.trackpadSpeed;
    final browserChanged = _selectedBrowser != settings.browserEngine;
    if (!modeChanged && !speedChanged && !browserChanged) return;
    setState(() {
      _trackpadMode = settings.trackpadMode;
      _trackpadSpeed = settings.trackpadSpeed;
      _selectedBrowser = settings.browserEngine;
    });
    final controller = _controller;
    if (controller != null) {
      controller.runJavaScript(
        'window.__microOsSetTrackpadMode(${_trackpadMode ? 'true' : 'false'});'
        'window.__microOsSetTrackpadSpeed($_trackpadSpeed);',
      );
    }
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

    final resolution = _settingsStore?.displayResolution;
    if (resolution != null) await widget.runtime.setDisplayResolution(resolution);
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
        url: widget.url ?? _settingsStore?.browserHomePage ?? 'https://www.google.com',
        browser: _selectedBrowser,
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
      ..setOnConsoleMessage((message) => widget.runtime.logDiagnostic(
            'console ${message.level}: ${message.message}',
          ))
      ..addJavaScriptChannel(
        'MicroOSDiagnostics',
        onMessageReceived: _onVncDiagnosticMessage,
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) =>
            widget.runtime.logDiagnostic('page started: $url'),
        onPageFinished: (url) async {
          widget.runtime.logDiagnostic('page finished: $url');
          await _installVncDiagnostics(controller);
          await _installTouchBridge(controller);
        },
        onWebResourceError: (error) {
          widget.runtime.logDiagnostic(
            'WebResourceError code=${error.errorCode} type=${error.errorType} '
            'mainFrame=${error.isForMainFrame} url=${error.url} '
            'description=${error.description}',
          );
          if (error.isForMainFrame) {
            _requestDisplayDiagnostics('main-frame WebResourceError: ${error.description}');
            _retryVncPage(controller);
          }
        },
        onHttpError: (error) {
          widget.runtime.logDiagnostic(
            'HttpError status=${error.response?.statusCode} '
            'url=${error.request.uri}',
          );
          _requestDisplayDiagnostics('HTTP error: ${error.response?.statusCode} ${error.request.uri}');
          _retryVncPage(controller);
        },
      ))
      ..loadRequest(Uri.parse(_vncUrl));

    setState(() {
      _controller = controller;
      _status = 'Connecting to VNC…';
    });
    _booting = false;
    _startVncRetryLoop(controller);
  }

  void _startVncRetryLoop(WebViewController controller) {
    _vncRetryTimer?.cancel();
    _vncRetryCount = 0;
    _vncRetryTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted || !identical(_controller, controller)) {
        timer.cancel();
        return;
      }
      if (_vncRetryCheckInFlight) return;
      _vncRetryCheckInFlight = true;
      try {
        // The health signal is produced from the actual noVNC canvas and RFB
        // connection state. Page text such as "Connected" is not evidence that
        // the remote framebuffer has painted any pixels.
        final result = await controller.runJavaScriptReturningResult(
          'window.__microOsVncHealth?.healthy === true',
        );
        if (result == true || result.toString() == 'true') {
          timer.cancel();
          _vncRecoveryAttempts = 0;
          _vncRecoveryTimer?.cancel();
          _vncRecoveryTimer = null;
          if (mounted) setState(() => _status = 'Connected — framebuffer active');
          return;
        }

        _vncRetryCount++;
        if (_vncRetryCount == 5 && mounted) {
          setState(() => _status = 'VNC connected; waiting for visible framebuffer pixels…');
        }
        if (_vncRetryCount >= 15) {
          _vncRetryCount = 0;
          widget.runtime.logDiagnostic(
            'canvas health timeout; reloading noVNC page after 15 seconds without visible pixels',
          );
          _requestDisplayDiagnostics('noVNC canvas health timeout');
          if (mounted) {
            setState(() => _status = 'No framebuffer pixels yet; reconnecting…');
          }
          await controller.reload();
        }
      } catch (error) {
        _vncRetryCount++;
        widget.runtime.logDiagnostic('canvas health poll failed: $error');
        if (_vncRetryCount >= 15) {
          _vncRetryCount = 0;
          await controller.reload();
        }
      } finally {
        _vncRetryCheckInFlight = false;
      }
    });
  }

  void _requestDisplayDiagnostics(String reason) {
    if (_displayDiagnosticsRequested) return;
    _displayDiagnosticsRequested = true;
    widget.runtime.collectDisplayDiagnostics(reason: reason);
  }

  void _onVncDiagnosticMessage(JavaScriptMessage message) {
    widget.runtime.logDiagnostic(message.message);
    try {
      final decoded = jsonDecode(message.message);
      if (decoded is! Map<String, dynamic>) return;
      final kind = decoded['kind']?.toString() ?? 'unknown';
      final failedHandshake = kind == 'websocket-error' ||
          kind == 'rfb-securityfailure' ||
          kind == 'novnc-ui-error' ||
          kind == 'rfb-error' ||
          (kind == 'rfb-disconnect' && decoded['clean'] != true);
      if (failedHandshake) {
        _requestDisplayDiagnostics('WebView reported ' + kind + ': ' + message.message);
      }
      if (kind == 'framebuffer' && decoded['healthy'] == true) {
        _displayDiagnosticsRequested = false;
        if (mounted) setState(() => _status = 'Connected — framebuffer active');
      }
    } catch (_) {
      // Preserve raw diagnostic text in the Runtime Log even if malformed.
    }
  }

  Future<void> _installVncDiagnostics(WebViewController controller) async {
    await controller.runJavaScript(r"""
      (() => {
        if (window.__microOsVncDiagnosticsInstalled) return;
        window.__microOsVncDiagnosticsInstalled = true;
        const send = (kind, detail={}) => {
          try {
            window.MicroOSDiagnostics?.postMessage(JSON.stringify({
              kind, timestamp: new Date().toISOString(), ...detail
            }));
          } catch (_) {}
        };

        // Install before UI.connect() so the actual noVNC WebSocket handshake
        // (including browser-level errors and close codes) is observable.
        const OriginalWebSocket = window.WebSocket;
        function DiagnosticWebSocket(url, protocols) {
          const socket = protocols === undefined
            ? new OriginalWebSocket(url)
            : new OriginalWebSocket(url, protocols);
          send('websocket-created', {url: String(url)});
          socket.addEventListener('open', () => send('websocket-open', {url: String(url)}));
          socket.addEventListener('error', () => send('websocket-error', {url: String(url)}));
          socket.addEventListener('close', event => send('websocket-close', {
            url: String(url), code: event.code, reason: event.reason,
            wasClean: event.wasClean
          }));
          return socket;
        }
        DiagnosticWebSocket.prototype = OriginalWebSocket.prototype;
        Object.setPrototypeOf(DiagnosticWebSocket, OriginalWebSocket);
        window.WebSocket = DiagnosticWebSocket;

        const ui = window.UI;
        if (!ui || typeof ui.connect !== 'function') {
          send('novnc-ui-error', {message: 'window.UI.connect is unavailable'});
          return;
        }
        try {
          ui.connect();
          send('novnc-connect-requested', {});
        } catch (error) {
          send('novnc-connect-threw', {message: String(error), stack: error?.stack || ''});
        }

        const rfb = ui.rfb;
        let rfbConnected = false;
        if (!rfb) {
          send('rfb-error', {message: 'UI.connect did not create UI.rfb'});
        } else {
          for (const eventName of [
            'connect', 'disconnect', 'securityfailure', 'credentialsrequired',
            'desktopname', 'capabilities'
          ]) {
            rfb.addEventListener(eventName, event => {
              const detail = event?.detail || {};
              if (eventName === 'connect') rfbConnected = true;
              if (eventName === 'disconnect') rfbConnected = false;
              send('rfb-' + eventName, {
                state: rfbConnected ? 'connected' : (rfb._rfbConnectionState || 'unknown'),
                clean: detail.clean,
                reason: detail.reason,
                name: detail.name,
                capabilities: detail.capabilities
              });
            });
          }
          send('rfb-initial-state', {
            state: rfb._rfbConnectionState || 'unknown'
          });
        }

        let previousSignature = '';
        let previousHealthy = false;
        let lastReport = 0;
        const sampleFramebuffer = () => {
          const canvas = document.getElementById('noVNC_canvas');
          const state = rfbConnected ? 'connected' : (window.UI?.rfb?._rfbConnectionState || 'unavailable');
          let width = canvas?.width || 0;
          let height = canvas?.height || 0;
          let nonBlackPixels = 0;
          let signature = '';
          let sampleError = '';
          if (canvas && width > 0 && height > 0) {
            try {
              const context = canvas.getContext('2d', {willReadFrequently:true});
              const points = [
                [0.2,0.2],[0.5,0.2],[0.8,0.2],
                [0.2,0.5],[0.5,0.5],[0.8,0.5],
                [0.2,0.8],[0.5,0.8],[0.8,0.8]
              ];
              const values = [];
              for (const point of points) {
                const x = Math.min(width-1, Math.floor(width*point[0]));
                const y = Math.min(height-1, Math.floor(height*point[1]));
                const pixel = context.getImageData(x,y,1,1).data;
                const r=pixel[0],g=pixel[1],b=pixel[2],a=pixel[3];
                if (a > 0 && (r+g+b) > 24) nonBlackPixels++;
                values.push(r,g,b,a);
              }
              signature = values.join(',');
            } catch (error) {
              sampleError = String(error);
            }
          }
          const connected = rfbConnected || state === 'connected';
          const canvasReady = width > 0 && height > 0;
          const healthy = connected && canvasReady && nonBlackPixels > 0;
          window.__microOsVncHealth = {
            connected, canvasReady, healthy, width, height,
            nonBlackPixels, signature, state, sampleError
          };
          const now = Date.now();
          if (signature !== previousSignature ||
              healthy !== previousHealthy ||
              now - lastReport > 5000) {
            send('framebuffer', {
              connected, canvasReady, healthy, width, height,
              nonBlackPixels, signature, state, sampleError
            });
            previousSignature = signature;
            previousHealthy = healthy;
            lastReport = now;
          }
        };
        sampleFramebuffer();
        window.__microOsVncSampler = window.setInterval(sampleFramebuffer, 1000);
        send('diagnostics-installed', {autoconnect: false});
      })();
    """);
  }

  void _retryVncPage(WebViewController controller) {
    if (!mounted || !identical(_controller, controller)) return;
    setState(() => _status = 'Desktop connection interrupted; repairing the display…');
    _scheduleVncRecovery(controller);
  }

  void _scheduleVncRecovery(WebViewController controller) {
    if (_vncRecoveryTimer != null ||
        _vncRecoveryInFlight ||
        _vncRecoveryAttempts >= 3) {
      return;
    }
    // Let a transient WebView/network hiccup settle before restarting X11.
    _vncRecoveryTimer = Timer(const Duration(seconds: 5), () async {
      _vncRecoveryTimer = null;
      if (!mounted || !identical(_controller, controller)) return;
      _vncRecoveryInFlight = true;
      _vncRecoveryAttempts++;
      if (mounted) {
        setState(() => _status =
            'Repairing Linux display… attempt $_vncRecoveryAttempts/3');
      }
      try {
        final ready = await widget.runtime.ensureDisplay(restart: true);
        if (!mounted || !identical(_controller, controller)) return;
        if (ready) {
          await controller.loadRequest(Uri.parse(_vncUrl));
          setState(() => _status = 'Display restarted; reconnecting…');
        } else {
          setState(() => _status =
              'Display repair failed. Check Settings → Runtime log and retry.');
        }
      } catch (error) {
        if (mounted) setState(() => _status = 'Display repair error: $error');
      } finally {
        _vncRecoveryInFlight = false;
      }
    });
  }

  @override
  void dispose() {
    _vncRetryTimer?.cancel();
    _vncRecoveryTimer?.cancel();
    _settingsStore?.removeListener(_syncTrackpadSettings);
    super.dispose();
  }

  Future<void> _launchSelectedBrowser() async {
    final url = widget.url ?? _settingsStore?.browserHomePage ?? 'https://www.google.com';
    if (!mounted) return;
    setState(() => _status =
        'Opening $url in ${_selectedBrowser == 'firefox' ? 'Firefox' : 'Chromium'}…');
    await widget.runtime.launchBrowser(
      browser: _selectedBrowser,
      url: url,
      singleProcess: widget.singleProcess,
    );
    if (mounted) setState(() => _status = 'Browser launch requested');
  }

  Future<void> _selectBrowser(String? browser) async {
    if (browser == null || browser == _selectedBrowser) return;
    setState(() => _selectedBrowser = browser);
    await _settingsStore?.setBrowserEngine(browser);
    await _launchSelectedBrowser();
  }

  Future<void> _showRemoteKeyboard() async {
    await _controller?.runJavaScript(
      "document.querySelector('#noVNC_keyboardinput')?.focus();",
    );
  }

  void _rightClick() {
    _controller?.runJavaScript('window.__microOsRightClick?.();');
  }

  Future<void> _setTrackpadSpeed(double speed) async {
    setState(() => _trackpadSpeed = speed);
    await _settingsStore?.setTrackpadSpeed(speed);
    _controller?.runJavaScript(
      'window.__microOsTrackpadSpeed=$speed;window.__microOsSetTrackpadSpeed?.($speed);',
    );
  }

  // Translate mobile gestures into mouse/wheel input for noVNC. Trackpad
  // mode moves a visible cursor relatively; direct mode maps touch to pixels.
  Future<void> _installTouchBridge(WebViewController controller) async {
    await controller.runJavaScript(r"""
      (() => {
        if (window.__microOsTouchBridgeV2Installed) return;
        const canvas = document.getElementById('noVNC_canvas');
        if (!canvas) {
          const observer = new MutationObserver(() => {
            const found = document.getElementById('noVNC_canvas');
            if (found) { observer.disconnect(); install(found); }
          });
          observer.observe(document.documentElement, {childList:true,subtree:true});
          return;
        }
        function install(target) {
          if (window.__microOsTouchBridgeV2Installed) return;
          window.__microOsTouchBridgeV2Installed = true;
          target.style.touchAction = 'none';
          let trackpad = true, mode = 'idle', sensitivity = Number(window.__microOsTrackpadSpeed)||1.35;
          let startX=0,startY=0,lastX=0,lastY=0,cursorX=0,cursorY=0;
          let timer=null,moved=false;
          const cursor=document.createElement('div');
          cursor.setAttribute('aria-hidden','true');
          cursor.style.cssText=[
            'position:fixed','left:0','top:0','z-index:2147483647',
            'width:26px','height:34px','pointer-events:none','display:none',
            'transform:translate(-1px,-1px)',
            'filter:drop-shadow(1px 2px 2px rgba(0,0,0,.65))'
          ].join(';');
          cursor.innerHTML='<svg viewBox="0 0 26 34" width="26" height="34" xmlns="http://www.w3.org/2000/svg"><path d="M2 1 L2 27 L8.5 20.5 L13.5 32 L18 30 L13 18.5 L23 18 Z" fill="white" stroke="#111827" stroke-width="1.6" stroke-linejoin="round"/></svg>';
          document.body.appendChild(cursor);
          const bounds=()=>target.getBoundingClientRect();
          const clampCursor=()=>{
            const r=bounds();
            cursorX=Math.max(r.left+1,Math.min(r.right-2,cursorX));
            cursorY=Math.max(r.top+1,Math.min(r.bottom-2,cursorY));
            cursor.style.left=cursorX+'px'; cursor.style.top=cursorY+'px';
          };
          // Keep the pointer inside the live noVNC canvas after rotation,
          // browser chrome changes, or a resized remote desktop.
          const resizePointer=()=>{if(trackpad&&cursorX!==0&&cursorY!==0)clampCursor();};
          if(typeof ResizeObserver!=='undefined'){
            const canvasObserver=new ResizeObserver(resizePointer);
            canvasObserver.observe(target);
          }
          window.addEventListener('resize',resizePointer,{passive:true});
          window.visualViewport?.addEventListener('resize',resizePointer,{passive:true});
          const moveCursor=(dx,dy,buttons=0)=>{cursorX+=dx*sensitivity;cursorY+=dy*sensitivity;clampCursor();mouse('mousemove',cursorX,cursorY,-1,buttons);};
          const setMode=enabled=>{
            trackpad=!!enabled;
            cursor.style.display=trackpad?'block':'none';
            target.style.cursor=trackpad?'none':'default';
            if(trackpad&&cursorX===0&&cursorY===0){
              const r=bounds();cursorX=r.left+r.width/2;cursorY=r.top+r.height/2;
            }
            if(trackpad)clampCursor();
          };
          window.__microOsSetTrackpadMode=setMode;
          const mouse=(type,x,y,button=0,buttons=0)=>target.dispatchEvent(new MouseEvent(type,{
            bubbles:true,cancelable:true,view:window,clientX:x,clientY:y,button,buttons
          }));
          const clickAt=(x,y,button=0)=>{
            mouse('mousedown',x,y,button,button===0?1:2);
            mouse('mouseup',x,y,button,0);
            mouse(button===2?'contextmenu':'click',x,y,button,0);
          };
          window.__microOsSetTrackpadSpeed=value=>{
            const next=Number(value);
            if(Number.isFinite(next))sensitivity=Math.max(0.7,Math.min(2.2,next));
          };
          window.__microOsRightClick=()=>{
            const x=trackpad?cursorX:lastX,y=trackpad?cursorY:lastY;
            clickAt(x,y,2);
          };
          const point=t=>({x:t.clientX,y:t.clientY});
          const clear=()=>{if(timer)clearTimeout(timer);timer=null;};
          target.addEventListener('touchstart',e=>{
            if(e.touches.length===2){
              clear();mode='scroll';
              const a=point(e.touches[0]),b=point(e.touches[1]);
              lastX=(a.x+b.x)/2;lastY=(a.y+b.y)/2;return;
            }
            if(e.touches.length!==1)return;
            const p=point(e.touches[0]);
            mode='pending';startX=lastX=p.x;startY=lastY=p.y;moved=false;clear();
            timer=setTimeout(()=>{
              if(mode==='pending'&&!moved){
                // Long-press enters a real left-button drag. Moving after the
                // hold selects text in terminals/editors and drags desktop items.
                mode='drag';
                const x=trackpad?cursorX:startX,y=trackpad?cursorY:startY;
                mouse('mousedown',x,y,0,1);
              }
            },500);
          },{passive:false});
          target.addEventListener('touchmove',e=>{
            if(mode==='scroll'&&e.touches.length>=2){
              e.preventDefault();
              const a=point(e.touches[0]),b=point(e.touches[1]);
              const x=(a.x+b.x)/2,y=(a.y+b.y)/2;
              target.dispatchEvent(new WheelEvent('wheel',{
                bubbles:true,cancelable:true,deltaX:lastX-x,deltaY:lastY-y,deltaMode:0
              }));
              lastX=x;lastY=y;return;
            }
            if((mode==='pending'||mode==='move'||mode==='drag')&&e.touches.length===1){
              e.preventDefault();const p=point(e.touches[0]);
              if(mode==='pending'&&Math.hypot(p.x-startX,p.y-startY)>8){
                clear();moved=true;mode='move';
                if(!trackpad)mouse('mousedown',startX,startY,0,1);
              }
              if(mode==='move'){
                if(trackpad)moveCursor(p.x-lastX,p.y-lastY);
                else mouse('mousemove',p.x,p.y,-1,1);
              } else if(mode==='drag'){
                if(trackpad)moveCursor(p.x-lastX,p.y-lastY,1);
                else mouse('mousemove',p.x,p.y,-1,1);
              }
              lastX=p.x;lastY=p.y;
            }
          },{passive:false});
          const finish=e=>{
            if(e && e.touches && e.touches.length>0)return;
            clear();
            if((!e || e.type!=='touchcancel')&&mode==='pending'&&!moved){
              clickAt(trackpad?cursorX:startX,trackpad?cursorY:startY,0);
            }
            if(mode==='drag'){
              mouse('mouseup',trackpad?cursorX:lastX,trackpad?cursorY:lastY,0,0);
            } else if(mode==='move'&&!trackpad){
              mouse('mouseup',lastX,lastY,0,0);
            }
            mode='idle';
          };
          target.addEventListener('touchend',finish,{passive:false});
          target.addEventListener('touchcancel',finish,{passive:false});
          const r=bounds();cursorX=r.left+r.width/2;cursorY=r.top+r.height/2;
          setMode(true);
        }
        install(canvas);
      })();
    """);
    await controller.runJavaScript(
      'window.__microOsSetTrackpadMode(${_trackpadMode ? 'true' : 'false'});',
    );
    await controller.runJavaScript(
      'window.__microOsSetTrackpadSpeed($_trackpadSpeed);',
    );
  }

  Future<void> _toggleTrackpadMode() async {
    setState(() => _trackpadMode = !_trackpadMode);
    await _settingsStore?.setTrackpadMode(_trackpadMode);
    _controller?.runJavaScript(
      'window.__microOsSetTrackpadMode(${_trackpadMode ? 'true' : 'false'});',
    );
  }

  String get _vncUrl {
    final base = 'http://127.0.0.1:6080/vnc.html';
    final query = <String>[
      'autoconnect=0',
      'resize=scale',
      'reconnect=1',
      'reconnect_delay=1500',
      'path=websockify',
      // Moderate quality/compression keeps the stream responsive on mobile CPU.
      'quality=5',
      'compression=2',
    ];
    return '$base?${query.join('&')}';
  }

  Widget _moreControlsButton() {
    return PopupMenuButton<String>(
      tooltip: 'More desktop controls',
      icon: const Icon(Icons.more_vert, size: 18, color: MicroColors.subtle),
      color: const Color(0xFF202735),
      onSelected: (action) {
        switch (action) {
          case 'right':
            _rightClick();
            break;
          case 'keyboard':
            _showRemoteKeyboard();
            break;
          case 'back':
          case 'forward':
          case 'reload':
          case 'new-tab':
          case 'close-tab':
          case 'new-window':
          case 'focus-address':
          case 'home':
          case 'bookmarks':
          case 'fullscreen':
          case 'zoom-in':
          case 'zoom-out':
          case 'zoom-reset':
          case 'window-minimize':
          case 'window-maximize':
          case 'window-restore':
          case 'window-close':
            widget.runtime.controlBrowser(action);
            break;
          case 'slow':
            _setTrackpadSpeed(0.9);
            break;
          case 'normal':
            _setTrackpadSpeed(1.35);
            break;
          case 'fast':
            _setTrackpadSpeed(1.8);
            break;
          case 'reconnect':
            _reload();
            break;
          case 'restart':
            _boot();
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'right', child: Text('Right-click')),
        const PopupMenuItem(value: 'keyboard', child: Text('Show Linux keyboard')),
        if (widget.launchBrowser) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'back', child: Text('Back')),
          const PopupMenuItem(value: 'forward', child: Text('Forward')),
          const PopupMenuItem(value: 'reload', child: Text('Reload')),
          const PopupMenuItem(value: 'new-tab', child: Text('New browser tab')),
          const PopupMenuItem(value: 'close-tab', child: Text('Close browser tab')),
          const PopupMenuItem(value: 'new-window', child: Text('New browser window')),
          const PopupMenuItem(value: 'focus-address', child: Text('Focus address bar')),
          const PopupMenuItem(value: 'home', child: Text('Browser home')),
          const PopupMenuItem(value: 'bookmarks', child: Text('Toggle bookmarks bar')),
          const PopupMenuItem(value: 'fullscreen', child: Text('Toggle full screen')),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'window-minimize', child: Text('Minimize browser window')),
          const PopupMenuItem(value: 'window-maximize', child: Text('Maximize browser window')),
          const PopupMenuItem(value: 'window-restore', child: Text('Restore browser window')),
          const PopupMenuItem(value: 'window-close', child: Text('Close browser window')),
        ],
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'slow', child: Text('Cursor speed: slow')),
        const PopupMenuItem(value: 'normal', child: Text('Cursor speed: normal')),
        const PopupMenuItem(value: 'fast', child: Text('Cursor speed: fast')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'reconnect', child: Text('Reconnect desktop')),
        const PopupMenuItem(value: 'restart', child: Text('Restart desktop')),
      ],
    );
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
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  MicroColors.windowHeader,
                  Sequoia.toolbarTint.withValues(alpha: 0.96),
                ],
              ),
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.075),
                  width: 0.7,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: MicroColors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                if (widget.launchBrowser) ...[
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedBrowser,
                      isDense: true,
                      dropdownColor: const Color(0xFF202735),
                      borderRadius: BorderRadius.circular(10),
                      iconSize: 16,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'chromium', child: Text('Chromium')),
                        DropdownMenuItem(value: 'firefox', child: Text('Firefox')),
                      ],
                      onChanged: controller == null ? null : _selectBrowser,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    _status,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MicroColors.subtle,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (controller != null) ...[
                  IconButton(
                    tooltip: _trackpadMode
                        ? 'Trackpad cursor enabled'
                        : 'Direct touch enabled',
                    visualDensity: VisualDensity.compact,
                    onPressed: _toggleTrackpadMode,
                    icon: Icon(
                      _trackpadMode
                          ? Icons.track_changes_rounded
                          : Icons.touch_app_rounded,
                      size: 16,
                    ),
                    color: _trackpadMode
                        ? MicroColors.accent
                        : MicroColors.subtle,
                  ),
                  _moreControlsButton(),
                ],
                IconButton(
                  tooltip: 'Restart desktop session',
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
