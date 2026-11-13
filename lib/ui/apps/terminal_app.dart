import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:xterm/xterm.dart';

import '../../core/terminal_profiles.dart';
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

  @override
  void initState() {
    super.initState();
    _addTab();
  }

  void _addTab() {
    final terminal = Terminal(maxLines: 10000);
    final controller = TerminalController();
    Pty? pty;

    if (widget.runtime.isReady) {
      try {
        pty = widget.runtime.startShell(argv: widget.argv);
        pty.output.cast<List<int>>().listen((data) {
          terminal.write(String.fromCharCodes(data));
        });
        terminal.onOutput = (data) => pty?.write(const SystemEncoding().encode(data));
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
    tab.pty?.kill();
    setState(() {
      if (_active >= _tabs.length) _active = _tabs.length - 1;
    });
  }

  @override
  void dispose() {
    for (final t in _tabs) {
      t.pty?.kill();
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
                    TerminalView(
                      tab.terminal,
                      controller: tab.controller,
                      theme: profile.toXterm(),
                      textStyle: TerminalStyle(
                        fontSize: widget.settings.terminalFontSize,
                        fontFamily: 'JetBrains Mono',
                      ),
                      autofocus: true,
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
}
