import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app_scope.dart';
import '../../core/terminal_profiles.dart';
import '../../core/theme.dart';
import '../../services/linux_runtime.dart';

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
                _Page.linux => _LinuxPage(runtime: runtime, settings: settings),
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

class _GitHubPage extends StatelessWidget {
  const _GitHubPage({required this.auth, required this.runtime});
  final dynamic auth;
  final LinuxRuntime runtime;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('GitHub', style: TextStyle(color: MicroColors.text, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        const Text('Personal Access Token is stored securely and used for git + OpenCode.', style: TextStyle(color: MicroColors.subtle)),
      ],
    );
  }
}

class _HuggingFacePage extends StatelessWidget {
  const _HuggingFacePage({required this.auth, required this.runtime});
  final dynamic auth;
  final LinuxRuntime runtime;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Hugging Face', style: TextStyle(color: MicroColors.text, fontSize: 22, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _LinuxPage extends StatelessWidget {
  const _LinuxPage({required this.runtime, required this.settings});
  final LinuxRuntime runtime;
  final dynamic settings;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Linux', style: TextStyle(color: MicroColors.text, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Text('Status: ${runtime.status.name}', style: const TextStyle(color: MicroColors.subtle)),
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

class _LoginPage extends StatelessWidget {
  const _LoginPage({required this.settings});
  final dynamic settings;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Users & Login', style: TextStyle(color: MicroColors.text, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(labelText: 'Display name'),
          controller: TextEditingController(text: settings.userName),
          onSubmitted: (v) => settings.setUserName(v),
        ),
        const SizedBox(height: 16),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Lock screen password (optional)',
            helperText: 'Local shell lock only — does not encrypt data',
          ),
          obscureText: true,
          onSubmitted: (v) => settings.setLoginPassword(v.isEmpty ? null : v),
        ),
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
