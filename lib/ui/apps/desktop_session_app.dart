import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../core/desktop_input.dart';
import '../../core/theme.dart';
import '../../services/desktop_audio.dart';
import '../../services/linux_runtime.dart';
import '../../services/settings_store.dart';
import '../desktop_controls_overlay.dart';
import '../desktop_key_bar.dart';
import '../native_x11_view.dart';

/// Shows the guest's real X11 desktop on Misty OS's own native surface.
///
/// The guest runs Xvfb + Openbox and a small MIT-licensed bridge. The Android
/// side mirrors damaged X11 rectangles into a TextureView and sends touch,
/// pointer and keyboard events back over a Unix socket. There is no VNC,
/// websockify or WebView in this path.
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
  String _status = 'Connecting to the native X11 display…';
  bool _failed = false;
  bool _booting = false;
  bool _displayReady = false;
  bool _connected = false;
  String? _socketPath;
  Size? _frameSize;
  int _attempts = 0;
  int _sessionGeneration = 0;
  DesktopPointerMode _pointerMode = DesktopPointerMode.trackpad;
  double _cursorSpeed = 1.35;
  bool _keyBarPinned = false;
  bool _audioMuted = false;
  Timer? _watchdog;
  int _reconnectAttempts = 0;
  SettingsStore? _settingsStore;
  bool _settingsInitialized = false;
  String _selectedBrowser = 'chromium';
  final GlobalKey<DesktopKeyBarState> _keyBarKey =
      GlobalKey<DesktopKeyBarState>();
  final GlobalKey<NativeX11ViewState> _x11Key = GlobalKey<NativeX11ViewState>();

  @override
  void initState() {
    super.initState();
    _audioMuted = DesktopAudio.volume <= 0.001;
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
    _watchdog = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_displayReady || _booting || _connected) return;
      if (_reconnectAttempts >= 4) return;
      _reconnectAttempts++;
      if (_reconnectAttempts.isEven) {
        // The surface alone cannot recover a guest bridge that exited. Restart
        // the whole display stack on every second failed reattach.
        _attempts = 1;
        unawaited(_boot());
      } else {
        _reconnectSurface();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settingsInitialized) return;
    _settingsStore = AppScope.of(context).settings;
    _pointerMode = _settingsStore!.desktopPointerMode;
    _cursorSpeed = _settingsStore!.desktopCursorSpeed;
    _settingsStore!.addListener(_syncDesktopSettings);
    _settingsInitialized = true;
  }

  void _syncDesktopSettings() {
    final settings = _settingsStore;
    if (settings == null || !mounted) return;
    final modeChanged = _pointerMode != settings.desktopPointerMode;
    final speedChanged = (_cursorSpeed - settings.desktopCursorSpeed).abs() > 0.001;
    if (!modeChanged && !speedChanged) return;
    setState(() {
      _pointerMode = settings.desktopPointerMode;
      _cursorSpeed = settings.desktopCursorSpeed;
    });
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _settingsStore?.removeListener(_syncDesktopSettings);
    unawaited(DesktopAudio.stop());
    super.dispose();
  }

  Future<void> _boot() async {
    if (_booting || !mounted) return;
    _booting = true;
    try {
      if (!widget.runtime.isReady) {
        if (mounted) {
          setState(() {
            _failed = true;
            _status = 'Linux is not installed yet. Finish setup first.';
          });
        }
        return;
      }

      setState(() {
        _failed = false;
        _displayReady = false;
        _connected = false;
        _status = 'Starting Xvfb and Openbox…';
      });

      var up = false;
      try {
        up = await widget.runtime.ensureDisplay(restart: _attempts > 0);
      } catch (error) {
        if (mounted) {
          setState(() {
            _failed = true;
            _status = 'Could not start the native X11 display: $error';
          });
        }
        return;
      }
      _attempts++;
      if (!mounted) return;

      if (!up) {
        setState(() {
          _failed = true;
          _status = 'The native X11 bridge did not start. Open Settings → '
              'Runtime log to see why (usually the guest is still installing).';
        });
        return;
      }

      if (widget.launchBrowser) {
        setState(() => _status = 'Launching the browser…');
        try {
          await widget.runtime.launchBrowser(
            url: widget.url ?? 'https://www.google.com',
            browser: _selectedBrowser,
            singleProcess: widget.singleProcess,
          );
          // Give the browser a moment to map its window before attaching.
          await Future<void>.delayed(const Duration(milliseconds: 900));
        } catch (error) {
          // A failed browser launch must never leave the desktop spinner stuck.
          if (mounted) {
            setState(() => _status = 'The desktop is ready; the browser did '
                'not start: $error');
          }
        }
      }

      if (!mounted) return;
      unawaited(DesktopAudio.start(widget.runtime.audioSocketPath));
      setState(() {
        _socketPath = widget.runtime.displaySocketPath;
        _displayReady = true;
        _connected = false;
        _reconnectAttempts = 0;
        _sessionGeneration++;
        _status = 'Attaching native X11 surface…';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _status = 'The desktop session failed to start: $error';
        });
      }
    } finally {
      _booting = false;
    }
  }

  void _onNativeStatus(NativeX11Status status) {
    if (!mounted) return;
    final frame = status.frameSize;
    setState(() {
      _connected = status.connected;
      if (frame != null) _frameSize = frame;
      if (status.connected) {
        _failed = false;
        _reconnectAttempts = 0;
        _status = _frameSize == null
            ? 'Connected to the X11 desktop'
            : 'Connected · ${_frameSize!.width.round()}×${_frameSize!.height.round()}';
      } else {
        _status = 'Waiting for the native X11 bridge…';
      }
    });
  }

  void _onThreeFingerTap() {
    _toggleKeyBar();
  }

  Future<void> _launchSelectedBrowser() async {
    final url = widget.url ?? 'https://www.google.com';
    if (!mounted) return;
    setState(() => _status =
        'Opening $url in ${_selectedBrowser == 'firefox' ? 'Firefox' : 'Chromium'}…');
    try {
      await widget.runtime.launchBrowser(
        browser: _selectedBrowser,
        url: url,
        singleProcess: widget.singleProcess,
      );
      if (mounted && _connected) {
        setState(() => _status = 'Browser launch requested');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _status = 'Browser launch failed: $error');
      }
    }
  }

  Future<void> _selectBrowser(String? browser) async {
    if (browser == null || browser == _selectedBrowser) return;
    setState(() => _selectedBrowser = browser);
    await _launchSelectedBrowser();
  }

  Future<void> _showRemoteKeyboard() async {
    if (!mounted) return;
    if (!_keyBarPinned) setState(() => _keyBarPinned = true);
    await _x11Key.currentState?.showKeyboard();
  }

  Future<void> _hideDesktopKeyBar() async {
    final bar = _keyBarKey.currentState;
    if (bar != null) await bar.releaseAllModifiers();
    if (!mounted) return;
    setState(() => _keyBarPinned = false);
    await _x11Key.currentState?.hideKeyboard();
  }

  void _toggleKeyBar() {
    if (_keyBarPinned) {
      unawaited(_hideDesktopKeyBar());
    } else {
      unawaited(_showRemoteKeyboard());
    }
  }

  void _rightClick() {
    unawaited(_x11Key.currentState?.rightClick());
  }

  Future<void> _setPointerMode(DesktopPointerMode mode) async {
    if (_pointerMode == mode) return;
    setState(() => _pointerMode = mode);
    await _settingsStore?.setDesktopPointerMode(mode);
  }

  void _cyclePointerMode() {
    unawaited(_setPointerMode(_pointerMode.next));
  }

  Future<void> _setCursorSpeed(double speed) async {
    final next = speed.clamp(0.8, 2.0).toDouble();
    setState(() => _cursorSpeed = next);
    await _settingsStore?.setDesktopCursorSpeed(next);
  }

  Future<void> _sendDesktopKey(int keysym, String code, bool down) async {
    await _x11Key.currentState?.sendKey(keysym, down);
  }

  Future<void> _typeDesktopText(String text) async {
    await _x11Key.currentState?.sendText(text);
  }

  void _reconnectSurface() {
    if (!mounted) return;
    setState(() {
      _connected = false;
      _sessionGeneration++;
      _status = 'Reconnecting to the native X11 bridge…';
    });
  }

  Future<void> _toggleAudio() async {
    final muted = !_audioMuted;
    setState(() => _audioMuted = muted);
    await DesktopAudio.setVolume(muted ? 0 : 1);
  }

  void _restartDesktop() {
    _attempts = 1;
    unawaited(_boot());
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
          case 'extra-keys':
            _toggleKeyBar();
            break;
          case 'pointer-mode':
            _cyclePointerMode();
            break;
          case 'recenter':
            unawaited(_x11Key.currentState?.recenterCursor());
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
            _setCursorSpeed(0.9);
            break;
          case 'normal':
            _setCursorSpeed(1.35);
            break;
          case 'fast':
            _setCursorSpeed(1.8);
            break;
          case 'mute-audio':
            unawaited(_toggleAudio());
            break;
          case 'reconnect':
            _reconnectAttempts = 0;
            _reconnectSurface();
            break;
          case 'restart':
            _restartDesktop();
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'right', child: Text('Right-click')),
        const PopupMenuItem(value: 'keyboard', child: Text('Desktop keyboard')),
        const PopupMenuItem(value: 'extra-keys', child: Text('Show extra keys bar')),
        const PopupMenuItem(value: 'pointer-mode', child: Text('Switch pointer mode')),
        const PopupMenuItem(value: 'recenter', child: Text('Recenter pointer')),
        const PopupMenuItem(value: 'mute-audio', child: Text('Mute desktop audio')),
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

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final showKeyBar = _displayReady && (_keyBarPinned || keyboardVisible);
    final socketPath = _socketPath;
    // The browser toolbar carries more actions than the plain desktop. On a
    // phone, keep the essentials and let the More menu expose the rest instead
    // of overflowing the row.
    final compact = MediaQuery.sizeOf(context).width < 420;

    return Container(
      color: const Color(0xFF0B0E14),
      child: Column(
        children: [
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: const Color(0xFF141822),
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 8,
                  color: _connected ? MicroColors.green : MicroColors.subtle,
                ),
                const SizedBox(width: 6),
                if (widget.launchBrowser) ...[
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
                      onChanged: _displayReady ? _selectBrowser : null,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (!compact)
                  Expanded(
                    child: Text(
                      _status,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: MicroColors.subtle, fontSize: 11),
                    ),
                  )
                else
                  const Spacer(),
                if (_displayReady) ...[
                  IconButton(
                    tooltip: _audioMuted ? 'Unmute desktop audio' : 'Mute desktop audio',
                    visualDensity: VisualDensity.compact,
                    onPressed: _toggleAudio,
                    icon: Icon(
                      _audioMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      size: 16,
                    ),
                    color: _audioMuted ? MicroColors.red : MicroColors.subtle,
                  ),
                  if (!compact)
                    IconButton(
                      tooltip: _pointerMode.title,
                      visualDensity: VisualDensity.compact,
                      onPressed: _cyclePointerMode,
                      icon: Icon(
                        _pointerMode.usesVisibleCursor
                            ? Icons.track_changes_rounded
                            : Icons.touch_app_rounded,
                        size: 16,
                      ),
                      color: _pointerMode.usesVisibleCursor
                          ? MicroColors.accent
                          : MicroColors.subtle,
                    ),
                  _moreControlsButton(),
                ],
                if (!compact)
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
            child: !_displayReady || socketPath == null
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
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      NativeX11View(
                        key: ValueKey<int>(_sessionGeneration),
                        socketPath: socketPath,
                        pointerMode: _pointerMode,
                        cursorSpeed: _cursorSpeed,
                        onStatus: _onNativeStatus,
                        onThreeFingerTap: _onThreeFingerTap,
                      ),
                      DesktopControlsOverlay(
                        pointerMode: _pointerMode,
                        keyBarVisible: showKeyBar,
                        onKeyboard: _showRemoteKeyboard,
                        onCyclePointerMode: _cyclePointerMode,
                        onToggleKeyBar: _toggleKeyBar,
                      ),
                    ],
                  ),
          ),
          if (showKeyBar)
            DesktopKeyBar(
              key: _keyBarKey,
              onKeyEvent: _sendDesktopKey,
              onText: _typeDesktopText,
              onHide: () => unawaited(_hideDesktopKeyBar()),
            ),
        ],
      ),
    );
  }
}
