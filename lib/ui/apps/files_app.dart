import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../services/linux_runtime.dart';

/// Finder-style file browser for the guest filesystem / Android storage.
class FilesApp extends StatefulWidget {
  const FilesApp({super.key, required this.runtime});

  final LinuxRuntime runtime;

  @override
  State<FilesApp> createState() => _FilesAppState();
}

class _FilesAppState extends State<FilesApp> {
  String _path = '/';
  List<String> _entries = [];
  bool _loading = true;
  String? _error;
  bool _listView = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Placeholder listing – real implementation uses runtime shell.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      setState(() {
        _entries = [
          'Home',
          'Downloads',
          'Documents',
          'Pictures',
          'Music',
          'Videos',
        ];
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Toolbar
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: MicroColors.sidebar,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
                color: MicroColors.text,
                onPressed: _path == '/' ? null : () {
                  setState(() => _path = '/');
                  _load();
                },
              ),
              Expanded(
                child: Text(
                  _path,
                  style: const TextStyle(color: MicroColors.subtle, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: Icon(
                  _listView ? Icons.grid_view_rounded : Icons.view_list_rounded,
                  size: 18,
                ),
                color: MicroColors.text,
                onPressed: () => setState(() => _listView = !_listView),
              ),
            ],
          ),
        ),
        // Body
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!, style: const TextStyle(color: MicroColors.red)))
                  : _listView
                      ? ListView.builder(
                          itemCount: _entries.length,
                          itemBuilder: (_, i) => ListTile(
                            leading: const Icon(Icons.folder_rounded, color: MicroColors.accent),
                            title: Text(_entries[i], style: const TextStyle(color: MicroColors.text)),
                            onTap: () {},
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 100,
                            childAspectRatio: 0.85,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: _entries.length,
                          itemBuilder: (_, i) => Column(
                            children: [
                              const Icon(Icons.folder_rounded, size: 48, color: MicroColors.accent),
                              const SizedBox(height: 6),
                              Text(
                                _entries[i],
                                style: const TextStyle(color: MicroColors.text, fontSize: 12),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
        ),
      ],
    );
  }
}
