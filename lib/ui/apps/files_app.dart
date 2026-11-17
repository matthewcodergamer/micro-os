import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';

import '../../core/theme.dart';
import '../../services/linux_runtime.dart';
import '../mac_icons.dart';

/// Finder-style browser for the real Linux guest filesystem and Android bind mounts.
class FilesApp extends StatefulWidget {
  const FilesApp({super.key, required this.runtime, this.onOpenTerminal});

  final LinuxRuntime runtime;
  final ValueChanged<List<String>>? onOpenTerminal;

  @override
  State<FilesApp> createState() => _FilesAppState();
}

enum _FinderSort { name, size, kind }

class _FilesAppState extends State<FilesApp> {
  String _path = '/root';
  List<_FileEntry> _entries = const [];
  bool _loading = true;
  bool _listView = false;
  bool _showHiddenFiles = false;
  _FinderSort _sort = _FinderSort.name;
  bool _ascending = true;
  final TextEditingController _searchController = TextEditingController();
  String _search = '';
  String? _error;
  int _request = 0;
  final List<String> _history = <String>['/root'];
  int _historyIndex = 0;
  final Set<String> _selectedPaths = <String>{};
  String? _columnSelection;


  static const _locations = <({String label, String path, String kind})>[
    (label: 'Home', path: '/root', kind: 'home'),
    (label: 'Downloads', path: '/root/Downloads', kind: 'downloads'),
    (label: 'Phone', path: '/mnt/android', kind: 'phone'),
    (label: 'Linux root', path: '/', kind: 'drive'),
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

  void _navigate(String path, {bool history = true}) {
    if (path == _path) return;
    setState(() {
      _path = path; _selectedPaths.clear(); _columnSelection = null;
      if (history) { _history.removeRange(_historyIndex + 1, _history.length); _history.add(path); _historyIndex = _history.length - 1; }
    });
    _load();
  }
  void _goBack() { if (_historyIndex == 0) return; setState(() { _historyIndex--; _path = _history[_historyIndex]; }); _load(); }
  void _goForward() { if (_historyIndex >= _history.length - 1) return; setState(() { _historyIndex++; _path = _history[_historyIndex]; }); _load(); }
  void _toggleSelection(_FileEntry entry) { final p = _entryPath(entry); setState(() { if (!_selectedPaths.add(p)) _selectedPaths.remove(p); }); }

  List<_FileEntry> get _visibleEntries {
    final query = _search.trim().toLowerCase();
    final entries = _entries.where((entry) {
      if (!_showHiddenFiles && entry.name.startsWith('.')) return false;
      return query.isEmpty || entry.name.toLowerCase().contains(query);
    }).toList();
    entries.sort((a, b) {
      final directoryOrder = a.isDirectory == b.isDirectory ? 0 : (a.isDirectory ? -1 : 1);
      if (directoryOrder != 0) return directoryOrder;
      final order = switch (_sort) {
        _FinderSort.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        _FinderSort.size => a.size.compareTo(b.size),
        _FinderSort.kind => _fileKind(a).compareTo(_fileKind(b)),
      };
      return _ascending ? order : -order;
    });
    return entries;
  }

  String _fileKind(_FileEntry entry) {
    if (entry.isDirectory) return 'Folder';
    if (entry.isLink) return 'Link';
    final dot = entry.name.lastIndexOf('.');
    return dot > 0 ? entry.name.substring(dot + 1).toLowerCase() : 'File';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _entryPath(_FileEntry entry) =>
      _path == '/' ? '/${entry.name}' : '$_path/${entry.name}';

  Future<void> _runGuest(String script, List<String> args) async {
    final pty = widget.runtime.startShell(
      argv: <String>['/bin/bash', '-lc', script, 'microos-finder', ...args],
    );
    final output = BytesBuilder(copy: false);
    final subscription = pty.output.listen(output.add);
    try {
      final code = await pty.exitCode.timeout(const Duration(seconds: 15));
      final message = utf8.decode(output.takeBytes(), allowMalformed: true).trim();
      if (code != 0) throw StateError(message.isEmpty ? 'Linux file operation failed.' : message);
    } finally {
      await subscription.cancel();
      pty.kill();
    }
  }

  Future<String?> _askName(String title, String initial) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: MicroColors.panelSolid,
        title: Text(title, style: const TextStyle(color: MicroColors.text)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: MicroColors.text),
          decoration: const InputDecoration(hintText: 'Name'),
          onSubmitted: (text) => Navigator.pop(context, text),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  bool _validName(String value) =>
      value.trim().isNotEmpty && !value.contains('/') && value != '.' && value != '..';

  void _notifyActionError(Object error) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _createFolder() async {
    final name = await _askName('New Folder', '');
    if (name == null) return;
    if (!_validName(name)) {
      _notifyActionError('Enter a valid folder name.');
      return;
    }
    final path = _path == '/' ? '/${name.trim()}' : '$_path/${name.trim()}';
    try {
      await _runGuest(r'mkdir -- "$1"', <String>[path]);
      await _load();
    } catch (error) {
      _notifyActionError(error);
    }
  }

  Future<void> _showEntryActions(_FileEntry entry) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MicroColors.panelSolid,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(entry.isDirectory ? Icons.folder_open_rounded : Icons.info_outline_rounded),
              title: Text(entry.isDirectory ? 'Open' : 'Get Info'),
              onTap: () => Navigator.pop(context, 'open'),
            ),
            if (entry.isDirectory && widget.onOpenTerminal != null)
              ListTile(
                leading: const Icon(Icons.terminal_rounded),
                title: const Text('Open in Terminal'),
                onTap: () => Navigator.pop(context, 'terminal'),
              ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy Path'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.control_point_duplicate_rounded),
              title: const Text('Duplicate'),
              onTap: () => Navigator.pop(context, 'duplicate'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: MicroColors.red),
              title: const Text('Move to Trash'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    final path = _entryPath(entry);
    if (action == 'open') {
      if (entry.isDirectory) {
        _navigate(path);
      } else {
        _showFileDetails(entry);
      }
    } else if (action == 'terminal') {
      widget.onOpenTerminal?.call(<String>[
        '/bin/bash',
        '-lc',
        r'cd -- "$1"; exec bash',
        'microos-terminal',
        path,
      ]);
    } else if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: path));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Path copied')));
    } else if (action == 'duplicate') {
      final dot = entry.name.lastIndexOf('.');
      final copyName = entry.isDirectory || dot <= 0
          ? '${entry.name} copy'
          : '${entry.name.substring(0, dot)} copy${entry.name.substring(dot)}';
      final destination = _path == '/' ? '/$copyName' : '$_path/$copyName';
      try {
        await _runGuest(r'if [ -e "$2" ] || [ -L "$2" ]; then echo "A copy already exists." >&2; exit 1; fi; cp -a -- "$1" "$2"', <String>[path, destination]);
        await _load();
      } catch (error) { _notifyActionError(error); }
    } else if (action == 'rename') {
      final name = await _askName('Rename', entry.name);
      if (name == null) return;
      if (!_validName(name)) {
        _notifyActionError('Enter a valid name.');
        return;
      }
      final destination = _path == '/' ? '/${name.trim()}' : '$_path/${name.trim()}';
      try {
        await _runGuest(r'if [ -e "$2" ] || [ -L "$2" ]; then echo "A file with that name already exists." >&2; exit 1; fi; mv -- "$1" "$2"', <String>[path, destination]);
        await _load();
      } catch (error) {
        _notifyActionError(error);
      }
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: MicroColors.panelSolid,
          title: const Text('Delete this item?', style: TextStyle(color: MicroColors.text)),
          content: Text('“${entry.name}” will be moved to the Linux Trash. You can restore it from the Trash folder.', style: const TextStyle(color: MicroColors.subtle)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Move to Trash', style: TextStyle(color: MicroColors.red)),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        try {
          await _runGuest(r'mkdir -p /root/.local/share/Trash/files; target="/root/.local/share/Trash/files/$(basename -- "$1")"; if [ -e "$target" ] || [ -L "$target" ]; then target="$target.$(date +%s%N)"; fi; mv -- "$1" "$target"', <String>[path]);
          await _load();
        } catch (error) {
          _notifyActionError(error);
        }
      }
    }
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
    return Row(children: [
      SizedBox(width: 132, child: Container(color: MicroColors.sidebar, child: ListView(padding: const EdgeInsets.all(8), children: [
        const Padding(padding: EdgeInsets.all(8), child: Text('FAVORITES', style: TextStyle(color: MicroColors.subtle, fontSize: 10, fontWeight: FontWeight.w700))),
        _sidebarItem('Home', '/root', 'home'),
        _sidebarItem('Downloads', '/root/Downloads', 'downloads'),
        _sidebarItem('Documents', '/root/Documents', 'documents'),
        _sidebarItem('Desktop', '/root/Desktop', 'desktop'),
        const Padding(padding: EdgeInsets.all(8), child: Text('LOCATIONS', style: TextStyle(color: MicroColors.subtle, fontSize: 10, fontWeight: FontWeight.w700))),
        _sidebarItem('Phone', '/mnt/android', 'phone'),
        _sidebarItem('Linux', '/', 'drive'),
      ]))),
      Container(width: 1, color: MicroColors.hairline),
      Expanded(child: Column(
      children: [
        Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: MicroColors.sidebar,
          child: Row(
            children: [
              IconButton(tooltip: 'Back', icon: const Icon(Icons.chevron_left_rounded), color: MicroColors.text, onPressed: _historyIndex > 0 ? _goBack : null),
              IconButton(tooltip: 'Forward', icon: const Icon(Icons.chevron_right_rounded), color: MicroColors.text, onPressed: _historyIndex < _history.length - 1 ? _goForward : null),
              IconButton(
                tooltip: 'Parent folder',
                icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                color: MicroColors.text,
                onPressed: _path == '/' ? null : () => _navigate(_parentPath),
              ),
              Expanded(child: _breadcrumbs()),
              IconButton(
                tooltip: 'New folder',
                icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                color: MicroColors.text,
                onPressed: _loading ? null : _createFolder,
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh_rounded, size: 18),
                color: MicroColors.text,
                onPressed: _loading ? null : _load,
              ),
              PopupMenuButton<String>(
                tooltip: 'View options', icon: const Icon(Icons.view_column_rounded, size: 18, color: MicroColors.text),
                onSelected: (v) => setState(() {
                  if (v == 'hidden') {
                    _showHiddenFiles = !_showHiddenFiles;
                  } else if (v == 'sort-name' || v == 'sort-size' || v == 'sort-kind') {
                    _sort = v == 'sort-size' ? _FinderSort.size : v == 'sort-kind' ? _FinderSort.kind : _FinderSort.name;
                  } else if (v == 'sort-direction') {
                    _ascending = !_ascending;
                  } else {
                    _listView = v == 'list';
                    _columnSelection = v == 'columns' ? '' : null;
                  }
                }),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'icons', child: Text('Icon View')),
                  const PopupMenuItem(value: 'list', child: Text('List View')),
                  const PopupMenuItem(value: 'columns', child: Text('Column View')),
                  PopupMenuItem(value: 'hidden', child: Text(_showHiddenFiles ? 'Hide Hidden Files' : 'Show Hidden Files')),
                  const PopupMenuDivider(),
                  const PopupMenuItem(value: 'sort-name', child: Text('Sort by Name')),
                  const PopupMenuItem(value: 'sort-size', child: Text('Sort by Size')),
                  const PopupMenuItem(value: 'sort-kind', child: Text('Sort by Kind')),
                  PopupMenuItem(value: 'sort-direction', child: Text(_ascending ? 'Sort Descending' : 'Sort Ascending')),
                ],
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
        : _columnSelection != null
                          ? _columnView()
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
      )),
    ]);
  }

  Widget _breadcrumbs() {
    final segments = _path.split('/').where((part) => part.isNotEmpty).toList();
    final crumbs = <({String label, String path})>[(label: 'Macintosh HD', path: '/')];
    var current = '';
    for (final segment in segments) {
      current += '/$segment';
      crumbs.add((label: segment, path: current));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < crumbs.length; i++) ...[
          if (i > 0) const Icon(Icons.chevron_right_rounded, size: 15, color: MicroColors.subtle),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(0, 30), padding: const EdgeInsets.symmetric(horizontal: 5), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            onPressed: () => _navigate(crumbs[i].path),
            child: Text(crumbs[i].label, style: TextStyle(color: i == crumbs.length - 1 ? MicroColors.text : MicroColors.subtle, fontSize: 12), overflow: TextOverflow.ellipsis),
          ),
        ],
      ]),
    );
  }

  Widget _sidebarItem(String label, String path, String kind) {
    final selected = _path == path || (path != '/' && _path.startsWith(path + '/'));
    return ListTile(dense: true, selected: selected, contentPadding: const EdgeInsets.symmetric(horizontal: 7), leading: FinderItemIcon(kind: kind, size: 18), title: Text(label, style: const TextStyle(fontSize: 11, color: MicroColors.text)), onTap: () => _navigate(path));
  }

  Widget _columnView() {
    final selected = _visibleEntries.where((e) => _entryPath(e) == _columnSelection).firstOrNull;
    return Row(children: [
      SizedBox(width: 185, child: ListView(children: _visibleEntries.map((e) => ListTile(
        dense: true, selected: _entryPath(e) == _columnSelection,
        leading: FinderItemIcon(kind: e.isDirectory ? 'folder' : e.isLink ? 'link' : 'file', size: 23),
        title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: MicroColors.text, fontSize: 12)),
        trailing: e.isDirectory ? const Icon(Icons.chevron_right_rounded, size: 16) : null,
        onTap: () => setState(() => _columnSelection = _entryPath(e)),
        onLongPress: () => _showEntryActions(e),
      )).toList())),
      Container(width: 1, color: MicroColors.hairline),
      Expanded(child: selected == null ? const Center(child: Text('Select an item', style: TextStyle(color: MicroColors.subtle))) :
        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          FinderItemIcon(kind: selected.isDirectory ? 'folder' : selected.isLink ? 'link' : 'file', size: 52),
          const SizedBox(height: 8), Padding(padding: const EdgeInsets.all(12), child: Text(selected.name, textAlign: TextAlign.center, style: const TextStyle(color: MicroColors.text))),
          Text(selected.isDirectory ? 'Folder' : _formatSize(selected.size), style: const TextStyle(color: MicroColors.subtle, fontSize: 11)),
          if (selected.isDirectory) TextButton.icon(onPressed: () => _navigate(_entryPath(selected)), icon: const Icon(Icons.folder_open_rounded), label: const Text('Open Folder')),
        ])),
    ]);
  }

  Widget _listTile(_FileEntry entry) {
    final folder = entry.isDirectory;
    final selected = _selectedPaths.contains(_entryPath(entry));
    return GestureDetector(
      onSecondaryTap: () { _toggleSelection(entry); _showEntryActions(entry); },
      child: ListTile(
      dense: true,
      selected: selected,
      leading: FinderItemIcon(
        kind: folder ? 'folder' : entry.isLink ? 'link' : 'file',
        size: 28,
      ),
      title: Text(entry.name, style: const TextStyle(color: MicroColors.text), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(folder ? 'Folder' : _formatSize(entry.size), style: const TextStyle(color: MicroColors.subtle, fontSize: 11)),
      onTap: folder ? () => _navigate(_entryPath(entry)) : () { _toggleSelection(entry); _showFileDetails(entry); },
      onLongPress: () { _toggleSelection(entry); _showEntryActions(entry); },
    ));
  }

  Widget _gridItem(_FileEntry entry) {
    final folder = entry.isDirectory;
    final selected = _selectedPaths.contains(_entryPath(entry));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTap: () { _toggleSelection(entry); _showEntryActions(entry); },
      onTap: folder ? () => _navigate(_entryPath(entry)) : () { _toggleSelection(entry); _showFileDetails(entry); },
      onLongPress: () { _toggleSelection(entry); _showEntryActions(entry); },
      child: Container(
        decoration: BoxDecoration(
          color: selected ? MicroColors.accent.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: selected ? Border.all(color: MicroColors.accent.withValues(alpha: 0.55)) : null,
        ),
        padding: const EdgeInsets.all(4),
        child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FinderItemIcon(
            kind: folder ? 'folder' : entry.isLink ? 'link' : 'file',
            size: 44,
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
