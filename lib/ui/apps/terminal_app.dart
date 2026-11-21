import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

import '../../core/terminal_profiles.dart';
import '../../core/terminal_paste.dart';
import '../../core/theme.dart';
import '../../services/linux_runtime.dart';
import '../../services/settings_store.dart';

/// Multi-terminal workspace with a Terminal.app style tab strip.
class TerminalTabsApp extends StatefulWidget {
  const TerminalTabsApp({
    super.key,
    required this.runtime,
    this.argv,
    required this.settings,
    this.onTitle,
  });

  final LinuxRuntime runtime;
  final List<String>? argv;
  final SettingsStore settings;
  final ValueChanged<String>? onTitle;

  @override
  State<TerminalTabsApp> createState() => _TerminalTabsAppState();
}

class _TerminalTabsAppState extends State<TerminalTabsApp> {
  final List<_Tab> _tabs = [];
  int _active = 0;
  final Set<int> _activePointers = <int>{};
  Timer? _selectionMenuTimer;

  @override
  void initState() {
    super.initState();
    _addTab();
  }

  void _addTab({List<String>? argv, String title = 'bash'}) {
    final terminal = Terminal(maxLines: 1000);
    final controller = TerminalController();
    Pty? pty;
    late final _Tab tab;

    if (widget.runtime.isReady) {
      try {
        pty = widget.runtime.startShell(argv: argv ?? widget.argv);
        // Decode byte chunks incrementally, retaining partial UTF-8 sequences.
        pty.output
            .map<List<int>>((chunk) => chunk)
            .transform(utf8.decoder)
            .listen((text) => terminal.write(text));
        terminal.onOutput = (data) => _sendTerminalInput(tab, data);
        terminal.onResize = (w, h, pw, ph) => pty?.resize(h, w);
      } catch (_) {}
    }

    tab = _Tab(
      terminal: terminal,
      controller: controller,
      pty: pty,
      title: title,
    );
    setState(() {
      _tabs.add(tab);
      _active = _tabs.length - 1;
    });
    widget.onTitle?.call('root - $title - 80x24');
  }

  void _openNewOpenCodeSession() {
    _addTab(
      argv: <String>['/bin/bash', '-lc', 'exec opencode'],
      title: 'OpenCode · New session',
    );
  }

  void _openOpenCodeSessionList() {
    _addTab(
      argv: <String>[
        '/bin/bash',
        '-lc',
        'exec opencode session list --max-count 50',
      ],
      title: 'OpenCode · Sessions',
    );
  }

  Future<void> _resumeOpenCodeSession() async {
    final idController = TextEditingController();
    final sessionId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: MicroColors.windowBody,
        title: const Text('Resume OpenCode session'),
        content: TextField(
          controller: idController,
          autofocus: true,
          style: const TextStyle(color: MicroColors.text),
          decoration: const InputDecoration(
            hintText: 'Paste session ID (ses_...)',
            hintStyle: TextStyle(color: MicroColors.subtle),
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(idController.text.trim()),
            child: const Text('Resume'),
          ),
        ],
      ),
    );
    idController.dispose();
    if (!mounted || sessionId == null || sessionId.isEmpty) return;
    if (!RegExp(r'^[A-Za-z0-9_-]+
    if (index < 0 || index >= _tabs.length) return;
    final tab = _tabs.removeAt(index);
    tab.dispose();
    if (_tabs.isEmpty) {
      setState(() => _active = 0);
      _addTab();
      return;
    }
    setState(() {
      if (_active > index) _active--;
      if (_active >= _tabs.length) _active = _tabs.length - 1;
    });
  }

  void _onTerminalPointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    _selectionMenuTimer?.cancel();
    if (_activePointers.length != 1) return;

    final position = event.position;
    _selectionMenuTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted || _tabs.isEmpty) return;
      final tab = _tabs[_active];
      if (tab.controller.selection == null) return;
      _showTerminalSelectionMenu(position, tab);
    });
  }

  void _onTerminalPointerUp(PointerEvent event) {
    _activePointers.remove(event.pointer);
    _selectionMenuTimer?.cancel();
  }

  Future<void> _showTerminalSelectionMenu(Offset globalPosition, _Tab tab) async {
    final selection = tab.controller.selection;
    if (selection == null || !mounted) return;

    final screen = MediaQuery.sizeOf(context);
    final action = await showMenu<_TerminalMenuAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        screen.width - globalPosition.dx,
        screen.height - globalPosition.dy,
      ),
      items: [
        const PopupMenuItem(
          value: _TerminalMenuAction.copy,
          child: Row(
            children: [
              Icon(Icons.copy_rounded, size: 18),
              SizedBox(width: 10),
              Text('Copy'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: _TerminalMenuAction.paste,
          child: Row(
            children: [
              Icon(Icons.content_paste_rounded, size: 18),
              SizedBox(width: 10),
              Text('Paste'),
            ],
          ),
        ),
      ],
    );

    if (!mounted || action == null) return;
    if (action == _TerminalMenuAction.copy) {
      await _copyTab(tab);
    } else if (action == _TerminalMenuAction.paste) {
      await _pasteTab(tab);
    }
  }

  _Tab? get _activeTab {
    if (_tabs.isEmpty) return null;
    return _tabs[_active.clamp(0, _tabs.length - 1).toInt()];
  }

  Future<void> _copyTab(_Tab tab) async {
    final selection = tab.controller.selection;
    final text = selection == null ? '' : tab.terminal.buffer.getText(selection);
    if (text.isEmpty) {
      _notify('Long-press or drag to select text first.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    tab.controller.clearSelection();
    _notify('Copied ${text.length} characters.');
  }

  Future<void> _pasteTab(_Tab tab) async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboard?.text;
    if (text == null || text.isEmpty) {
      _notify('Clipboard is empty.');
      return;
    }
    await _enqueuePaste(tab, text);
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1400),
      ));
  }

  void _copyActive() {
    final tab = _activeTab;
    if (tab != null) unawaited(_copyTab(tab));
  }

  void _pasteActive() {
    final tab = _activeTab;
    if (tab != null) unawaited(_pasteTab(tab));
  }

  void _sendKey(TerminalKey key, {bool ctrl = false}) {
    _activeTab?.terminal.keyInput(key, ctrl: ctrl);
  }

  void _sendText(String text) {
    _activeTab?.terminal.textInput(text);
  }

  /// Scrolls the scrollback buffer, or sends wheel/arrow input when the
  /// full-screen alternate buffer (OpenCode, vim, less) owns the screen.
  void _scrollActive(int lines) {
    final tab = _activeTab;
    if (tab == null || lines == 0) return;

    if (tab.terminal.isUsingAltBuffer) {
      final up = lines < 0;
      final button = up ? TerminalMouseButton.wheelUp : TerminalMouseButton.wheelDown;
      for (var i = 0; i < lines.abs().clamp(1, 6); i++) {
        final handled = tab.terminal.mouseInput(
          button,
          TerminalMouseButtonState.down,
          const CellOffset(0, 0),
        );
        if (!handled) {
          tab.terminal.keyInput(up ? TerminalKey.arrowUp : TerminalKey.arrowDown);
        }
      }
      return;
    }

    if (!tab.scrollController.hasClients) return;
    final position = tab.scrollController.position;
    final target = (position.pixels + lines * 48)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    position.jumpTo(target);
  }


  // Clipboard and platform keyboard pastes share the same bounded input path.
  // flutter_pty exposes synchronous writes rather than a drain acknowledgement,
  // so short paced writes are used as conservative flow control.
  static const int _pasteChunkSize = 500;
  static const int _maxQueuedPasteCodeUnits = 2 * 1024 * 1024;
  static const Duration _pasteChunkDelay = Duration(milliseconds: 4);

  void _sendTerminalInput(_Tab tab, String text) {
    if (text.isEmpty || tab.disposed || tab.pty == null) return;
    if (text.length > _pasteChunkSize) {
      unawaited(_enqueuePaste(tab, text));
      return;
    }
    try {
      tab.pty!.write(utf8.encode(text));
    } catch (error) {
      if (mounted && !tab.disposed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Terminal input failed: $error')),
        );
      }
    }
  }

  Future<void> _enqueuePaste(_Tab tab, String text) async {
    if (tab.disposed || tab.pty == null) return;
    if (tab.pendingPasteCodeUnits + text.length > _maxQueuedPasteCodeUnits) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paste queue is full. Wait for the current paste to finish.')),
        );
      }
      return;
    }

    tab.pendingPasteCodeUnits += text.length;
    final paste = tab.pasteQueue.then((_) async {
      try {
        for (final chunk in splitTerminalPaste(
          text,
          maxCodeUnits: _pasteChunkSize,
        )) {
          if (!mounted || tab.disposed || tab.pty == null) break;
          tab.pty!.write(utf8.encode(chunk));
          await Future<void>.delayed(_pasteChunkDelay);
        }
      } catch (error) {
        if (mounted && !tab.disposed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Paste stopped: $error')),
          );
        }
      } finally {
        tab.pendingPasteCodeUnits =
            (tab.pendingPasteCodeUnits - text.length).clamp(0, _maxQueuedPasteCodeUnits).toInt();
      }
    });
    tab.pasteQueue = paste;
    await paste;
  }

  @override
  void dispose() {
    _selectionMenuTimer?.cancel();
    for (final t in _tabs) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) {
        if (!widget.runtime.isReady) {
          return const Center(
            child: Text(
              'Install Linux first to use the Terminal.',
              style: TextStyle(color: MicroColors.subtle),
            ),
          );
        }

        final profile = profileById(widget.settings.terminalProfile);

        return Column(
          children: [
            // Tab strip
            Container(
              height: 36,
              color: MicroColors.windowHeader,
              child: Row(
                children: [
                  Expanded(
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _tabs.length,
                      itemBuilder: (_, i) {
                        final selected = i == _active;
                        return GestureDetector(
                          onTap: () => setState(() => _active = i),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected ? MicroColors.windowBody : Colors.transparent,
                              border: Border(
                                bottom: BorderSide(
                                  color: selected ? MicroColors.accent : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _tabs[i].title,
                                  style: TextStyle(
                                    color: selected ? MicroColors.text : MicroColors.subtle,
                                    fontSize: 12,
                                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () => _closeTab(i),
                                  child: Padding(
                                    padding: const EdgeInsets.all(3),
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: 13,
                                      color: selected ? MicroColors.text : MicroColors.subtle,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_rounded, size: 18),
                    color: MicroColors.text,
                    onPressed: _addTab,
                  ),
                ],
              ),
            ),
            // Terminal body
            Expanded(
              child: IndexedStack(
                index: _active,
                children: [
                  for (final tab in _tabs)
                    Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: _onTerminalPointerDown,
                      onPointerUp: _onTerminalPointerUp,
                      onPointerCancel: _onTerminalPointerUp,
                      child: TerminalView(
                        tab.terminal,
                        controller: tab.controller,
                        scrollController: tab.scrollController,
                        theme: profile.toXterm(),
                        cursorType: TerminalCursorType.block,
                        alwaysShowCursor: true,
                        textStyle: TerminalStyle(
                          fontSize: widget.settings.terminalFontSize,
                          fontFamily: 'JetBrains Mono',
                        ),
                        autofocus: true,
                      ),
                    ),
                ],
              ),
            ),
            _TerminalKeyBar(
              onNewOpenCode: _openNewOpenCodeSession,
              onListOpenCodeSessions: _openOpenCodeSessionList,
              onResumeOpenCode: _resumeOpenCodeSession,
              onCopy: _copyActive,
              onPaste: _pasteActive,
              onScrollUp: () => _scrollActive(-4),
              onScrollDown: () => _scrollActive(4),
              onKey: (key, ctrl) => _sendKey(key, ctrl: ctrl),
              onText: _sendText,
            ),
          ],
        );
      },
    );
  }
}

enum _TerminalMenuAction { copy, paste }

/// Always-visible accessory row. xterm's gestures handle long-press and drag
/// selection, but on a phone the copy affordance and scrollback must be
/// reachable without a hidden menu or a mouse wheel.
class _TerminalKeyBar extends StatelessWidget {
  const _TerminalKeyBar({
    required this.onNewOpenCode,
    required this.onListOpenCodeSessions,
    required this.onResumeOpenCode,
    required this.onCopy,
    required this.onPaste,
    required this.onScrollUp,
    required this.onScrollDown,
    required this.onKey,
    required this.onText,
  });

  final VoidCallback onNewOpenCode;
  final VoidCallback onListOpenCodeSessions;
  final VoidCallback onResumeOpenCode;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onScrollUp;
  final VoidCallback onScrollDown;
  final void Function(TerminalKey key, bool ctrl) onKey;
  final ValueChanged<String> onText;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      color: MicroColors.windowHeader,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        children: [
          _KeyChip(label: 'New AI', icon: Icons.auto_awesome_rounded, onTap: onNewOpenCode),
          _KeyChip(label: 'AI Sessions', icon: Icons.history_rounded, onTap: onListOpenCodeSessions),
          _KeyChip(label: 'Resume AI', icon: Icons.play_arrow_rounded, onTap: onResumeOpenCode),
          const _KeyDivider(),
          _KeyChip(label: 'Copy', icon: Icons.copy_rounded, onTap: onCopy),
          _KeyChip(label: 'Paste', icon: Icons.content_paste_rounded, onTap: onPaste),
          const _KeyDivider(),
          _KeyChip(label: 'Esc', onTap: () => onKey(TerminalKey.escape, false)),
          _KeyChip(label: 'Tab', onTap: () => onKey(TerminalKey.tab, false)),
          _KeyChip(label: 'PgUp', icon: Icons.keyboard_arrow_up_rounded, onTap: onScrollUp),
          _KeyChip(label: 'PgDn', icon: Icons.keyboard_arrow_down_rounded, onTap: onScrollDown),
          _KeyChip(label: '←', onTap: () => onKey(TerminalKey.arrowLeft, false)),
          _KeyChip(label: '↑', onTap: () => onKey(TerminalKey.arrowUp, false)),
          _KeyChip(label: '↓', onTap: () => onKey(TerminalKey.arrowDown, false)),
          _KeyChip(label: '→', onTap: () => onKey(TerminalKey.arrowRight, false)),
          _KeyChip(label: '/', onTap: () => onText('/')),
          _KeyChip(label: '^C', onTap: () => onKey(TerminalKey.keyC, true)),
          _KeyChip(label: '^D', onTap: () => onKey(TerminalKey.keyD, true)),
        ],
      ),
    );
  }
}

class _KeyChip extends StatelessWidget {
  const _KeyChip({required this.label, this.icon, required this.onTap});

  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: MicroColors.windowBody,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          canRequestFocus: false,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: MicroColors.text),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    color: MicroColors.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KeyDivider extends StatelessWidget {
  const _KeyDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      color: MicroColors.subtle.withValues(alpha: 0.25),
    );
  }
}

class _Tab {
  _Tab({
    required this.terminal,
    required this.controller,
    this.pty,
    required this.title,
  });

  final Terminal terminal;
  final TerminalController controller;
  final Pty? pty;
  final ScrollController scrollController = ScrollController();
  String title;
  Future<void> pasteQueue = Future<void>.value();
  int pendingPasteCodeUnits = 0;
  bool disposed = false;

  void dispose() {
    if (disposed) return;
    disposed = true;
    pendingPasteCodeUnits = 0;
    scrollController.dispose();
    try {
      pty?.kill();
    } catch (_) {
      // The PTY may already have exited.
    }
  }
}
).hasMatch(sessionId)) {
      _notify('That session ID contains unsupported characters.');
      return;
    }
    _addTab(
      argv: <String>[
        '/bin/bash',
        '-lc',
        'exec opencode --session "$1"',
        'misty-opencode-resume',
        sessionId,
      ],
      title: 'OpenCode · Resume',
    );
  }

  void _closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final tab = _tabs.removeAt(index);
    tab.dispose();
    if (_tabs.isEmpty) {
      setState(() => _active = 0);
      _addTab();
      return;
    }
    setState(() {
      if (_active > index) _active--;
      if (_active >= _tabs.length) _active = _tabs.length - 1;
    });
  }

  void _onTerminalPointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    _selectionMenuTimer?.cancel();
    if (_activePointers.length != 1) return;

    final position = event.position;
    _selectionMenuTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted || _tabs.isEmpty) return;
      final tab = _tabs[_active];
      if (tab.controller.selection == null) return;
      _showTerminalSelectionMenu(position, tab);
    });
  }

  void _onTerminalPointerUp(PointerEvent event) {
    _activePointers.remove(event.pointer);
    _selectionMenuTimer?.cancel();
  }

  Future<void> _showTerminalSelectionMenu(Offset globalPosition, _Tab tab) async {
    final selection = tab.controller.selection;
    if (selection == null || !mounted) return;

    final screen = MediaQuery.sizeOf(context);
    final action = await showMenu<_TerminalMenuAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        screen.width - globalPosition.dx,
        screen.height - globalPosition.dy,
      ),
      items: [
        const PopupMenuItem(
          value: _TerminalMenuAction.copy,
          child: Row(
            children: [
              Icon(Icons.copy_rounded, size: 18),
              SizedBox(width: 10),
              Text('Copy'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: _TerminalMenuAction.paste,
          child: Row(
            children: [
              Icon(Icons.content_paste_rounded, size: 18),
              SizedBox(width: 10),
              Text('Paste'),
            ],
          ),
        ),
      ],
    );

    if (!mounted || action == null) return;
    if (action == _TerminalMenuAction.copy) {
      await _copyTab(tab);
    } else if (action == _TerminalMenuAction.paste) {
      await _pasteTab(tab);
    }
  }

  _Tab? get _activeTab {
    if (_tabs.isEmpty) return null;
    return _tabs[_active.clamp(0, _tabs.length - 1).toInt()];
  }

  Future<void> _copyTab(_Tab tab) async {
    final selection = tab.controller.selection;
    final text = selection == null ? '' : tab.terminal.buffer.getText(selection);
    if (text.isEmpty) {
      _notify('Long-press or drag to select text first.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    tab.controller.clearSelection();
    _notify('Copied ${text.length} characters.');
  }

  Future<void> _pasteTab(_Tab tab) async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboard?.text;
    if (text == null || text.isEmpty) {
      _notify('Clipboard is empty.');
      return;
    }
    await _enqueuePaste(tab, text);
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1400),
      ));
  }

  void _copyActive() {
    final tab = _activeTab;
    if (tab != null) unawaited(_copyTab(tab));
  }

  void _pasteActive() {
    final tab = _activeTab;
    if (tab != null) unawaited(_pasteTab(tab));
  }

  void _sendKey(TerminalKey key, {bool ctrl = false}) {
    _activeTab?.terminal.keyInput(key, ctrl: ctrl);
  }

  void _sendText(String text) {
    _activeTab?.terminal.textInput(text);
  }

  /// Scrolls the scrollback buffer, or sends wheel/arrow input when the
  /// full-screen alternate buffer (OpenCode, vim, less) owns the screen.
  void _scrollActive(int lines) {
    final tab = _activeTab;
    if (tab == null || lines == 0) return;

    if (tab.terminal.isUsingAltBuffer) {
      final up = lines < 0;
      final button = up ? TerminalMouseButton.wheelUp : TerminalMouseButton.wheelDown;
      for (var i = 0; i < lines.abs().clamp(1, 6); i++) {
        final handled = tab.terminal.mouseInput(
          button,
          TerminalMouseButtonState.down,
          const CellOffset(0, 0),
        );
        if (!handled) {
          tab.terminal.keyInput(up ? TerminalKey.arrowUp : TerminalKey.arrowDown);
        }
      }
      return;
    }

    if (!tab.scrollController.hasClients) return;
    final position = tab.scrollController.position;
    final target = (position.pixels + lines * 48)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    position.jumpTo(target);
  }


  // Clipboard and platform keyboard pastes share the same bounded input path.
  // flutter_pty exposes synchronous writes rather than a drain acknowledgement,
  // so short paced writes are used as conservative flow control.
  static const int _pasteChunkSize = 500;
  static const int _maxQueuedPasteCodeUnits = 2 * 1024 * 1024;
  static const Duration _pasteChunkDelay = Duration(milliseconds: 4);

  void _sendTerminalInput(_Tab tab, String text) {
    if (text.isEmpty || tab.disposed || tab.pty == null) return;
    if (text.length > _pasteChunkSize) {
      unawaited(_enqueuePaste(tab, text));
      return;
    }
    try {
      tab.pty!.write(utf8.encode(text));
    } catch (error) {
      if (mounted && !tab.disposed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Terminal input failed: $error')),
        );
      }
    }
  }

  Future<void> _enqueuePaste(_Tab tab, String text) async {
    if (tab.disposed || tab.pty == null) return;
    if (tab.pendingPasteCodeUnits + text.length > _maxQueuedPasteCodeUnits) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paste queue is full. Wait for the current paste to finish.')),
        );
      }
      return;
    }

    tab.pendingPasteCodeUnits += text.length;
    final paste = tab.pasteQueue.then((_) async {
      try {
        for (final chunk in splitTerminalPaste(
          text,
          maxCodeUnits: _pasteChunkSize,
        )) {
          if (!mounted || tab.disposed || tab.pty == null) break;
          tab.pty!.write(utf8.encode(chunk));
          await Future<void>.delayed(_pasteChunkDelay);
        }
      } catch (error) {
        if (mounted && !tab.disposed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Paste stopped: $error')),
          );
        }
      } finally {
        tab.pendingPasteCodeUnits =
            (tab.pendingPasteCodeUnits - text.length).clamp(0, _maxQueuedPasteCodeUnits).toInt();
      }
    });
    tab.pasteQueue = paste;
    await paste;
  }

  @override
  void dispose() {
    _selectionMenuTimer?.cancel();
    for (final t in _tabs) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) {
        if (!widget.runtime.isReady) {
          return const Center(
            child: Text(
              'Install Linux first to use the Terminal.',
              style: TextStyle(color: MicroColors.subtle),
            ),
          );
        }

        final profile = profileById(widget.settings.terminalProfile);

        return Column(
          children: [
            // Tab strip
            Container(
              height: 36,
              color: MicroColors.windowHeader,
              child: Row(
                children: [
                  Expanded(
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _tabs.length,
                      itemBuilder: (_, i) {
                        final selected = i == _active;
                        return GestureDetector(
                          onTap: () => setState(() => _active = i),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected ? MicroColors.windowBody : Colors.transparent,
                              border: Border(
                                bottom: BorderSide(
                                  color: selected ? MicroColors.accent : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _tabs[i].title,
                                  style: TextStyle(
                                    color: selected ? MicroColors.text : MicroColors.subtle,
                                    fontSize: 12,
                                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () => _closeTab(i),
                                  child: Padding(
                                    padding: const EdgeInsets.all(3),
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: 13,
                                      color: selected ? MicroColors.text : MicroColors.subtle,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_rounded, size: 18),
                    color: MicroColors.text,
                    onPressed: _addTab,
                  ),
                ],
              ),
            ),
            // Terminal body
            Expanded(
              child: IndexedStack(
                index: _active,
                children: [
                  for (final tab in _tabs)
                    Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: _onTerminalPointerDown,
                      onPointerUp: _onTerminalPointerUp,
                      onPointerCancel: _onTerminalPointerUp,
                      child: TerminalView(
                        tab.terminal,
                        controller: tab.controller,
                        scrollController: tab.scrollController,
                        theme: profile.toXterm(),
                        cursorType: TerminalCursorType.block,
                        alwaysShowCursor: true,
                        textStyle: TerminalStyle(
                          fontSize: widget.settings.terminalFontSize,
                          fontFamily: 'JetBrains Mono',
                        ),
                        autofocus: true,
                      ),
                    ),
                ],
              ),
            ),
            _TerminalKeyBar(
              onCopy: _copyActive,
              onPaste: _pasteActive,
              onScrollUp: () => _scrollActive(-4),
              onScrollDown: () => _scrollActive(4),
              onKey: (key, ctrl) => _sendKey(key, ctrl: ctrl),
              onText: _sendText,
            ),
          ],
        );
      },
    );
  }
}

enum _TerminalMenuAction { copy, paste }

/// Always-visible accessory row. xterm's gestures handle long-press and drag
/// selection, but on a phone the copy affordance and scrollback must be
/// reachable without a hidden menu or a mouse wheel.
class _TerminalKeyBar extends StatelessWidget {
  const _TerminalKeyBar({
    required this.onCopy,
    required this.onPaste,
    required this.onScrollUp,
    required this.onScrollDown,
    required this.onKey,
    required this.onText,
  });

  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onScrollUp;
  final VoidCallback onScrollDown;
  final void Function(TerminalKey key, bool ctrl) onKey;
  final ValueChanged<String> onText;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      color: MicroColors.windowHeader,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        children: [
          _KeyChip(label: 'Copy', icon: Icons.copy_rounded, onTap: onCopy),
          _KeyChip(label: 'Paste', icon: Icons.content_paste_rounded, onTap: onPaste),
          const _KeyDivider(),
          _KeyChip(label: 'Esc', onTap: () => onKey(TerminalKey.escape, false)),
          _KeyChip(label: 'Tab', onTap: () => onKey(TerminalKey.tab, false)),
          _KeyChip(label: 'PgUp', icon: Icons.keyboard_arrow_up_rounded, onTap: onScrollUp),
          _KeyChip(label: 'PgDn', icon: Icons.keyboard_arrow_down_rounded, onTap: onScrollDown),
          _KeyChip(label: '←', onTap: () => onKey(TerminalKey.arrowLeft, false)),
          _KeyChip(label: '↑', onTap: () => onKey(TerminalKey.arrowUp, false)),
          _KeyChip(label: '↓', onTap: () => onKey(TerminalKey.arrowDown, false)),
          _KeyChip(label: '→', onTap: () => onKey(TerminalKey.arrowRight, false)),
          _KeyChip(label: '/', onTap: () => onText('/')),
          _KeyChip(label: '^C', onTap: () => onKey(TerminalKey.keyC, true)),
          _KeyChip(label: '^D', onTap: () => onKey(TerminalKey.keyD, true)),
        ],
      ),
    );
  }
}

class _KeyChip extends StatelessWidget {
  const _KeyChip({required this.label, this.icon, required this.onTap});

  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: MicroColors.windowBody,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          canRequestFocus: false,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: MicroColors.text),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    color: MicroColors.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KeyDivider extends StatelessWidget {
  const _KeyDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      color: MicroColors.subtle.withValues(alpha: 0.25),
    );
  }
}

class _Tab {
  _Tab({
    required this.terminal,
    required this.controller,
    this.pty,
    required this.title,
  });

  final Terminal terminal;
  final TerminalController controller;
  final Pty? pty;
  final ScrollController scrollController = ScrollController();
  String title;
  Future<void> pasteQueue = Future<void>.value();
  int pendingPasteCodeUnits = 0;
  bool disposed = false;

  void dispose() {
    if (disposed) return;
    disposed = true;
    pendingPasteCodeUnits = 0;
    scrollController.dispose();
    try {
      pty?.kill();
    } catch (_) {
      // The PTY may already have exited.
    }
  }
}
