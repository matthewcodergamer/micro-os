import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

import '../../core/theme.dart';
import '../../services/linux_runtime.dart';

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
  });

  final LinuxRuntime runtime;
  final List<String>? argv;

  @override
  State<TerminalApp> createState() => _TerminalAppState();
}

class _TerminalAppState extends State<TerminalApp> {
  final Terminal _terminal = Terminal(maxLines: 8000);

  Pty? _pty;
  StreamSubscription? _output;
  String? _error;
  bool _ctrlArmed = false;

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
      _output = pty.output.listen(
        (data) => _terminal.write(utf8.decode(data, allowMalformed: true)),
        onError: (Object e) => _terminal.write('\r\n[pty error: $e]\r\n'),
        onDone: () => _terminal.write('\r\n[process exited]\r\n'),
      );
    } catch (e) {
      setState(() => _error = '$e');
    }
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
      color: const Color(0xFF0B0E14),
      child: Column(
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF141822),
              border: Border(bottom: BorderSide(color: Color(0x1AFFFFFF))),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal, size: 15, color: MicroColors.subtle),
                const SizedBox(width: 7),
                const Expanded(
                  child: Text('Terminal', style: TextStyle(color: MicroColors.subtle, fontSize: 11)),
                ),
                IconButton(
                  tooltip: 'Paste from Android clipboard',
                  visualDensity: VisualDensity.compact,
                  onPressed: _pasteFromClipboard,
                  icon: const Icon(Icons.content_paste, size: 17),
                  color: MicroColors.text,
                ),
              ],
            ),
          ),
          Expanded(
            child: GestureDetector(
              onLongPress: _showTerminalMenu,
              child: TerminalView(
                _terminal,
                autofocus: true,
                padding: const EdgeInsets.all(8),
                backgroundOpacity: 1,
                theme: _theme,
              ),
            ),
          ),
          // Termux-style developer keys stay available above the soft keyboard.
          Container(
            height: 44,
            decoration: const BoxDecoration(
              color: Color(0xFF141822),
              border: Border(top: BorderSide(color: Color(0x1AFFFFFF))),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _extraKey('Tab', '\t'),
                  _extraKey('↑', '\x1b[A'),
                  _extraKey('↓', '\x1b[B'),
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

const TerminalTheme _theme = TerminalTheme(
  cursor: Color(0xFF7FD1FF),
  selection: Color(0x553D7EFF),
  foreground: Color(0xFFE6E9F0),
  background: Color(0xFF0B0E14),
  black: Color(0xFF1B1F27),
  red: Color(0xFFFF6B6B),
  green: Color(0xFF4ADE80),
  yellow: Color(0xFFFACC15),
  blue: Color(0xFF60A5FA),
  magenta: Color(0xFFC084FC),
  cyan: Color(0xFF22D3EE),
  white: Color(0xFFE5E7EB),
  brightBlack: Color(0xFF4B5563),
  brightRed: Color(0xFFFF8A8A),
  brightGreen: Color(0xFF86EFAC),
  brightYellow: Color(0xFFFDE68A),
  brightBlue: Color(0xFF93C5FD),
  brightMagenta: Color(0xFFD8B4FE),
  brightCyan: Color(0xFF67E8F9),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0x66FACC15),
  searchHitBackgroundCurrent: Color(0x99FACC15),
  searchHitForeground: Color(0xFF0B0E14),
);
