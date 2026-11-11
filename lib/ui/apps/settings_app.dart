import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app_scope.dart';
import '../../core/theme.dart';
import '../../services/linux_runtime.dart';

class SettingsApp extends StatefulWidget {
  const SettingsApp({super.key, required this.runtime});

  final LinuxRuntime runtime;

  @override
  State<SettingsApp> createState() => _SettingsAppState();
}

class _SettingsAppState extends State<SettingsApp> {
  final TextEditingController _token = TextEditingController();

  bool _busy = false;
  bool _repairing = false;
  String? _message;
  bool _messageIsError = false;
  String? _login;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  Future<void> _restore() async {
    final scope = AppScope.of(context);
    final token = await scope.auth.readToken();
    final login = await scope.auth.readLogin();
    if (!mounted) return;
    setState(() {
      _login = login;
      if (token != null) _token.text = token;
    });
  }

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  void _notify(String message, {bool isError = false}) {
    setState(() {
      _message = message;
      _messageIsError = isError;
    });
  }

  Future<void> _saveToken() async {
    final scope = AppScope.of(context);
    final token = _token.text.trim();

    if (token.isEmpty) {
      _notify('Paste a GitHub Personal Access Token first.', isError: true);
      return;
    }

    setState(() => _busy = true);
    try {
      final identity = await scope.auth.verify(token);
      if (identity == null) {
        _notify(
          'GitHub rejected that token. It needs the “repo” scope (classic) or '
          'Contents: read/write (fine-grained).',
          isError: true,
        );
        return;
      }

      await scope.auth.saveToken(token, identity.login);
      if (widget.runtime.isReady) {
        await widget.runtime.applyGitCredentials(token, identity.login);
      }
      if (!mounted) return;
      setState(() => _login = identity.login);
      _notify(
        widget.runtime.isReady
            ? 'Connected as ${identity.login}. git push will not prompt.'
            : 'Token saved for ${identity.login}. It is written into the guest '
                'as soon as Linux finishes installing.',
      );
    } catch (e) {
      _notify('Could not store the token: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearToken() async {
    final scope = AppScope.of(context);
    await scope.auth.clear();
    await widget.runtime.clearGitCredentials();
    if (!mounted) return;
    _token.clear();
    setState(() => _login = null);
    _notify('GitHub credentials removed.');
  }

  Future<void> _requestStorage() async {
    final status = await Permission.manageExternalStorage.request();
    if (!mounted) return;
    _notify(
      status.isGranted
          ? 'All-files access granted. /storage/emulated/0 is mounted at /mnt/android.'
          : 'Permission denied. Enable “All files access” in Android app settings.',
      isError: !status.isGranted,
    );
  }

  Future<void> _install() async {
    final scope = AppScope.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: MicroColors.panelSolid,
        title: const Text('Install Linux toolchain?'),
        content: const Text(
          'This downloads roughly 700 MB – 1.2 GB of packages inside the guest. '
          'Use Wi-Fi and keep the app in the foreground.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Install'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await widget.runtime.install();
    if (!mounted) return;
    if (widget.runtime.isReady) {
      await scope.settings.markInstalled();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);

    return Container(
      color: MicroColors.panelSolid,
      child: AnimatedBuilder(
        animation: Listenable.merge([widget.runtime, scope.settings]),
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _Section(
                title: 'GitHub',
                subtitle: _login == null
                    ? 'Not connected'
                    : 'Connected as $_login',
                children: [
                  const Text(
                    'Paste a Personal Access Token. It is kept in the Android '
                    'keystore and written into the guest as a git credential.',
                    style: TextStyle(color: MicroColors.subtle, fontSize: 11),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _token,
                    obscureText: true,
                    style: const TextStyle(fontSize: 12, color: MicroColors.text),
                    decoration: const InputDecoration(
                      hintText: 'ghp_…',
                      labelText: 'Personal Access Token',
                      labelStyle: TextStyle(fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      FilledButton(
                        onPressed: _busy ? null : _saveToken,
                        child: _busy
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Save & apply'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _busy ? null : _clearToken,
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _message!,
                      style: TextStyle(
                        fontSize: 11,
                        color: _messageIsError
                            ? MicroColors.red
                            : MicroColors.green,
                      ),
                    ),
                  ],
                ],
              ),
                  ],
                ],
              ),
              _Section(
                title: 'How to get a GitHub Token',
                subtitle: 'Connect MicroOS to your GitHub account',
                children: [
                  const Text(
                    '1. Open github.com and sign in.\n'
                    '2. Go to Settings → Developer settings → Personal access tokens.\n'
                    '3. Choose Fine-grained tokens → Generate new token.\n'
                    '4. Give it a name (for example, MicroOS) and an expiration date.\n'
                    '5. Select the repositories MicroOS should access.\n'
                    '6. Under Repository permissions, set Contents to Read and write.\n'
                    '7. Generate the token, copy it immediately, then paste it in the GitHub section above and tap Save & apply.',
                    style: TextStyle(color: MicroColors.text, fontSize: 11, height: 1.55),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Keep this token private. Anyone who has it may be able to access the repositories you selected. If it is exposed, revoke it in GitHub settings and create a new one.',
                    style: TextStyle(color: MicroColors.amber, fontSize: 10, height: 1.45),
                  ),
                ],
              ),
              _Section(
                title: 'Linux runtime',
                subtitle: widget.runtime.stage,
                children: [
                  Row(
                    children: [
                      _Pill(
                        label: widget.runtime.status.name.toUpperCase(),
                        color: switch (widget.runtime.status) {
                          RuntimeStatus.ready => MicroColors.green,
                          RuntimeStatus.installing => MicroColors.amber,
                          RuntimeStatus.failed => MicroColors.red,
                          _ => MicroColors.subtle,
                        },
                      ),
                      const Spacer(),
                      Text(
                        '${(widget.runtime.progress * 100).round()}%',
                        style: const TextStyle(
                          color: MicroColors.subtle,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: widget.runtime.progress == 0
                          ? null
                          : widget.runtime.progress,
                      minHeight: 5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (widget.runtime.error != null)
                    Text(
                      widget.runtime.error!,
                      style: const TextStyle(
                        color: MicroColors.red,
                        fontSize: 11,
                      ),
                    ),
                  Row(
                    children: [
                      FilledButton.tonal(
                        onPressed: widget.runtime.isBusy ? null : _install,
                        child: Text(
                          widget.runtime.isReady ? 'Repair toolchain' : 'Install toolchain',
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _requestStorage,
                        child: const Text('Storage access'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: (!widget.runtime.isReady || widget.runtime.isBusy || _repairing)
                          ? null
                          : () async {
                              setState(() => _repairing = true);
                              final code = await widget.runtime.repairPackages();
                              if (!mounted) return;
                              setState(() => _repairing = false);
                              _notify(
                                code == 0
                                    ? 'Package repair completed.'
                                    : 'Package repair exited with code $code. Check the log for details.',
                                isError: code != 0,
                              );
                            },
                      icon: _repairing
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.build_outlined, size: 16),
                      label: Text(_repairing ? 'Repairing packages…' : 'Repair Linux packages'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _LogView(runtime: widget.runtime),
                ],
              ),
              _Section(
                title: 'OpenCode appearance',
                subtitle: 'Independent from the dark MicroOS desktop',
                children: [
                  DropdownButtonFormField<String>(
                    value: scope.settings.openCodeTheme,
                    decoration: const InputDecoration(labelText: 'OpenCode theme'),
                    items: const [
                      DropdownMenuItem(value: 'light', child: Text('Light / White')),
                      DropdownMenuItem(value: 'dark', child: Text('Dark')),
                      DropdownMenuItem(value: 'system', child: Text('Follow system')),
                    ],
                    onChanged: (value) {
                      if (value != null) scope.settings.setOpenCodeTheme(value);
                    },
                  ),
                  const SizedBox(height: 6),
                  const Text('The selected theme is written to OpenCode config when AI Hub launches.',
                    style: TextStyle(color: MicroColors.subtle, fontSize: 10)),
                ],
              ),
              _Section(
                title: 'Browser',
                subtitle: 'Memory profile for low-RAM phones',
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: scope.settings.singleProcessBrowser,
                    onChanged: (value) =>
                        scope.settings.setSingleProcessBrowser(value),
                    title: const Text(
                      'Compatibility mode (--single-process)',
                      style: TextStyle(fontSize: 12, color: MicroColors.text),
                    ),
                    subtitle: const Text(
                      'Lower memory, but Chromium may crash on heavy pages. '
                      'Off by default because upstream deprecated the flag.',
                      style: TextStyle(fontSize: 10, color: MicroColors.subtle),
                    ),
                  ),
                  const Text(
                    'Always applied: --no-sandbox --disable-gpu-sandbox '
                    '--disable-dev-shm-usage --process-per-site '
                    '--renderer-process-limit=1 --disable-background-networking '
                    '--js-flags=--max-old-space-size=512',
                    style: TextStyle(
                      fontSize: 10,
                      color: MicroColors.subtle,
                      fontFamily: 'monospace',
                      height: 1.5,
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.only(top: 6, bottom: 20),
                child: Text(
                  'MicroOS 0.1.0 · Android arm64 · Ubuntu 24.04 guest via proot',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0x66FFFFFF), fontSize: 10),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x0DFFFFFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: MicroColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 8),
              child: Text(
                subtitle!,
                style: const TextStyle(color: MicroColors.subtle, fontSize: 10),
              ),
            )
          else
            const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _LogView extends StatelessWidget {
  const _LogView({required this.runtime});

  final LinuxRuntime runtime;

  @override
  Widget build(BuildContext context) {
    final lines = runtime.logLines;
    final tail = lines.sublist(math.max(0, lines.length - 12));

    return Container(
      height: 132,
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: SingleChildScrollView(
        reverse: true,
        child: Text(
          tail.isEmpty ? 'No output yet.' : tail.join('\n'),
          style: const TextStyle(
            color: Color(0xFF9FB0C7),
            fontSize: 9,
            fontFamily: 'monospace',
            height: 1.45,
          ),
        ),
      ),
    );
  }
}
