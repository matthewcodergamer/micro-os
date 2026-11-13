import 'dart:async';

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
  Timer? _vncRetryTimer;
  int _vncRetryCount = 0;
  bool _vncRetryCheckInFlight = false;
  bool _trackpadMode = true;
  double _trackpadSpeed = 1.35;
  String _selectedBrowser = 'chromium';
  late final TextEditingController _addressController;

  @override
  void initState() {
    super.initState();
    _addressController = TextEditingController(
      text: widget.url ?? 'https://www.google.com',
    );
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
        url: _addressController.text,
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
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => _installTouchBridge(controller),
        onWebResourceError: (_) => _retryVncPage(controller),
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
        final result = await controller.runJavaScriptReturningResult(
          "document.body ? document.body.innerText : ''",
        );
        final pageText = result.toString().toLowerCase();
        final connected = pageText.contains('connected') &&
            !pageText.contains('disconnected');
        if (connected) {
          timer.cancel();
          if (mounted) setState(() => _status = 'Connected');
          return;
        }

        _vncRetryCount++;
        if (_vncRetryCount >= 15) {
          _vncRetryCount = 0;
          if (mounted) setState(() => _status = 'Still waiting for the display… reconnecting');
          await controller.reload();
          return;
        }

        final failed = pageText.contains('failed to connect') ||
            pageText.contains('connection failed');
        if (failed || _vncRetryCount % 3 == 0) {
          if (mounted) {
            setState(() => _status =
                'Waiting for the VNC server… retry $_vncRetryCount/15');
          }
          await controller.reload();
        }
      } catch (_) {
        _vncRetryCount++;
        if (_vncRetryCount >= 15) {
          _vncRetryCount = 0;
          if (mounted) setState(() => _status = 'Still waiting for the display… reconnecting');
          await controller.reload();
        } else if (_vncRetryCount % 3 == 0) {
          await controller.reload();
        }
      } finally {
        _vncRetryCheckInFlight = false;
      }
    });
  }

  void _retryVncPage(WebViewController controller) {
    if (!mounted || !identical(_controller, controller)) return;
    if (_vncRetryCount < 15) {
      setState(() => _status = 'VNC connection interrupted; retrying…');
    }
  }

  @override
  void dispose() {
    _vncRetryTimer?.cancel();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _launchSelectedBrowser() async {
    final url = _addressController.text.trim();
    if (url.isEmpty) return;
    setState(() => _status = 'Opening $url in ${_selectedBrowser == 'firefox' ? 'Firefox' : 'Chromium'}…');
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

  void _setTrackpadSpeed(double speed) {
    setState(() => _trackpadSpeed = speed);
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
          const moveCursor=(dx,dy)=>{cursorX+=dx*sensitivity;cursorY+=dy*sensitivity;clampCursor();mouse('mousemove',cursorX,cursorY,-1,0);};
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
                mode='right';
                clickAt(trackpad?cursorX:startX,trackpad?cursorY:startY,2);
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
            if((mode==='pending'||mode==='move')&&e.touches.length===1){
              e.preventDefault();const p=point(e.touches[0]);
              if(mode==='pending'&&Math.hypot(p.x-startX,p.y-startY)>8){
                clear();moved=true;mode='move';
                if(!trackpad)mouse('mousedown',startX,startY,0,1);
              }
              if(mode==='move'){
                if(trackpad)moveCursor(p.x-lastX,p.y-lastY);
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
            if(mode==='move'&&!trackpad)mouse('mouseup',lastX,lastY,0,0);
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

  void _toggleTrackpadMode() {
    setState(() => _trackpadMode = !_trackpadMode);
    _controller?.runJavaScript(
      'window.__microOsSetTrackpadMode(${_trackpadMode ? 'true' : 'false'});',
    );
  }

  String get _vncUrl {
    final base = 'http://127.0.0.1:6080/vnc.html';
    final query = <String>[
      'autoconnect=1',
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
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'right', child: Text('Right-click')),
        PopupMenuItem(value: 'keyboard', child: Text('Show Linux keyboard')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'slow', child: Text('Cursor speed: slow')),
        PopupMenuItem(value: 'normal', child: Text('Cursor speed: normal')),
        PopupMenuItem(value: 'fast', child: Text('Cursor speed: fast')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'reconnect', child: Text('Reconnect desktop')),
        PopupMenuItem(value: 'restart', child: Text('Restart desktop')),
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
          if (widget.launchBrowser)
            Container(
              padding: const EdgeInsets.fromLTRB(7, 3, 7, 2),
              color: const Color(0xFF141822),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.circle, size: 8, color: MicroColors.green),
                      const SizedBox(width: 5),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedBrowser,
                          isDense: true,
                          dropdownColor: const Color(0xFF202735),
                          style: const TextStyle(color: Colors.white, fontSize: 11),
                          items: const [
                            DropdownMenuItem(value: 'chromium', child: Text('Chromium')),
                            DropdownMenuItem(value: 'firefox', child: Text('Firefox')),
                          ],
                          onChanged: controller == null ? null : _selectBrowser,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: TextField(
                          controller: _addressController,
                          enabled: controller != null,
                          textInputAction: TextInputAction.go,
                          keyboardType: TextInputType.url,
                          onSubmitted: (_) => _launchSelectedBrowser(),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          decoration: InputDecoration(
                            hintText: 'Enter website address',
                            hintStyle: const TextStyle(color: MicroColors.subtle, fontSize: 11),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
                            filled: true,
                            fillColor: const Color(0xFF0B0E14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Go to address',
                        visualDensity: VisualDensity.compact,
                        onPressed: controller == null ? null : _launchSelectedBrowser,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                        color: MicroColors.accent,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        visualDensity: VisualDensity.compact,
                        onPressed: controller == null
                            ? null
                            : () => widget.runtime.controlBrowser('back'),
                        icon: const Icon(Icons.arrow_back_rounded, size: 17),
                        color: MicroColors.subtle,
                      ),
                      IconButton(
                        tooltip: 'Forward',
                        visualDensity: VisualDensity.compact,
                        onPressed: controller == null
                            ? null
                            : () => widget.runtime.controlBrowser('forward'),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                        color: MicroColors.subtle,
                      ),
                      IconButton(
                        tooltip: 'Reload page',
                        visualDensity: VisualDensity.compact,
                        onPressed: controller == null
                            ? null
                            : () => widget.runtime.controlBrowser('reload'),
                        icon: const Icon(Icons.refresh_rounded, size: 17),
                        color: MicroColors.subtle,
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: _trackpadMode
                            ? 'Trackpad cursor enabled'
                            : 'Direct touch enabled',
                        visualDensity: VisualDensity.compact,
                        onPressed: controller == null ? null : _toggleTrackpadMode,
                        icon: Icon(
                          _trackpadMode
                              ? Icons.track_changes_rounded
                              : Icons.touch_app_rounded,
                          size: 17,
                        ),
                        color: _trackpadMode
                            ? MicroColors.accent
                            : MicroColors.subtle,
                      ),
                      if (controller != null) _moreControlsButton(),
                    ],
                  ),
                ],
              ),
            )
          else
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              color: const Color(0xFF141822),
              child: Row(
                children: [
                  const Icon(Icons.circle, size: 8, color: MicroColors.green),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _status,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: MicroColors.subtle, fontSize: 11),
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
