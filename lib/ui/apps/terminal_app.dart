import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final Terminal _terminal = Terminal(maxLines: 1000);

  Pty? _pty;
  StreamSubscription? _output;
  String? _error;
  bool _ctrlArmed = false;
  final StringBuffer _pendingOutput = StringBuffer();
  Timer? _outputFlushTimer;

  @override
  void initState() {
    super.initState();
    _terminal.onOutput = _send;
    _terminal.onResize = _resize;
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

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) _terminal.paste(text);
  }

  Future<void> _showTerminalMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MicroColors.panelSolid,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: const Text('Paste from clipboard'),
              onTap: () => Navigator.pop(context, 'paste'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'paste') await _pasteFromClipboard();
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
    if (_pendingOutput.isNotEmpty) {
      _terminal.write(_pendingOutput.toString());
      _pendingOutput.clear();
    }
    _output?.cancel();
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
                  tooltip: 'Paste from Android clipboard',
                  visualDensity: VisualDensity.compact,
                  onPressed: _pasteFromClipboard,
                  icon: const Icon(Icons.content_paste, size: 17),
                  color: const Color(0xFFF4F4F4),
                ),
              ],
            ),
          ),
          Expanded(
            child: GestureDetector(
              onLongPress: _showTerminalMenu,
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: widget.settings,
                  builder: (context, _) => TerminalView(
                    _terminal,
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
