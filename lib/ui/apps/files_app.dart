import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app_scope.dart';
import '../../core/theme.dart';
import '../../models/window_state.dart';
import '../../services/linux_runtime.dart';

/// Browses Android shared storage and can hand the current directory to the
/// Linux guest, where it is mounted at /mnt/android.
class FilesApp extends StatefulWidget {
  const FilesApp({super.key, required this.runtime});

  final LinuxRuntime runtime;

  @override
  State<FilesApp> createState() => _FilesAppState();
}

class _FilesAppState extends State<FilesApp> {
  static const String _root = '/storage/emulated/0';

  String _path = _root;
  List<FileSystemEntity> _entries = const <FileSystemEntity>[];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final dir = Directory(_path);
      final entries = dir.listSync(followLinks: false)
        ..sort((a, b) {
          final aDir = a is Directory;
          final bDir = b is Directory;
          if (aDir != bDir) return aDir ? -1 : 1;
          return a.path.toLowerCase().compareTo(b.path.toLowerCase());
        });
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _entries = const <FileSystemEntity>[];
        _error = 'Cannot read $_path. Grant “All files access” to MicroOS.';
      });
    }
  }

  String get _guestPath => _path.replaceFirst(_root, '/mnt/android');

  void _openInTerminal() {
    final scope = AppScope.of(context);
    final screen = MediaQuery.sizeOf(context);
    scope.desktop.open(
      AppId.terminal,
      screen: screen,
      args: <String>[
        '/bin/bash',
        '-lc',
        'cd ${_shellQuote(_guestPath)} && exec bash -l',
      ],
    );
  }

  String _shellQuote(String value) =>
      "'${value.replaceAll("'", "'\\''")}'";

  Future<void> _requestAccess() async {
    await Permission.manageExternalStorage.request();
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final canGoUp = _path != _root && _path.length > _root.length;

    return Container(
      color: MicroColors.panelSolid,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0x1AFFFFFF))),
            ),
            child: Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: canGoUp
                      ? () {
                          setState(() => _path = Directory(_path).parent.path);
                          _load();
                        }
                      : null,
                  icon: const Icon(Icons.arrow_upward, size: 18),
                ),
                Expanded(
                  child: Text(
                    _guestPath,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MicroColors.subtle,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _openInTerminal,
                  child: const Text('Terminal here', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: MicroColors.subtle, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _requestAccess,
                    child: const Text('Grant all-files access'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _entries.length,
              itemBuilder: (context, index) {
                final entry = _entries[index];
                final name = entry.path.split('/').last;
                final isDir = entry is Directory;
                return ListTile(
                  dense: true,
                  leading: Icon(
                    isDir ? Icons.folder_rounded : Icons.insert_drive_file_outlined,
                    color: isDir ? const Color(0xFFF0A32B) : MicroColors.subtle,
                    size: 20,
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(color: MicroColors.text, fontSize: 12),
                  ),
                  onTap: isDir
                      ? () {
                          setState(() => _path = entry.path);
                          _load();
                        }
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
