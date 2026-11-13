import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_pty/flutter_pty.dart';

import '../../core/theme.dart';
import '../../services/linux_runtime.dart';

/// Finder-style browser for the real Linux guest filesystem and Android bind mounts.
class FilesApp extends StatefulWidget {
  const FilesApp({super.key, required this.runtime});

  final LinuxRuntime runtime;

  @override
  State<FilesApp> createState() => _FilesAppState();
}

class _FilesAppState extends State<FilesApp> {
  String _path = '/root';
  List<_FileEntry> _entries = const [];
  bool _loading = true;
  bool _listView = false;
  final TextEditingController _searchController = TextEditingController();
  String _search = '';
  String? _error;
  int _request = 0;

  static const _locations = <({String label, String path, IconData icon})>[
    (label: 'Home', path: '/root', icon: Icons.home_rounded),
    (label: 'Downloads', path: '/root/Downloads', icon: Icons.download_rounded),
    (label: 'Phone', path: '/mnt/android', icon: Icons.phone_android_rounded),
    (label: 'Linux root', path: '/', icon: Icons.computer_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FilesApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runtime != widget.runtime) _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });

    if (!widget.runtime.isReady) {
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
          _error = 'Install Linux before browsing files.';
        });
      }
      return;
    }

    Pty? pty;
    StreamSubscription<List<int>>? subscription;
    final bytes = BytesBuilder(copy: false);
    final done = Completer<void>();

    try {
      const script = r'''
if [ ! -d "$1" ]; then
  printf '__MICROOS_DIRECTORY_NOT_FOUND__'
  exit 1
fi
find -- "$1" -mindepth 1 -maxdepth 1 -printf '%y\0%s\0%f\0' 2>/dev/null
''';
      pty = widget.runtime.startShell(
        argv: <String>['/bin/bash', '-lc', script, 'microos-finder', _path],
      );
      subscription = pty.output.listen(
        bytes.add,
        onError: (Object error, StackTrace stack) {
          if (!done.isCompleted) done.completeError(error, stack);
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
      );

      await done.future.timeout(const Duration(seconds: 12));
      final output = utf8.decode(bytes.takeBytes(), allowMalformed: true);
      if (output.contains('__MICROOS_DIRECTORY_NOT_FOUND__')) {
        throw StateError('This folder no longer exists or is not accessible.');
      }

      final parts = output.split('\u0000');
      final entries = <_FileEntry>[];
      for (var i = 0; i + 2 < parts.length; i += 3) {
        final type = parts[i];
        final size = int.tryParse(parts[i + 1]) ?? 0;
        final name = parts[i + 2];
        if (name.isEmpty) continue;
        entries.add(_FileEntry(
          name: name,
          isDirectory: type == 'd',
          isLink: type == 'l',
          size: size,
        ));
      }
      entries.sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      if (mounted && request == _request) {
        setState(() {
          _entries = entries;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted && request == _request) {
        setState(() {
          _error = error is TimeoutException
              ? 'The folder took too long to load.'
              : error.toString().replaceFirst('Bad state: ', '');
          _loading = false;
        });
      }
    } finally {
      await subscription?.cancel();
      pty?.kill();
    }
  }

  String get _parentPath {
    if (_path == '/') return '/';
    final normalized = _path.endsWith('/') ? _path.substring(0, _path.length - 1) : _path;
    final slash = normalized.lastIndexOf('/');
    return slash <= 0 ? '/' : normalized.substring(0, slash);
  }

  void _navigate(String path) {
    if (path == _path) return;
    setState(() => _path = path);
    _load();
  }

  List<_FileEntry> get _visibleEntries {
    final query = _search.trim().toLowerCase();
    if (query.isEmpty) return _entries;
    return _entries.where((entry) => entry.name.toLowerCase().contains(query)).toList(growable: false);
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  void _showFileDetails(_FileEntry entry) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: MicroColors.panelSolid,
        title: Text(entry.name, style: const TextStyle(color: MicroColors.text)),
        content: Text(
          '${entry.isLink ? 'Symbolic link' : 'File'} · ${_formatSize(entry.size)}\n\nPath: $_path/${entry.name}',
          style: const TextStyle(color: MicroColors.subtle),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: MicroColors.sidebar,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Parent folder',
                icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                color: MicroColors.text,
                onPressed: _path == '/' ? null : () => _navigate(_parentPath),
              ),
              Expanded(
                child: Text(
                  _path,
                  style: const TextStyle(color: MicroColors.subtle, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh_rounded, size: 18),
                color: MicroColors.text,
                onPressed: _loading ? null : _load,
              ),
              IconButton(
                tooltip: _listView ? 'Grid view' : 'List view',
                icon: Icon(_listView ? Icons.grid_view_rounded : Icons.view_list_rounded, size: 18),
                color: MicroColors.text,
                onPressed: () => setState(() => _listView = !_listView),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _search = value),
            style: const TextStyle(color: MicroColors.text, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search this folder',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              suffixIcon: _search.isEmpty ? null : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close_rounded, size: 16),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _search = '');
                },
              ),
              isDense: true,
              filled: true,
              fillColor: MicroColors.sidebar,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            children: [
              for (final location in _locations)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    avatar: Icon(location.icon, size: 15),
                    label: Text(location.label),
                    onPressed: () => _navigate(location.path),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.folder_off_rounded, color: MicroColors.subtle, size: 36),
                            const SizedBox(height: 10),
                            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: MicroColors.red)),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Try again'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _visibleEntries.isEmpty
                      ? Center(
                          child: Text(
                            _entries.isEmpty ? 'This folder is empty' : 'No matching files',
                            style: const TextStyle(color: MicroColors.subtle),
                          ),
                        )
                      : _listView
                          ? ListView.builder(
                              itemCount: _visibleEntries.length,
                              itemBuilder: (_, i) => _listTile(_visibleEntries[i]),
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.all(14),
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 112,
                                childAspectRatio: 0.88,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                              itemCount: _visibleEntries.length,
                              itemBuilder: (_, i) => _gridItem(_visibleEntries[i]),
                            ),
        ),
      ],
    );
  }

  Widget _listTile(_FileEntry entry) {
    final folder = entry.isDirectory;
    return ListTile(
      dense: true,
      leading: Icon(
        folder ? Icons.folder_rounded : entry.isLink ? Icons.link_rounded : Icons.insert_drive_file_rounded,
        color: folder ? MicroColors.accent : MicroColors.subtle,
      ),
      title: Text(entry.name, style: const TextStyle(color: MicroColors.text), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(folder ? 'Folder' : _formatSize(entry.size), style: const TextStyle(color: MicroColors.subtle, fontSize: 11)),
      onTap: folder ? () => _navigate(_path == '/' ? '/${entry.name}' : '$_path/${entry.name}') : () => _showFileDetails(entry),
    );
  }

  Widget _gridItem(_FileEntry entry) {
    final folder = entry.isDirectory;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: folder ? () => _navigate(_path == '/' ? '/${entry.name}' : '$_path/${entry.name}') : () => _showFileDetails(entry),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            folder ? Icons.folder_rounded : entry.isLink ? Icons.link_rounded : Icons.insert_drive_file_rounded,
            size: 44,
            color: folder ? MicroColors.accent : MicroColors.subtle,
          ),
          const SizedBox(height: 6),
          Text(
            entry.name,
            style: const TextStyle(color: MicroColors.text, fontSize: 11),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (!folder)
            Text(_formatSize(entry.size), style: const TextStyle(color: MicroColors.subtle, fontSize: 9)),
        ],
      ),
    );
  }
}

class _FileEntry {
  const _FileEntry({
    required this.name,
    required this.isDirectory,
    required this.isLink,
    required this.size,
  });

  final String name;
  final bool isDirectory;
  final bool isLink;
  final int size;
}
