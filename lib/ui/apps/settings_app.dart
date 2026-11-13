import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app_scope.dart';
import '../../core/terminal_profiles.dart';
import '../../core/theme.dart';
import '../../services/github_auth.dart';
import '../../services/linux_runtime.dart';
import '../../services/settings_store.dart';

enum _Page { desktop, speech, github, huggingface, linux, terminal, browser, login, about }

class SettingsApp extends StatefulWidget {
  const SettingsApp({super.key, required this.runtime});

  final LinuxRuntime runtime;

  @override
  State<SettingsApp> createState() => _SettingsAppState();
}

class _SettingsAppState extends State<SettingsApp> {
  _Page _page = _Page.desktop;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final settings = scope.settings;
    final auth = scope.auth;
    final runtime = widget.runtime;
    final wide = MediaQuery.sizeOf(context).width > 600;

    return Row(
      children: [
        if (wide)
          Container(
            width: 220,
            color: MicroColors.sidebar,
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                for (final p in _Page.values)
                  ListTile(
                    dense: true,
                    selected: _page == p,
                    selectedTileColor: MicroColors.accent.withValues(alpha: 0.2),
                    title: Text(
                      _title(p),
                      style: TextStyle(
                        color: _page == p ? MicroColors.accent : MicroColors.text,
                        fontSize: 14,
                      ),
                    ),
                    onTap: () => setState(() => _page = p),
                  ),
              ],
            ),
          ),
        Expanded(
          child: ListenableBuilder(
            listenable: Listenable.merge([settings, runtime]),
            builder: (context, _) {
              return switch (_page) {
                _Page.desktop => _DesktopPage(settings: settings),
                _Page.speech => _SpeechPage(settings: settings),
                _Page.github => _GitHubPage(auth: auth, runtime: runtime),
                _Page.huggingface => _HuggingFacePage(auth: auth, runtime: runtime),
                _Page.linux => _LinuxPage(runtime: runtime),
                _Page.terminal => _TerminalPage(settings: settings),
                _Page.browser => _BrowserPage(settings: settings),
                _Page.login => _LoginPage(settings: settings),
                _Page.about => const _AboutPage(),
              };
            },
          ),
        ),
      ],
    );
  }

  String _title(_Page p) => switch (p) {
        _Page.desktop => 'Desktop & Dock',
        _Page.speech => 'Speech',
        _Page.github => 'GitHub',
        _Page.huggingface => 'Hugging Face',
        _Page.linux => 'Linux',
        _Page.terminal => 'Terminal',
        _Page.browser => 'Browser',
        _Page.login => 'Users & Login',
        _Page.about => 'About',
      };
}

class _DesktopPage extends StatelessWidget {
  const _DesktopPage({required this.settings});
  final dynamic settings;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Desktop & Dock', style: TextStyle(color: MicroColors.text, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        SwitchListTile(
          title: const Text('Automatically hide and show the Dock', style: TextStyle(color: MicroColors.text)),
          value: settings.dockAutoHide,
          onChanged: (v) => settings.setDockAutoHide(v),
        ),
      ],
    );
  }
}

class _SpeechPage extends StatelessWidget {
  const _SpeechPage({required this.settings});
  final dynamic settings;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Speech', style: TextStyle(color: MicroColors.text, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        SwitchListTile(
          title: const Text('Auto-read OpenCode output', style: TextStyle(color: MicroColors.text)),
          value: settings.autoReadOpenCode,
          onChanged: (v) => settings.setAutoReadOpenCode(v),
        ),
      ],
    );
  }
}

class _GitHubPage extends StatefulWidget {
  const _GitHubPage({required this.auth, required this.runtime});
  final GithubAuth auth;
  final LinuxRuntime runtime;

  @override
  State<_GitHubPage> createState() => _GitHubPageState();
}

class _GitHubPageState extends State<_GitHubPage> {
  final _token = TextEditingController();
  String? _login;
  String? _message;
  bool _busy = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    widget.auth.readLogin().then((value) {
      if (mounted) setState(() => _login = value);
    });
  }

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final token = _token.text.trim();
    if (token.isEmpty) {
      _notify('Paste a GitHub token first.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final identity = await widget.auth.verify(token);
      if (identity == null) {
        _notify('GitHub rejected this token. Check its validity and repository permissions.', error: true);
        return;
      }
      await widget.auth.saveToken(token, identity.login);
      widget.runtime.setGithubToken(token);
      if (widget.runtime.isReady) {
        await widget.runtime.applyGitCredentials(token, identity.login);
      }
      if (!mounted) return;
      setState(() => _login = identity.login);
      _notify('Connected as ${identity.login}.');
      _token.clear();
    } catch (e) {
      _notify('Could not save the GitHub token: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    setState(() => _busy = true);
    try {
      await widget.auth.clear();
      widget.runtime.setGithubToken(null);
      await widget.runtime.clearGitCredentials();
      if (!mounted) return;
      _token.clear();
      setState(() => _login = null);
      _notify('GitHub credentials removed.');
    } catch (e) {
      _notify('Could not clear GitHub credentials: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _notify(String value, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = value;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('GitHub', style: TextStyle(color: MicroColors.text, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(_login == null ? 'Not connected' : 'Connected as $_login',
            style: const TextStyle(color: MicroColors.subtle)),
        const SizedBox(height: 16),
        const Text('Use a Personal Access Token. It is stored in secure platform storage and supplied to Linux tools without writing it into project files.',
            style: TextStyle(color: MicroColors.subtle, fontSize: 12)),
        const SizedBox(height: 16),
        TextField(
          controller: _token,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'GitHub Personal Access Token', hintText: 'ghp_…'),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Verify & Save'),
          ),
          TextButton(onPressed: _busy || _login == null ? null : _clear, child: const Text('Disconnect')),
        ]),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(_message!, style: TextStyle(color: _error ? MicroColors.red : MicroColors.green, fontSize: 12)),
        ],
      ],
    );
  }
}

class _HuggingFacePage extends StatefulWidget {
  const _HuggingFacePage({required this.auth, required this.runtime});
  final GithubAuth auth;
  final LinuxRuntime runtime;

  @override
  State<_HuggingFacePage> createState() => _HuggingFacePageState();
}

class _HuggingFacePageState extends State<_HuggingFacePage> {
  final _token = TextEditingController();
  String? _account;
  String? _message;
  bool _busy = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    widget.auth.readHuggingFaceToken().then((value) {
      if (mounted) setState(() => _account = value == null ? null : 'Token saved');
    });
  }

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final token = _token.text.trim();
    if (token.isEmpty) {
      _notify('Paste a Hugging Face token first.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final account = await widget.auth.verifyHuggingFace(token);
      if (account == null) {
        _notify('Hugging Face rejected this token.', error: true);
        return;
      }
      await widget.auth.saveHuggingFaceToken(token);
      widget.runtime.setHuggingFaceToken(token);
      if (!mounted) return;
      setState(() => _account = account);
      _token.clear();
      _notify('Connected as $account.');
    } catch (e) {
      _notify('Could not save the Hugging Face token: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    setState(() => _busy = true);
    try {
      await widget.auth.clearHuggingFaceToken();
      widget.runtime.setHuggingFaceToken(null);
      if (!mounted) return;
      _token.clear();
      setState(() => _account = null);
      _notify('Hugging Face token removed.');
    } catch (e) {
      _notify('Could not clear the token: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _notify(String value, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = value;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Hugging Face', style: TextStyle(color: MicroColors.text, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(_account == null ? 'Not connected' : 'Connected · $_account',
            style: const TextStyle(color: MicroColors.subtle)),
        const SizedBox(height: 16),
        const Text('The access token is stored securely and passed to Linux processes as HF_TOKEN.',
            style: TextStyle(color: MicroColors.subtle, fontSize: 12)),
        const SizedBox(height: 16),
        TextField(
          controller: _token,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'Hugging Face access token', hintText: 'hf_…'),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Verify & Save'),
          ),
          TextButton(onPressed: _busy || _account == null ? null : _clear, child: const Text('Disconnect')),
        ]),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(_message!, style: TextStyle(color: _error ? MicroColors.red : MicroColors.green, fontSize: 12)),
        ],
      ],
    );
  }
}

class _LinuxPage extends StatelessWidget {
  const _LinuxPage({required this.runtime});
  final LinuxRuntime runtime;

  Future<void> _requestStorage(BuildContext context) async {
    final status = await Permission.manageExternalStorage.request();
    if (!context.mounted) return;
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Storage access was not granted. You can enable it in Android app settings.')),
      );
      if (status.isPermanentlyDenied) await openAppSettings();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Storage access granted.')),
      );
    }
  }

  Future<void> _repair(BuildContext context) async {
    final code = await runtime.repairPackages();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(code == 0 ? 'Linux package repair completed.' : 'Package repair exited with code $code.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Linux', style: TextStyle(color: MicroColors.text, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Text('Status: ${runtime.status.name}', style: const TextStyle(color: MicroColors.subtle)),
        if (runtime.error != null) ...[
          const SizedBox(height: 8),
          Text(runtime.error!, style: const TextStyle(color: MicroColors.red, fontSize: 12)),
        ],
        if (runtime.isBusy) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: runtime.progress == 0 ? null : runtime.progress),
          Text(runtime.stage, style: const TextStyle(color: MicroColors.subtle, fontSize: 13)),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: runtime.isBusy ? null : () => runtime.install(),
          child: Text(runtime.isReady ? 'Reinstall Workstation' : 'Install Workstation'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => _requestStorage(context),
          child: const Text('Grant Android storage access'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: !runtime.isReady || runtime.isBusy ? null : () => _repair(context),
          child: const Text('Repair Linux packages'),
        ),
      ],
    );
  }
}

class _TerminalPage extends StatelessWidget {
  const _TerminalPage({required this.settings});
  final dynamic settings;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Terminal', style: TextStyle(color: MicroColors.text, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        Text('Font size: ${settings.terminalFontSize.round()}', style: const TextStyle(color: MicroColors.text)),
        Slider(
          value: settings.terminalFontSize,
          min: 10,
          max: 18,
          divisions: 8,
          onChanged: (v) => settings.setTerminalFontSize(v),
        ),
        const SizedBox(height: 16),
        const Text('Colour profile', style: TextStyle(color: MicroColors.text)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final p in kTerminalProfiles)
              ChoiceChip(
                label: Text(p.name),
                selected: settings.terminalProfile == p.id,
                onSelected: (_) => settings.setTerminalProfile(p.id),
              ),
          ],
        ),
      ],
    );
  }
}

class _BrowserPage extends StatelessWidget {
  const _BrowserPage({required this.settings});
  final dynamic settings;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Browser', style: TextStyle(color: MicroColors.text, fontSize: 22, fontWeight: FontWeight.w700)),
        SwitchListTile(
          title: const Text('Single-process mode', style: TextStyle(color: MicroColors.text)),
          subtitle: const Text('More stable on low-memory devices', style: TextStyle(color: MicroColors.subtle, fontSize: 12)),
          value: settings.singleProcessBrowser,
          onChanged: (v) => settings.setSingleProcessBrowser(v),
        ),
      ],
    );
  }
}

class _LoginPage extends StatefulWidget {
  const _LoginPage({required this.settings});
  final SettingsStore settings;

  @override
  State<_LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<_LoginPage> {
  late final TextEditingController _name;
  final TextEditingController _password = TextEditingController();
  bool _saving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.settings.userName);
  }

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    await widget.settings.setUserName(_name.text);
    if (mounted) setState(() => _message = 'Display name saved.');
  }

  Future<void> _savePassword() async {
    setState(() => _saving = true);
    try {
      await widget.settings.setLoginPassword(_password.text.isEmpty ? null : _password.text);
      _password.clear();
      if (mounted) setState(() => _message = 'Lock screen password updated.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removePassword() async {
    await widget.settings.setLoginPassword(null);
    if (mounted) setState(() => _message = 'Lock screen password removed.');
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Users & Login', style: TextStyle(color: MicroColors.text, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'Display name'),
          onSubmitted: (_) => _saveName(),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(onPressed: _saveName, child: const Text('Save display name')),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _password,
          obscureText: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Lock screen password (optional)',
            helperText: 'Local shell lock only — does not encrypt data',
          ),
          onSubmitted: (_) => _savePassword(),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          FilledButton(onPressed: _saving ? null : _savePassword, child: const Text('Save password')),
          TextButton(onPressed: _saving ? null : _removePassword, child: const Text('Remove password')),
        ]),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(_message!, style: const TextStyle(color: MicroColors.green, fontSize: 12)),
        ],
      ],
    );
  }
}

class _AboutPage extends StatelessWidget {
  const _AboutPage();

  @override
  Widget build(BuildContext context) {
    return const ListView(
      padding: EdgeInsets.all(24),
      children: [
        Text('About MicroOS', style: TextStyle(color: MicroColors.text, fontSize: 22, fontWeight: FontWeight.w700)),
        SizedBox(height: 12),
        Text('Golden Gate UI · macOS 27 style window manager for a mobile Linux workstation.', style: TextStyle(color: MicroColors.subtle)),
      ],
    );
  }
}
