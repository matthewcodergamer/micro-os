import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

import '../../core/opencode_themes.dart';
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

  void _addTab() {
    final terminal = Terminal(maxLines: 1000);
    final controller = TerminalController();
    final profile = profileById(widget.settings.terminalProfile);
    final openCode = resolveOpenCodeTheme(
      widget.settings.openCodeTheme,
      profile,
    );
    Pty? pty;
    late final _Tab tab;

    if (widget.runtime.isReady) {
      try {
        pty = widget.runtime.startShell(
          argv: widget.argv,
          extraEnv: <String, String>{
            // OpenCode reads this inline CLI config on every launch. The user
            // can choose White/Graphite/Ocean/Forest/... independently of the
            // shell, or follow the selected macOS Terminal profile.
            'OPENCODE_CLI_CONFIG_CONTENT': jsonEncode(<String, Object>{
              'theme': <String, String>{
                'name': openCode.name,
                'mode': openCode.mode,
              },
              'highlights': false,
            }),
          },
        );
        // Decode byte chunks incrementally, retaining partial UTF-8 sequences.
        pty.output
            .map<List<int>>((chunk) => chunk)
            .transform(utf8.decoder)
            .listen((text) => terminal.write(text));
        terminal.onOutput = (data) => _sendTerminalInput(tab, data);
        // The shell should see one stable window size after the keyboard and
        // window animation settle, not a SIGWINCH storm on every layout frame.
        terminal.onResize = (w, h, pw, ph) => tab.scheduleResize(h, w);
      } catch (_) {}
    }

    tab = _Tab(
      terminal: terminal,
      controller: controller,
      pty: pty,
      title: 'bash',
    );
    setState(() {
      _tabs.add(tab);
      _active = _tabs.length - 1;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || tab.disposed) return;
      tab.focusNode.requestFocus();
    });
    widget.onTitle?.call('root - bash - 80x24');
  }

  void _closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final tab = _tabs.removeAt(index);
    if (_tabs.isEmpty) {
      setState(() => _active = 0);
      _addTab();
      WidgetsBinding.instance.addPostFrameCallback((_) => tab.dispose());
      return;
    }
    setState(() {
      if (_active > index) _active--;
      if (_active >= _tabs.length) _active = _tabs.length - 1;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      tab.dispose();
      if (!mounted || _tabs.isEmpty) return;
      _tabs[_active.clamp(0, _tabs.length - 1).toInt()].focusNode
          .requestFocus();
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
            // macOS Terminal-style tab strip: graphite chrome, a selected tab
            // painted in the profile's own background, and a compact new-tab
            // button. The window's traffic lights stay in the title bar above.
            Container(
              height: 38,
              padding: const EdgeInsets.only(left: 7, right: 4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF313136), Color(0xFF242428)],
                ),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.07),
                    width: 0.7,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _tabs.length,
                      itemBuilder: (_, i) {
                        final selected = i == _active;
                        return GestureDetector(
                          onTap: () {
                            setState(() => _active = i);
                            _tabs[i].focusNode.requestFocus();
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            curve: Curves.easeOutCubic,
                            margin: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 5,
                            ),
                            padding: const EdgeInsets.only(
                              left: 10,
                              right: 4,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? profile.background
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                color: selected
                                    ? Colors.white.withValues(alpha: 0.16)
                                    : Colors.transparent,
                                width: 0.7,
                              ),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.30,
                                        ),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.terminal_rounded,
                                  size: 12,
                                  color: selected
                                      ? profile.foreground.withValues(
                                          alpha: 0.82,
                                        )
                                      : Colors.white38,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _tabs[i].title,
                                  style: TextStyle(
                                    color: selected
                                        ? profile.foreground
                                        : Colors.white54,
                                    fontSize: 11.5,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () => _closeTab(i),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: 12,
                                      color: selected
                                          ? profile.foreground.withValues(
                                              alpha: 0.65,
                                            )
                                          : Colors.white38,
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
                  Tooltip(
                    message: 'New tab',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: _addTab,
                      child: const SizedBox(
                        width: 30,
                        height: 30,
                        child: Icon(
                          Icons.add_rounded,
                          size: 17,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Terminal body. Padding inside the black canvas gives the same
            // breathing room as Terminal.app without changing the PTY grid.
            Expanded(
              child: ColoredBox(
                color: profile.background,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(9, 7, 9, 5),
                  child: IndexedStack(
                    index: _active,
                    children: [
                      for (var i = 0; i < _tabs.length; i++)
                        Builder(builder: (context) {
                          final tab = _tabs[i];
                          return Listener(
                            key: ObjectKey(tab),
                            behavior: HitTestBehavior.translucent,
                            onPointerDown: _onTerminalPointerDown,
                            onPointerUp: _onTerminalPointerUp,
                            onPointerCancel: _onTerminalPointerUp,
                            child: TerminalView(
                              tab.terminal,
                              controller: tab.controller,
                              focusNode: tab.focusNode,
                              scrollController: tab.scrollController,
                              theme: profile.toXterm(),
                              cursorType: TerminalCursorType.block,
                              alwaysShowCursor: true,
                              textStyle: TerminalStyle(
                                fontSize: widget.settings.terminalFontSize,
                                fontFamily: 'JetBrains Mono',
                              ),
                              // Only the first tab autofocuses. Every hidden
                              // tab must not compete for the phone keyboard.
                              autofocus: i == 0,
                            ),
                          );
                        }),
                    ],
                  ),
                ),
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
      decoration: BoxDecoration(
        color: MicroColors.windowHeader,
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
            width: 0.7,
          ),
        ),
      ),
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
        color: Colors.white.withValues(alpha: 0.075),
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
  final FocusNode focusNode = FocusNode(debugLabel: 'Misty terminal');
  String title;
  Future<void> pasteQueue = Future<void>.value();
  int pendingPasteCodeUnits = 0;
  bool disposed = false;
  Timer? _resizeTimer;
  int? _pendingRows;
  int? _pendingCols;

  void scheduleResize(int rows, int cols) {
    if (disposed) return;
    _pendingRows = rows;
    _pendingCols = cols;
    _resizeTimer?.cancel();
    _resizeTimer = Timer(const Duration(milliseconds: 260), () {
      final targetRows = _pendingRows;
      final targetCols = _pendingCols;
      if (disposed || targetRows == null || targetCols == null) return;
      try {
        pty?.resize(targetRows, targetCols);
      } catch (_) {
        // The PTY may already have exited.
      }
    });
  }

  void dispose() {
    if (disposed) return;
    disposed = true;
    pendingPasteCodeUnits = 0;
    _resizeTimer?.cancel();
    scrollController.dispose();
    focusNode.dispose();
    try {
      pty?.kill();
    } catch (_) {
      // The PTY may already have exited.
    }
  }
}
