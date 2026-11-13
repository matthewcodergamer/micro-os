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

  void _addTab() {
    final terminal = Terminal(maxLines: 1000);
    final controller = TerminalController();
    Pty? pty;

    if (widget.runtime.isReady) {
      try {
        pty = widget.runtime.startShell(argv: widget.argv);
        // Decode byte chunks incrementally, retaining partial UTF-8 sequences.
        pty.output
            .map<List<int>>((chunk) => chunk)
            .transform(utf8.decoder)
            .listen((text) => terminal.write(text));
        terminal.onOutput = (data) => pty?.write(utf8.encode(data));
        terminal.onResize = (w, h, pw, ph) => pty?.resize(h, w);
      } catch (_) {}
    }

    final tab = _Tab(
      terminal: terminal,
      controller: controller,
      pty: pty,
      title: 'bash',
    );
    setState(() {
      _tabs.add(tab);
      _active = _tabs.length - 1;
    });
    widget.onTitle?.call('root - bash - 80x24');
  }

  void _closeTab(int index) {
    if (_tabs.length <= 1) return;
    final tab = _tabs.removeAt(index);
    tab.dispose();
    setState(() {
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
      final selectedText = tab.terminal.buffer.getText(selection);
      if (selectedText.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: selectedText));
      }
      tab.controller.clearSelection();
    } else if (action == _TerminalMenuAction.paste) {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clipboard?.text;
      if (text != null && text.isNotEmpty) {
        await _enqueuePaste(tab, text);
      }
    }
  }


  // Clipboard text is kept in a bounded per-tab queue and delivered in small
  // Unicode-safe pieces. Pty.write is synchronous in flutter_pty, so pacing
  // gives the PTY/event loop time to drain between writes instead of flooding it.
  static const int _maxQueuedPasteCodeUnits = 2 * 1024 * 1024;
  static const Duration _pasteChunkDelay = Duration(milliseconds: 4);

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
        for (final chunk in splitTerminalPaste(text)) {
          if (!mounted || tab.disposed || tab.pty == null) break;
          tab.terminal.textInput(chunk);
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
            (tab.pendingPasteCodeUnits - text.length).clamp(0, _maxQueuedPasteCodeUnits);
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
                            child: Text(
                              _tabs[i].title,
                              style: TextStyle(
                                color: selected ? MicroColors.text : MicroColors.subtle,
                                fontSize: 12,
                                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                              ),
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
                        theme: profile.toXterm(),
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
          ],
        );
      },
    );
  }
}

enum _TerminalMenuAction { copy, paste }

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
  String title;
  Future<void> pasteQueue = Future<void>.value();
  int pendingPasteCodeUnits = 0;
  bool disposed = false;

  void dispose() {
    if (disposed) return;
    disposed = true;
    pendingPasteCodeUnits = 0;
    try {
      pty?.kill();
    } catch (_) {
      // The PTY may already have exited.
    }
  }
}
