import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

import '../../core/theme.dart';
import '../../services/linux_runtime.dart';
import '../../services/settings_store.dart';

/// A real PTY inside the Linux guest, rendered with xterm.dart.
///
/// Input is written straight through to the PTY with no artificial delay, which
/// is what keeps typing responsive; the flicker people see in X11 is a display
/// pipeline problem, not a keyboard one (see the desktop view).
class TerminalApp extends StatefulWidget {
  const TerminalApp({
    super.key,
    required this.runtime,
    this.argv,
    required this.settings,
  });

  final LinuxRuntime runtime;
  final List<String>? argv;
  final SettingsStore settings;

  @override
  State<TerminalApp> createState() => _TerminalAppState();
}

class _TerminalAppState extends State<TerminalApp> {
  final Terminal _terminal = Terminal(maxLines: 3000);
  final TerminalController _terminalController = TerminalController();
  final FlutterTts _tts = FlutterTts();
  bool _speaking = false;
  bool _voiceReady = false;
  HttpServer? _ttsServer;

  Pty? _pty;
  StreamSubscription? _output;
  String? _error;
  bool _ctrlArmed = false;
  final StringBuffer _pendingOutput = StringBuffer();
  Timer? _outputFlushTimer;
  Timer? _selectionCopyTimer;
  Timer? _copyToastTimer;
  OverlayEntry? _copyToast;
  String? _lastCopiedSelection;

  @override
  void initState() {
    super.initState();
    _configureTts();
    _startTtsBridge();
    _terminal.onOutput = _send;
    _terminal.onResize = _resize;
    _terminalController.addListener(_onSelectionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _start() {
    if (!mounted) return;
    if (!widget.runtime.isReady) {
      setState(() => _error = 'Linux is not installed yet. Finish setup first.');
      return;
    }

    try {
      final pty = widget.runtime.startShell(argv: widget.argv);
      _pty = pty;
      _output = pty.output.map((bytes) => utf8.decode(bytes, allowMalformed: true)).listen(
        _queueOutput,
        onError: (Object e) => _terminal.write('\r\n[pty error: $e]\r\n'),
        onDone: () => _terminal.write('\r\n[process exited]\r\n'),
      );
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  void _queueOutput(String chunk) {
    if (chunk.isEmpty) return;
    _pendingOutput.write(chunk);
    _outputFlushTimer ??= Timer(const Duration(milliseconds: 16), _flushOutput);
  }

  void _flushOutput() {
    _outputFlushTimer = null;
    if (!mounted || _pendingOutput.isEmpty) return;
    final chunk = _pendingOutput.toString();
    _pendingOutput.clear();
    _terminal.write(chunk);
  }

  Future<void> _configureTts() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.48);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(true);
      _tts.setStartHandler(() { if (mounted) setState(() => _speaking = true); });
      _tts.setCompletionHandler(() { if (mounted) setState(() => _speaking = false); });
      _tts.setCancelHandler(() { if (mounted) setState(() => _speaking = false); });
      _tts.setErrorHandler((_) { if (mounted) setState(() => _speaking = false); });
      _voiceReady = true;
    } catch (_) {
      _voiceReady = false;
    }
  }

  Future<void> _startTtsBridge() async {
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 17842);
      if (!mounted) {
        await server.close(force: true);
        return;
      }
      _ttsServer = server;
      server.listen((request) async {
        if (request.method != 'POST' || request.uri.path != '/speak') {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        try {
          final body = await utf8.decoder.bind(request).join();
          final payload = jsonDecode(body) as Map<String, dynamic>;
          final text = (payload['text'] as String? ?? '').trim();
          if (text.isEmpty || text.length > 12000) {
            request.response.statusCode = HttpStatus.badRequest;
            await request.response.close();
            return;
          }
          if (!widget.settings.autoReadOpenCode) {
            request.response.statusCode = HttpStatus.noContent;
            await request.response.close();
            return;
          }
          if (!_voiceReady) await _configureTts();
          await _tts.stop();
          await _tts.speak(text, focus: true);
          request.response.statusCode = HttpStatus.accepted;
        } catch (_) {
          request.response.statusCode = HttpStatus.internalServerError;
        }
        await request.response.close();
      });
    } catch (e) {
      // The manual read-aloud control remains available if the local bridge
      // cannot bind (for example, if another MicroOS terminal owns the port).
      debugPrint('MicroOS speech bridge unavailable: $e');
    }
  }

  Future<void> _speakText(String text) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return;
    if (!_voiceReady) await _configureTts();
    if (!_voiceReady) throw StateError('Android text-to-speech is unavailable');
    await _tts.stop();
    await _tts.speak(cleaned, focus: true);
  }

  Future<void> _readSelection() async {
    final range = _terminalController.selection;
    if (range == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select terminal text first, then tap Read aloud')),
        );
      }
      return;
    }
    final selected = _terminal.buffer.getText(range).trim();
    if (selected.isEmpty) return;
    try {
      await _speakText(selected);
      _terminalController.clearSelection();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read selection: $e')),
        );
      }
    }
  }

  Future<void> _stopSpeaking() async {
    await _tts.stop();
    if (mounted) setState(() => _speaking = false);
  }

  void _onSelectionChanged() {
    final range = _terminalController.selection;
    if (range == null) {
      _selectionCopyTimer?.cancel();
      _lastCopiedSelection = null;
      return;
    }
    _selectionCopyTimer?.cancel();
    _selectionCopyTimer = Timer(const Duration(milliseconds: 250), () async {
      final current = _terminalController.selection;
      if (!mounted || current == null) return;
      final selected = _terminal.buffer.getText(current);
      if (selected.trim().isEmpty || selected == _lastCopiedSelection) return;
      try {
        await Clipboard.setData(ClipboardData(text: selected));
        _lastCopiedSelection = selected;
        _showCopyToast();
      } catch (e) {
        debugPrint('MicroOS terminal auto-copy failed: $e');
      }
    });
  }

  void _showCopyToast() {
    if (!mounted) return;
    _copyToastTimer?.cancel();
    _copyToast?.remove();
    _copyToast = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 12,
        right: 12,
        child: Material(
          color: Colors.transparent,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xEE202733),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0x553FFFFFFF)),
              boxShadow: const [
                BoxShadow(color: Color(0x55000000), blurRadius: 14, offset: Offset(0, 5)),
              ],
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: Color(0xFF70D6A0), size: 16),
                  SizedBox(width: 8),
                  Text('Copied to clipboard', style: TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_copyToast!);
    _copyToastTimer = Timer(const Duration(milliseconds: 1400), () {
      _copyToast?.remove();
      _copyToast = null;
    });
  }

  Future<void> _copySelection() async {
    final range = _terminalController.selection;
    if (range == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Long-press text, drag the handles, then tap Copy')),
        );
      }
      return;
    }
    final selected = _terminal.buffer.getText(range);
    if (selected.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: selected));
    _terminalController.clearSelection();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) _terminal.paste(text);
  }

  void _send(String data) {
    if (_ctrlArmed && data.isNotEmpty) {
      _ctrlArmed = false;
      if (mounted) setState(() {});
      final code = data.toUpperCase().codeUnitAt(0);
      if (code >= 64 && code <= 95) {
        data = String.fromCharCode(code - 64);
      }
    }
    final pty = _pty;
    if (pty == null) return;
    try {
      pty.write(Uint8List.fromList(utf8.encode(data)));
    } catch (_) {
      // PTY closed mid-keystroke.
    }
  }

  void _sendExtra(String sequence) {
    _send(sequence);
  }

  Widget _extraKey(String label, String sequence, {bool selected = false, VoidCallback? onPressed}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
      child: SizedBox(
        height: 34,
        child: OutlinedButton(
          onPressed: onPressed ?? () => _sendExtra(sequence),
          style: OutlinedButton.styleFrom(
            foregroundColor: selected ? Colors.white : MicroColors.text,
            backgroundColor: selected ? const Color(0xFF315C9B) : const Color(0xFF252B38),
            side: const BorderSide(color: Color(0x334FFFFFFF)),
            padding: const EdgeInsets.symmetric(horizontal: 11),
            minimumSize: const Size(38, 34),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  void _resize(int width, int height, int pixelWidth, int pixelHeight) {
    try {
      _pty?.resize(height, width);
    } catch (_) {
      // Ignore resize after exit.
    }
  }

  @override
  void dispose() {
    _outputFlushTimer?.cancel();
    _selectionCopyTimer?.cancel();
    _copyToastTimer?.cancel();
    _copyToast?.remove();
    _terminalController.removeListener(_onSelectionChanged);
    if (_pendingOutput.isNotEmpty) {
      _terminal.write(_pendingOutput.toString());
      _pendingOutput.clear();
    }
    _output?.cancel();
    _ttsServer?.close(force: true);
    _tts.stop();
    _terminalController.dispose();
    try {
      _pty?.kill();
    } catch (_) {
      // Already dead.
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Container(
        color: MicroColors.panelSolid,
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: MicroColors.subtle, fontSize: 13),
          ),
        ),
      );
    }

    return Container(
      color: TerminalProColors.background,
      child: Column(
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF101010),
              border: Border(bottom: BorderSide(color: Color(0x1AFFFFFF))),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal, size: 15, color: Color(0xFFBFBFBF)),
                const SizedBox(width: 7),
                const Expanded(
                  child: Text(
                    'Terminal',
                    style: TextStyle(color: Color(0xFFBFBFBF), fontSize: 11),
                  ),
                ),
                IconButton(
                  tooltip: _speaking ? 'Stop reading aloud' : 'Read selected text aloud',
                  visualDensity: VisualDensity.compact,
                  onPressed: _speaking ? _stopSpeaking : _readSelection,
                  icon: Icon(_speaking ? Icons.stop_circle_outlined : Icons.volume_up, size: 18),
                  color: _speaking ? MicroColors.green : const Color(0xFFF4F4F4),
                ),
                IconButton(
                  tooltip: 'Copy selected terminal text',
                  visualDensity: VisualDensity.compact,
                  onPressed: _copySelection,
                  icon: const Icon(Icons.copy, size: 17),
                  color: const Color(0xFFF4F4F4),
                ),
                IconButton(
                  tooltip: 'Paste from Android clipboard',
                  visualDensity: VisualDensity.compact,
                  onPressed: _pasteFromClipboard,
                  icon: const Icon(Icons.content_paste, size: 17),
                  color: const Color(0xFFF4F4F4),
                ),
              ],
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: _speaking ? 34 : 0,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            color: const Color(0xFF252B38),
            child: _speaking
                ? Row(
                    children: [
                      const Icon(Icons.graphic_eq, color: MicroColors.green, size: 17),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('Reading aloud',
                          style: TextStyle(color: MicroColors.text, fontSize: 11)),
                      ),
                      TextButton.icon(
                        onPressed: _stopSpeaking,
                        icon: const Icon(Icons.stop, size: 14),
                        label: const Text('Stop'),
                        style: TextButton.styleFrom(
                          foregroundColor: MicroColors.text,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: widget.settings,
                builder: (context, _) => TerminalView(
                    _terminal,
                    controller: _terminalController,
                    deleteDetection: true,
                    autofocus: true,
                    padding: const EdgeInsets.all(8),
                    backgroundOpacity: 1,
                    theme: _theme,
                    textStyle: TerminalStyle(
                      fontSize: widget.settings.terminalFontSize,
                      fontFamily: 'JetBrains Mono',
                      fontFamilyFallback: const ['monospace'],
                    ),
                    simulateScroll: true,
                  ),
              ),
            ),
          ),
          // Termux-style developer keys stay available above the soft keyboard.
          Container(
            height: 44,
            decoration: const BoxDecoration(
              color: Color(0xFF101010),
              border: Border(top: BorderSide(color: Color(0x1AFFFFFF))),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _extraKey('Tab', '\t'),
                  _extraKey('↑', '\x1b[A'),
                  _extraKey('↓', '\x1b[B'),
                  _extraKey('PgUp', '\x1b[5~'),
                  _extraKey('PgDn', '\x1b[6~'),
                  _extraKey('←', '\x1b[D'),
                  _extraKey('→', '\x1b[C'),
                  _extraKey('Ctrl', '', selected: _ctrlArmed, onPressed: () {
                    setState(() => _ctrlArmed = !_ctrlArmed);
                  }),
                  _extraKey('Esc', '\x1b'),
                  _extraKey('|', '|'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// macOS Terminal.app Pro profile palette.
const TerminalTheme _theme = TerminalTheme(
  cursor: TerminalProColors.cursor,
  selection: TerminalProColors.selection,
  foreground: TerminalProColors.foreground,
  background: TerminalProColors.background,
  black: Color(0xFF000000),
  red: Color(0xFF990000),
  green: Color(0xFF00A600),
  yellow: Color(0xFF999900),
  blue: Color(0xFF0000B3),
  magenta: Color(0xFFB300B3),
  cyan: Color(0xFF00A6B3),
  white: Color(0xFFBFBFBF),
  brightBlack: Color(0xFF666666),
  brightRed: Color(0xFFE60000),
  brightGreen: Color(0xFF00D900),
  brightYellow: Color(0xFFE6E600),
  brightBlue: Color(0xFF0000FF),
  brightMagenta: Color(0xFFE600E6),
  brightCyan: Color(0xFF00E6E6),
  brightWhite: Color(0xFFE6E6E6),
  searchHitBackground: Color(0x66E6E600),
  searchHitBackgroundCurrent: Color(0x99E6E600),
  searchHitForeground: Color(0xFF000000),
);

class TerminalProColors {
  const TerminalProColors._();

  static const background = Color(0xFF000000);
  static const foreground = Color(0xFFF4F4F4);
  static const cursor = Color(0xFF606060);
  static const selection = Color(0xFF525252);
}
