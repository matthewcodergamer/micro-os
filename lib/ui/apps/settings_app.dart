import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app_scope.dart';
import '../../core/desktop_input.dart';
import '../../core/macos_design.dart';
import '../../core/opencode_themes.dart';
import '../../core/shell_mode.dart';
import '../../core/terminal_profiles.dart';
import '../../services/github_auth.dart';
import '../../services/linux_runtime.dart';
import '../../services/performance_monitor.dart';
import '../../services/settings_store.dart';

enum _Page {
  desktop,
  performance,
  linux,
  terminal,
  browser,
  github,
  huggingface,
  login,
  about,
}

String _pageTitle(_Page page) => switch (page) {
  _Page.desktop => 'Desktop & Dock',
  _Page.performance => 'Performance',
  _Page.linux => 'Linux Workstation',
  _Page.terminal => 'Terminal',
  _Page.browser => 'Browser',
  _Page.github => 'GitHub',
  _Page.huggingface => 'Hugging Face',
  _Page.login => 'Users & Login',
  _Page.about => 'About',
};

String _pageSubtitle(_Page page) => switch (page) {
  _Page.desktop =>
    'Choose your window style, the Dock, and Linux desktop input.',
  _Page.performance => 'Live, on-device telemetry for this phone or tablet.',
  _Page.linux => 'Manage the PRoot Ubuntu runtime and storage access.',
  _Page.terminal => 'Type, colour, and cursor preferences for every shell.',
  _Page.browser => 'Rendering and memory options for the Linux browser.',
  _Page.github => 'Connect an account for Git, GitHub CLI, and OpenCode.',
  _Page.huggingface => 'Share a token with Linux AI tools and model downloads.',
  _Page.login => 'Your display name and the Misty lock screen password.',
  _Page.about => 'A calm, cloud-native Linux workstation for mobile.',
};

IconData _pageIcon(_Page page) => switch (page) {
  _Page.desktop => Icons.space_dashboard_rounded,
  _Page.performance => Icons.speed_rounded,
  _Page.linux => Icons.terminal_rounded,
  _Page.terminal => Icons.code_rounded,
  _Page.browser => Icons.public_rounded,
  _Page.github => Icons.alternate_email_rounded,
  _Page.huggingface => Icons.auto_awesome_rounded,
  _Page.login => Icons.person_rounded,
  _Page.about => Icons.info_rounded,
};

Color _pageAccent(_Page page) => switch (page) {
  _Page.desktop => Sequoia.blue,
  _Page.performance => Sequoia.teal,
  _Page.linux => Sequoia.green,
  _Page.terminal => Sequoia.purple,
  _Page.browser => Sequoia.blue,
  _Page.github => Sequoia.indigo,
  _Page.huggingface => Sequoia.orange,
  _Page.login => Sequoia.pink,
  _Page.about => Sequoia.accent,
};

class _NavGroup {
  const _NavGroup(this.label, this.pages);

  final String label;
  final List<_Page> pages;
}

const _navGroups = <_NavGroup>[
  _NavGroup('General', [_Page.desktop, _Page.performance]),
  _NavGroup('Linux', [_Page.linux, _Page.terminal, _Page.browser]),
  _NavGroup('Accounts', [_Page.github, _Page.huggingface, _Page.login]),
  _NavGroup('Misty OS', [_Page.about]),
];

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
    final wide = MediaQuery.sizeOf(context).width >= 680;

    final content = ListenableBuilder(
      key: ValueKey(_page),
      listenable: Listenable.merge([settings, runtime]),
      builder: (context, _) {
        return switch (_page) {
          _Page.desktop => _DesktopPage(settings: settings),
          _Page.performance => const _PerformancePage(),
          _Page.linux => _LinuxPage(runtime: runtime),
          _Page.terminal => _TerminalPage(settings: settings),
          _Page.browser => _BrowserPage(settings: settings),
          _Page.github => _GitHubPage(auth: auth, runtime: runtime),
          _Page.huggingface => _HuggingFacePage(auth: auth, runtime: runtime),
          _Page.login => _LoginPage(settings: settings),
          _Page.about => const _AboutPage(),
        };
      },
    );

    // A short cross-fade makes switching panes feel like System Settings
    // instead of a hard list rebuild.
    final animatedContent = AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.015),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: content,
    );

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF25252A), Color(0xFF1A1A1E)],
        ),
      ),
      child: wide
          ? Row(
              children: [
                _SettingsSidebar(
                  page: _page,
                  onSelect: (page) => setState(() => _page = page),
                ),
                Expanded(child: animatedContent),
              ],
            )
          : Column(
              children: [
                _CompactTabs(
                  page: _page,
                  onSelect: (page) => setState(() => _page = page),
                ),
                Expanded(child: animatedContent),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pages
// ---------------------------------------------------------------------------

class _DesktopPage extends StatelessWidget {
  const _DesktopPage({required this.settings});

  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      icon: _pageIcon(_Page.desktop),
      accent: _pageAccent(_Page.desktop),
      title: _pageTitle(_Page.desktop),
      subtitle: _pageSubtitle(_Page.desktop),
      children: [
        _Section(
          title: 'Window style',
          caption:
              'Two kinds of people use Misty OS: the ones who want the full '
              'desktop on their phone, and the ones who want that desktop to '
              'feel mobile. Pick your side — or let Misty choose for you.',
          children: [
            _ChoiceGroup<ShellMode>(
              value: settings.shellMode,
              options: const [
                _Choice(
                  value: ShellMode.automatic,
                  title: 'Automatic',
                  description:
                      'Full-screen, touch-friendly apps on phones. Floating '
                      'macOS windows on tablets and larger screens.',
                  icon: Icons.auto_awesome_rounded,
                ),
                _Choice(
                  value: ShellMode.desktop,
                  title: 'Desktop',
                  description:
                      'The complete macOS experience everywhere: movable, '
                      'resizable windows on every device.',
                  icon: Icons.desktop_windows_rounded,
                ),
                _Choice(
                  value: ShellMode.mobile,
                  title: 'Mobile',
                  description:
                      'Every app opens edge to edge with a compact header and '
                      'thumb-sized controls. Best for one-handed use.',
                  icon: Icons.smartphone_rounded,
                ),
              ],
              onChanged: settings.setShellMode,
            ),
            _ShellModePreview(mode: settings.shellMode),
          ],
        ),
        _Section(
          title: 'Dock',
          caption:
              'Automatic keeps a centred Dock on tablets and desktops, and '
              'hides it on phones until you swipe up from the bottom edge.',
          children: [
            _ChoiceGroup<DockVisibilityMode>(
              value: settings.dockVisibilityMode,
              options: const [
                _Choice(
                  value: DockVisibilityMode.automatic,
                  title: 'Automatic',
                  description:
                      'Centred and persistent on large screens. Swipe up to '
                      'reveal it on phones.',
                  icon: Icons.auto_awesome_rounded,
                ),
                _Choice(
                  value: DockVisibilityMode.alwaysVisible,
                  title: 'Always visible',
                  description:
                      'Keep the Dock centred at all times, even while an app '
                      'has focus.',
                  icon: Icons.vertical_align_bottom_rounded,
                ),
                _Choice(
                  value: DockVisibilityMode.autoHide,
                  title: 'Auto-hide',
                  description:
                      'Hide the Dock everywhere. Swipe up from the bottom edge '
                      'to bring it back.',
                  icon: Icons.visibility_off_rounded,
                ),
              ],
              onChanged: settings.setDockVisibilityMode,
            ),
            const _InfoNote(
              icon: Icons.swipe_up_rounded,
              text:
                  'Swipe up from the bottom of the screen to reveal a hidden '
                  'Dock. It tucks away again after a few seconds.',
            ),
          ],
        ),
        _Section(
          title: 'System',
          children: [
            _SwitchRow(
              icon: Icons.smartphone_rounded,
              iconColor: Sequoia.green,
              title: 'Show Android system bars',
              subtitle:
                  'Restore the Android status and navigation bars instead of '
                  'the immersive Misty shell.',
              value: settings.systemBarsVisible,
              onChanged: (visible) async {
                await settings.setSystemBarsVisible(visible);
                await SystemChrome.setEnabledSystemUIMode(
                  visible
                      ? SystemUiMode.edgeToEdge
                      : SystemUiMode.immersiveSticky,
                );
              },
            ),
          ],
        ),
        _Section(
          title: 'Linux desktop input',
          caption:
              'Touches drive the X11 desktop inside the Linux Desktop window. '
              'The floating keyboard and extra keys work in both modes.',
          children: [
            _ChoiceGroup<DesktopPointerMode>(
              value: settings.desktopPointerMode,
              options: [
                for (final mode in DesktopPointerMode.values)
                  _Choice(
                    value: mode,
                    title: mode.title,
                    description: mode.description,
                    icon: mode == DesktopPointerMode.trackpad
                        ? Icons.touch_app_rounded
                        : Icons.ads_click_rounded,
                  ),
              ],
              onChanged: settings.setDesktopPointerMode,
            ),
            if (settings.desktopPointerMode == DesktopPointerMode.trackpad) ...[
              _SliderCard(
                title: 'Pointer speed',
                value: '${settings.desktopCursorSpeed.toStringAsFixed(2)}×',
                slider: Slider(
                  value: settings.desktopCursorSpeed,
                  min: 0.8,
                  max: 2.0,
                  divisions: 12,
                  label: '${settings.desktopCursorSpeed.toStringAsFixed(2)}×',
                  onChanged: (value) =>
                      settings.setDesktopCursorSpeed(value),
                ),
                footer:
                    'One finger moves the pointer, tap to click, two fingers '
                    'scroll, and a long-press opens the right-click menu.',
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _ShellModePreview extends StatelessWidget {
  const _ShellModePreview({required this.mode});

  final ShellMode mode;

  @override
  Widget build(BuildContext context) {
    final automatic = mode == ShellMode.automatic;
    final mobile = mode == ShellMode.mobile;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 134,
            child: Row(
              children: [
                if (automatic) ...[
                  const Expanded(
                    child: _PreviewStage(label: 'Phone', fullScreen: true),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: _PreviewStage(label: 'Tablet', fullScreen: false),
                  ),
                ] else
                  Expanded(
                    child: _PreviewStage(
                      label: mobile ? 'Phone' : 'Desktop',
                      fullScreen: mobile,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          Text(
            switch (mode) {
              ShellMode.automatic =>
                'Your phone gets full-screen apps; a tablet keeps the '
                    'floating window desktop.',
              ShellMode.desktop =>
                'Windows stay movable and resizable everywhere, exactly like '
                    'macOS.',
              ShellMode.mobile =>
                'Apps fill the screen and the header is sized for thumbs.',
            },
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Sequoia.labelTertiary,
              fontSize: 10.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewStage extends StatelessWidget {
  const _PreviewStage({required this.label, required this.fullScreen});

  final String label;
  final bool fullScreen;

  Widget _line(double fraction, {bool accent = false}) {
    return FractionallySizedBox(
      widthFactor: fraction,
      child: Container(
        height: 3,
        margin: const EdgeInsets.only(bottom: 3),
        decoration: BoxDecoration(
          color: accent
              ? Sequoia.blue.withValues(alpha: 0.85)
              : Colors.white.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final windowRadius = fullScreen ? 0.0 : 6.0;
    return Column(
      children: [
        Expanded(
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2B4C73), Color(0xFF111D2F)],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.10),
                width: 0.7,
              ),
            ),
            child: Stack(
              children: [
                // Mini menu bar.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 7,
                  child: Container(color: const Color(0xCC2A2A2E)),
                ),
                // App window.
                Positioned(
                  left: fullScreen ? 0 : 16,
                  right: fullScreen ? 0 : 16,
                  top: fullScreen ? 7 : 24,
                  bottom: fullScreen ? 0 : 23,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF26262B),
                      borderRadius: BorderRadius.circular(windowRadius),
                      border: Border.all(
                        color: Colors.white.withValues(
                          alpha: fullScreen ? 0.04 : 0.14,
                        ),
                        width: 0.6,
                      ),
                      boxShadow: fullScreen
                          ? null
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          height: 13,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3A3A40),
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(windowRadius),
                            ),
                          ),
                          child: Row(
                            children: [
                              if (fullScreen)
                                const Icon(
                                  Icons.close_rounded,
                                  size: 7,
                                  color: Colors.white54,
                                )
                              else
                                Row(
                                  children: [
                                    _dot(Sequoia.closeLight),
                                    _dot(Sequoia.miniLight),
                                    _dot(Sequoia.zoomLight),
                                  ],
                                ),
                              const Spacer(),
                              Container(
                                width: 22,
                                height: 2,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.24),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const Spacer(),
                              if (fullScreen)
                                const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 8,
                                  color: Colors.white38,
                                )
                              else
                                const SizedBox(width: 12),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              if (!fullScreen)
                                Container(
                                  width: 26,
                                  color: const Color(0xFF2D2D33),
                                  padding: const EdgeInsets.fromLTRB(5, 6, 5, 0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _line(1),
                                      _line(0.72),
                                      _line(0.9),
                                      _line(0.6),
                                    ],
                                  ),
                                ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _line(0.55, accent: true),
                                      _line(0.92),
                                      _line(0.76),
                                      _line(0.46),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Floating Dock only exists in the desktop presentation.
                if (!fullScreen)
                  Positioned(
                    left: 13,
                    right: 13,
                    bottom: 4,
                    height: 14,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xE62E2E33),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < 4; i++)
                            Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.72),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: const TextStyle(
            color: Sequoia.labelSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _dot(Color color) {
    return Container(
      width: 3.5,
      height: 3.5,
      margin: const EdgeInsets.only(right: 2),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _TerminalPage extends StatelessWidget {
  const _TerminalPage({required this.settings});

  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    final profile = kTerminalProfiles.firstWhere(
      (item) => item.id == settings.terminalProfile,
      orElse: () => kTerminalProfiles.first,
    );

    return _PageShell(
      icon: _pageIcon(_Page.terminal),
      accent: _pageAccent(_Page.terminal),
      title: _pageTitle(_Page.terminal),
      subtitle: _pageSubtitle(_Page.terminal),
      children: [
        _Section(
          title: 'Type',
          children: [
            _SliderCard(
              title: 'Font size',
              value: '${settings.terminalFontSize.round()} pt',
              slider: Slider(
                value: settings.terminalFontSize,
                min: 10,
                max: 18,
                divisions: 8,
                label: '${settings.terminalFontSize.round()} pt',
                onChanged: (value) => settings.setTerminalFontSize(value),
              ),
              footer:
                  'JetBrains Mono stays crisp at every size. Existing tabs '
                  'adopt the new size immediately.',
            ),
          ],
        ),
        _Section(
          title: 'Colour profile',
          caption:
              'Every shell and new OpenCode session follows this macOS '
              'palette. Light profiles also switch OpenCode to a light theme.',
          children: [
            _ProfileGrid(
              selected: settings.terminalProfile,
              onChanged: settings.setTerminalProfile,
            ),
            _TerminalPreview(profile: profile),
          ],
        ),
        _Section(
          title: 'OpenCode',
          caption:
              'The AI Hub and every new terminal tab use this palette. White '
              'keeps OpenCode bright even when the shell is black.',
          children: [
            _ChoiceGroup<String>(
              value: settings.openCodeTheme,
              onChanged: settings.setOpenCodeTheme,
              options: [
                for (final theme in kOpenCodeThemes)
                  _Choice(
                    value: theme.id,
                    title: theme.title,
                    description: theme.description,
                    icon: _openCodeIcon(theme.id),
                  ),
              ],
            ),
            _OpenCodePreview(
              preference: settings.openCodeTheme,
              profile: profile,
            ),
          ],
        ),
      ],
    );
  }
}

IconData _openCodeIcon(String id) => switch (id) {
  'light' => Icons.light_mode_rounded,
  'dark' => Icons.dark_mode_rounded,
  'system' => Icons.terminal_rounded,
  'ocean' => Icons.water_rounded,
  'forest' => Icons.forest_rounded,
  'rose' => Icons.local_florist_rounded,
  'sand' => Icons.wb_sunny_rounded,
  _ => Icons.palette_rounded,
};

class _BrowserPage extends StatelessWidget {
  const _BrowserPage({required this.settings});

  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      icon: _pageIcon(_Page.browser),
      accent: _pageAccent(_Page.browser),
      title: _pageTitle(_Page.browser),
      subtitle: _pageSubtitle(_Page.browser),
      children: [
        _Section(
          title: 'Rendering',
          children: [
            _SwitchRow(
              icon: Icons.memory_rounded,
              iconColor: Sequoia.orange,
              title: 'Single-process mode',
              subtitle:
                  'Runs the browser in one process. Helpful on very small '
                  'devices, at the cost of resilience.',
              value: settings.singleProcessBrowser,
              onChanged: settings.setSingleProcessBrowser,
            ),
          ],
        ),
        const _InfoNote(
          icon: Icons.shield_outlined,
          text:
              'Leave single-process mode off unless the browser repeatedly '
              'runs out of memory. Separate renderer processes recover from a '
              'crash without taking the whole browser down.',
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
        _notify(
          'GitHub rejected this token. Check its validity and repository '
          'permissions.',
          error: true,
        );
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
    final connected = _login != null;
    return _PageShell(
      icon: _pageIcon(_Page.github),
      accent: _pageAccent(_Page.github),
      title: _pageTitle(_Page.github),
      subtitle: _pageSubtitle(_Page.github),
      children: [
        _AccountCard(
          icon: Icons.alternate_email_rounded,
          accent: Sequoia.indigo,
          title: connected ? _login! : 'Not connected',
          subtitle: connected
              ? 'Git, GitHub CLI, and OpenCode can use this account.'
              : 'Add a personal access token to sign in.',
          status: connected ? 'Connected' : 'Offline',
          connected: connected,
        ),
        _Section(
          title: 'Personal access token',
          caption:
              'Stored in Android encrypted storage and passed to Linux tools '
              'without writing it into project files.',
          children: [
            _Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _token,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        if (!_busy) _save();
                      },
                      decoration: const InputDecoration(
                        labelText: 'GitHub token',
                        hintText: 'ghp_…',
                        prefixIcon: Icon(Icons.key_rounded, size: 18),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: _busy ? null : _save,
                          icon: _busy
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check_rounded, size: 18),
                          label: const Text('Verify & save'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _busy || !connected ? null : _clear,
                          child: const Text('Disconnect'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_message != null)
              _MessageBanner(message: _message!, error: _error),
          ],
        ),
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
      if (mounted) {
        setState(() => _account = value == null ? null : 'Token saved');
      }
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
    final connected = _account != null;
    return _PageShell(
      icon: _pageIcon(_Page.huggingface),
      accent: _pageAccent(_Page.huggingface),
      title: _pageTitle(_Page.huggingface),
      subtitle: _pageSubtitle(_Page.huggingface),
      children: [
        _AccountCard(
          icon: Icons.auto_awesome_rounded,
          accent: Sequoia.orange,
          title: connected ? _account! : 'Not connected',
          subtitle: connected
              ? 'Linux processes receive this token as HF_TOKEN.'
              : 'Add a token to download models and use AI tools.',
          status: connected ? 'Connected' : 'Offline',
          connected: connected,
        ),
        _Section(
          title: 'Access token',
          caption: 'The token is stored securely and never written to disk.',
          children: [
            _Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _token,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        if (!_busy) _save();
                      },
                      decoration: const InputDecoration(
                        labelText: 'Hugging Face token',
                        hintText: 'hf_…',
                        prefixIcon: Icon(Icons.key_rounded, size: 18),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: _busy ? null : _save,
                          icon: _busy
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check_rounded, size: 18),
                          label: const Text('Verify & save'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _busy || !connected ? null : _clear,
                          child: const Text('Disconnect'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_message != null)
              _MessageBanner(message: _message!, error: _error),
          ],
        ),
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
        const SnackBar(
          content: Text(
            'Storage access was not granted. You can enable it in Android app '
            'settings.',
          ),
        ),
      );
      if (status.isPermanentlyDenied) await openAppSettings();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Storage access granted.')));
    }
  }

  Future<void> _repair(BuildContext context) async {
    final code = await runtime.repairPackages();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          code == 0
              ? 'Linux package repair completed.'
              : 'Package repair exited with code $code.',
        ),
      ),
    );
  }

  Future<void> _stopSession(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop Linux session?'),
        content: const Text(
          'This will terminate active Linux terminals, desktop services and '
          'browser processes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Stop session'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await runtime.stopSession();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Linux session stopped.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = runtime.isBusy;
    final ready = runtime.isReady;
    return _PageShell(
      icon: _pageIcon(_Page.linux),
      accent: _pageAccent(_Page.linux),
      title: _pageTitle(_Page.linux),
      subtitle: _pageSubtitle(_Page.linux),
      children: [
        _LinuxHero(runtime: runtime),
        _Section(
          title: 'Workstation',
          children: [
            _Card(
              children: [
                _ActionRow(
                  icon: ready
                      ? Icons.restart_alt_rounded
                      : Icons.download_rounded,
                  iconColor: Sequoia.blue,
                  title: ready ? 'Reinstall workstation' : 'Install workstation',
                  subtitle:
                      'Download and provision the Ubuntu ARM64 PRoot image.',
                  enabled: !busy,
                  onTap: () => runtime.install(),
                ),
                _ActionRow(
                  icon: Icons.folder_shared_rounded,
                  iconColor: Sequoia.orange,
                  title: 'Android storage access',
                  subtitle: 'Allow Linux apps to read shared folders.',
                  onTap: () => _requestStorage(context),
                ),
                _ActionRow(
                  icon: Icons.healing_rounded,
                  iconColor: Sequoia.teal,
                  title: 'Repair Linux packages',
                  subtitle: 'Reinstall missing packages and desktop entries.',
                  enabled: ready && !busy,
                  onTap: () => _repair(context),
                ),
                _ActionRow(
                  icon: Icons.power_settings_new_rounded,
                  iconColor: Sequoia.red,
                  title: 'Stop Linux session',
                  subtitle:
                      'Close every terminal, desktop process, and browser.',
                  enabled: runtime.hasActiveSession,
                  onTap: () => _stopSession(context),
                ),
              ],
            ),
          ],
        ),
        const _InfoNote(
          icon: Icons.info_outline_rounded,
          text:
              'Linux runs in PRoot without a separate kernel. Android may '
              'reclaim idle sessions in the background; reopening an app '
              'restores the guest.',
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
  final TextEditingController _confirmation = TextEditingController();
  bool _saving = false;
  bool _showPassword = false;
  String? _message;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.settings.userName);
  }

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    await widget.settings.setUserName(_name.text);
    if (mounted) setState(() => _message = 'Display name saved.');
  }

  Future<void> _savePassword() async {
    if (_password.text.length < 4) {
      setState(() {
        _error = 'Use at least 4 characters for the lock password.';
        _message = null;
      });
      return;
    }
    if (_password.text != _confirmation.text) {
      setState(() {
        _error = 'The passwords do not match.';
        _message = null;
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _message = null;
    });
    try {
      await widget.settings.setLoginPassword(_password.text);
      _password.clear();
      _confirmation.clear();
      if (mounted) {
        setState(() => _message = 'Lock screen password saved securely.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Encrypted storage could not save the password. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removePassword() async {
    setState(() {
      _saving = true;
      _error = null;
      _message = null;
    });
    try {
      await widget.settings.setLoginPassword(null);
      _password.clear();
      _confirmation.clear();
      if (mounted) setState(() => _message = 'Lock screen password removed.');
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Encrypted storage could not remove the password. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final trimmed = settings.userName.trim();
    final initial = trimmed.isEmpty
        ? 'M'
        : String.fromCharCode(trimmed.runes.first).toUpperCase();

    return _PageShell(
      icon: _pageIcon(_Page.login),
      accent: _pageAccent(_Page.login),
      title: _pageTitle(_Page.login),
      subtitle: _pageSubtitle(_Page.login),
      children: [
        _Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Sequoia.pink, Sequoia.purple],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Sequoia.pink.withValues(alpha: 0.24),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        settings.userName,
                        style: const TextStyle(
                          color: Sequoia.label,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Local Misty OS account',
                        style: TextStyle(
                          color: Sequoia.labelSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusPill(
                  label: settings.hasPassword ? 'Protected' : 'Open',
                  color: settings.hasPassword
                      ? Sequoia.green
                      : Sequoia.orange,
                ),
              ],
            ),
          ),
        ),
        _Section(
          title: 'Display name',
          children: [
            _Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _name,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Name shown on the lock screen',
                        prefixIcon: Icon(Icons.badge_rounded, size: 18),
                      ),
                      onSubmitted: (_) => _saveName(),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _saving ? null : _saveName,
                        child: const Text('Save name'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        _Section(
          title: 'Lock screen',
          caption:
              'This password protects the Misty OS lock screen only. It does '
              'not encrypt Linux files or replace your Android device lock.',
          children: [
            _Card(
              children: [
                _SettingsRow(
                  leadingIcon: settings.hasPassword
                      ? Icons.lock_rounded
                      : Icons.lock_open_rounded,
                  leadingColor: settings.hasPassword
                      ? Sequoia.green
                      : Sequoia.orange,
                  title: 'Password protection',
                  subtitle: settings.hasPassword
                      ? 'The lock screen asks for your password.'
                      : 'No lock password is set.',
                  trailing: _StatusPill(
                    label: settings.hasPassword ? 'On' : 'Off',
                    color: settings.hasPassword
                        ? Sequoia.green
                        : Sequoia.orange,
                  ),
                ),
                _CardBody(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _password,
                        obscureText: !_showPassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'New lock screen password',
                          helperText: 'At least 4 characters.',
                          prefixIcon: const Icon(Icons.password_rounded, size: 18),
                          suffixIcon: IconButton(
                            tooltip: _showPassword
                                ? 'Hide password'
                                : 'Show password',
                            onPressed: () => setState(
                              () => _showPassword = !_showPassword,
                            ),
                            icon: Icon(
                              _showPassword
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                              size: 19,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _confirmation,
                        obscureText: !_showPassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'Confirm new password',
                          prefixIcon: Icon(Icons.password_rounded, size: 18),
                        ),
                        onSubmitted: (_) => _savePassword(),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          FilledButton(
                            onPressed: _saving ? null : _savePassword,
                            child: Text(_saving ? 'Saving…' : 'Save password'),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: _saving || !settings.hasPassword
                                ? null
                                : _removePassword,
                            child: const Text('Remove'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (settings.loginPasswordStorageUnavailable)
              const _MessageBanner(
                message:
                    'Secure password storage is unavailable. Misty OS will '
                    'keep the lock closed rather than bypass it.',
                error: true,
              ),
            if (settings.loginPasswordMigrationPending)
              const _MessageBanner(
                message:
                    'An older password is still usable, but its secure '
                    'migration is pending. Save a new password when storage is '
                    'available.',
                error: false,
              ),
            if (_error != null) _MessageBanner(message: _error!, error: true),
            if (_message != null)
              _MessageBanner(message: _message!, error: false),
          ],
        ),
      ],
    );
  }
}

class _AboutPage extends StatelessWidget {
  const _AboutPage();

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      icon: _pageIcon(_Page.about),
      accent: _pageAccent(_Page.about),
      title: _pageTitle(_Page.about),
      subtitle: _pageSubtitle(_Page.about),
      children: [
        _Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: Column(
              children: [
                _IconBadge(
                  icon: Icons.blur_on_rounded,
                  color: Sequoia.accent,
                  size: 68,
                  radius: 18,
                ),
                const SizedBox(height: 14),
                const Text(
                  'Misty OS',
                  style: TextStyle(
                    color: Sequoia.label,
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'A calm, cloud-native Linux workstation for mobile.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Sequoia.labelSecondary,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                const _StatusPill(label: 'Version 0.1.0', color: Sequoia.accent),
              ],
            ),
          ),
        ),
        const _Section(
          title: 'This build',
          children: [
            _Card(
              children: [
                _SettingsRow(
                  leadingIcon: Icons.memory_rounded,
                  leadingColor: Sequoia.green,
                  title: 'Linux runtime',
                  subtitle: 'Ubuntu ARM64 in PRoot',
                ),
                _SettingsRow(
                  leadingIcon: Icons.layers_rounded,
                  leadingColor: Sequoia.blue,
                  title: 'Interface',
                  subtitle: 'Flutter shell with native X11 surfaces',
                ),
                _SettingsRow(
                  leadingIcon: Icons.palette_rounded,
                  leadingColor: Sequoia.purple,
                  title: 'Design language',
                  subtitle: 'Golden Gate · Liquid Glass',
                ),
              ],
            ),
          ],
        ),
        const _Section(
          title: 'Credits',
          children: [
            _InfoNote(
              icon: Icons.favorite_rounded,
              text:
                  'Misty OS is hand-built. Its visual language follows the '
                  'macOS Sequoia design guidelines and the MIT-licensed '
                  'macos_ui reference tokens.',
            ),
          ],
        ),
      ],
    );
  }
}

/// Read-only view over the Misty Performance Engine telemetry.
///
/// The page owns its monitor: polling `/proc` and collecting frame timings only
/// happens while this page is on screen, so the shell pays nothing for telemetry
/// it is not displaying.
class _PerformancePage extends StatefulWidget {
  const _PerformancePage();

  @override
  State<_PerformancePage> createState() => _PerformancePageState();
}

class _PerformancePageState extends State<_PerformancePage> {
  final PerformanceMonitor _monitor = PerformanceMonitor();

  @override
  void initState() {
    super.initState();
    _monitor.start();
  }

  @override
  void dispose() {
    _monitor.dispose();
    super.dispose();
  }

  String _mb(int megabytes) {
    if (megabytes <= 0) return '0 MB';
    if (megabytes >= 1024) return '${(megabytes / 1024).toStringAsFixed(1)} GB';
    return '$megabytes MB';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _monitor,
      builder: (context, _) {
        final snapshot = _monitor.snapshot;
        final memory = snapshot.memory;
        final frames = snapshot.frames;
        final pressure = snapshot.memoryPressureAvg10;

        return _PageShell(
          icon: _pageIcon(_Page.performance),
          accent: _pageAccent(_Page.performance),
          title: _pageTitle(_Page.performance),
          subtitle: _pageSubtitle(_Page.performance),
          action: IconButton(
            tooltip: 'Reset frame statistics',
            onPressed: _monitor.resetFrameStats,
            icon: const Icon(
              Icons.restart_alt_rounded,
              size: 20,
              color: Sequoia.labelSecondary,
            ),
          ),
          children: [
            _PerfCard(
              icon: Icons.speed_rounded,
              accent: Sequoia.teal,
              title: 'Dominant bottleneck',
              trailing: snapshot.capturedAt == null
                  ? 'sampling…'
                  : 'updated '
                        '${snapshot.capturedAt!.hour.toString().padLeft(2, '0')}:'
                        '${snapshot.capturedAt!.minute.toString().padLeft(2, '0')}:'
                        '${snapshot.capturedAt!.second.toString().padLeft(2, '0')}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    describeBottleneck(snapshot),
                    style: const TextStyle(
                      color: Sequoia.label,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _PerfPill(
                        label: 'CPU',
                        value: formatPercent(snapshot.cpuPercent),
                      ),
                      _PerfPill(
                        label: 'Memory pressure',
                        value: pressure == null
                            ? 'unavailable'
                            : '${pressure.toStringAsFixed(1)}% · '
                                  '${pressureBand(pressure)}',
                      ),
                      _PerfPill(
                        label: 'Frames p95',
                        value: frames.hasData
                            ? formatMs(frames.p95)
                            : 'no frames yet',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            _PerfCard(
              icon: Icons.memory_rounded,
              accent: Sequoia.blue,
              title: 'Memory',
              trailing: memory.readable
                  ? '${_mb(memory.usedMb)} of ${_mb(memory.totalMb)}'
                  : 'unavailable',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: memory.readable ? memory.usedFraction : null,
                      minHeight: 6,
                      backgroundColor: Colors.white.withValues(alpha: 0.10),
                      color: Sequoia.accent,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PerfRow(
                    label: 'Available',
                    value: memory.readable
                        ? _mb(memory.availableMb)
                        : 'unavailable',
                  ),
                  _PerfRow(
                    label: 'Cached',
                    value: memory.readable
                        ? _mb(memory.cachedKb ~/ 1024)
                        : 'unavailable',
                  ),
                  _PerfRow(
                    label: 'Anonymous pages',
                    value: memory.readable
                        ? _mb(memory.anonKb ~/ 1024)
                        : 'unavailable',
                  ),
                  _PerfRow(
                    label: 'ZRAM / swap in use',
                    value: memory.swapTotalMb > 0
                        ? '${_mb(memory.swapUsedMb)} of '
                              '${_mb(memory.swapTotalMb)}'
                        : 'no swap device',
                  ),
                  _PerfRow(
                    label: 'PSI memory stall',
                    value: pressure == null
                        ? 'unavailable'
                        : '${pressure.toStringAsFixed(1)}% · '
                              '${pressureBand(pressure)}',
                  ),
                ],
              ),
            ),
            _PerfCard(
              icon: Icons.compress_rounded,
              accent: Sequoia.purple,
              title: 'ZRAM compression',
              trailing: formatRatio(snapshot.zramRatio),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PerfRow(
                    label: 'Compressed memory',
                    value: snapshot.zramUsedMb == null
                        ? 'unavailable'
                        : _mb(snapshot.zramUsedMb!),
                  ),
                  _PerfRow(
                    label: 'Physical RAM currently used',
                    value: memory.readable ? _mb(memory.usedMb) : 'unavailable',
                  ),
                  const Text(
                    'zram0 counters are readable on most Android kernels; when '
                    'SELinux hides them the ratio stays unavailable rather than '
                    'being guessed.',
                    style: TextStyle(
                      color: Sequoia.labelTertiary,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            _PerfCard(
              icon: Icons.animation_rounded,
              accent: Sequoia.orange,
              title: 'Rendering',
              trailing: frames.hasData
                  ? '${frames.samples} frames'
                  : 'no samples',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _PerfStat(
                          label: 'p50',
                          value: frames.hasData ? formatMs(frames.p50) : '—',
                        ),
                      ),
                      Expanded(
                        child: _PerfStat(
                          label: 'p95',
                          value: frames.hasData ? formatMs(frames.p95) : '—',
                        ),
                      ),
                      Expanded(
                        child: _PerfStat(
                          label: 'p99',
                          value: frames.hasData ? formatMs(frames.p99) : '—',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    frames.hasData && frames.p95 <= 16.7
                        ? 'Frame pacing is inside the 16.7 ms budget (60 fps).'
                        : 'Frame pacing is above the 16.7 ms budget; expect '
                              'visible stutter.',
                    style: TextStyle(
                      color: frames.hasData && frames.p95 <= 16.7
                          ? Sequoia.green
                          : Sequoia.labelTertiary,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            _PerfCard(
              icon: Icons.list_alt_rounded,
              accent: Sequoia.graphite,
              title: 'Top processes by RSS',
              child: snapshot.topProcesses.isEmpty
                  ? const Text(
                      'Android does not expose other applications to '
                      'third-party /proc reads, so no process list is '
                      'available on this device.',
                      style: TextStyle(
                        color: Sequoia.labelTertiary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final process in snapshot.topProcesses)
                          _PerfRow(
                            label: '${process.name} (${process.pid})',
                            value: _mb(process.rssMb),
                          ),
                        if (snapshot.processListLimited)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'Only processes visible to this app are listed.',
                              style: TextStyle(
                                color: Sequoia.labelTertiary,
                                fontSize: 11,
                              ),
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

// ---------------------------------------------------------------------------
// Shared layout and controls
// ---------------------------------------------------------------------------

class _SettingsSidebar extends StatelessWidget {
  const _SettingsSidebar({required this.page, required this.onSelect});

  final _Page page;
  final ValueChanged<_Page> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 232,
      decoration: BoxDecoration(
        color: const Color(0x660F0F12),
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
            child: Row(
              children: [
                _IconBadge(
                  icon: Icons.settings_rounded,
                  color: Sequoia.accent,
                  size: 32,
                  radius: 9,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Settings',
                        style: TextStyle(
                          color: Sequoia.label,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      Text(
                        'Misty OS',
                        style: TextStyle(
                          color: Sequoia.labelTertiary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 16),
              children: [
                for (final group in _navGroups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 12, 10, 6),
                    child: Text(
                      group.label.toUpperCase(),
                      style: TextStyle(
                        color: Sequoia.labelTertiary.withValues(alpha: 0.8),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ),
                  for (final item in group.pages)
                    _SidebarItem(
                      label: _pageTitle(item),
                      icon: _pageIcon(item),
                      accent: _pageAccent(item),
                      selected: page == item,
                      onTap: () => onSelect(item),
                    ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Text(
              'Misty OS · v0.1.0',
              style: TextStyle(
                color: Sequoia.labelTertiary.withValues(alpha: 0.72),
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactTabs extends StatelessWidget {
  const _CompactTabs({required this.page, required this.onSelect});

  final _Page page;
  final ValueChanged<_Page> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: const Color(0x4D0F0F12),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        children: [
          for (final item in _Page.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _CompactPageTab(
                label: _pageTitle(item),
                icon: _pageIcon(item),
                accent: _pageAccent(item),
                selected: page == item,
                onTap: () => onSelect(item),
              ),
            ),
        ],
      ),
    );
  }
}

class _PageShell extends StatelessWidget {
  const _PageShell({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.children,
    this.action,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth < 430 ? 18.0 : 28.0;
        return ListView(
          padding: EdgeInsets.fromLTRB(horizontal, 24, horizontal, 42),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _IconBadge(
                          icon: icon,
                          color: accent,
                          size: 46,
                          radius: 12,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  color: Sequoia.label,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.5,
                                  height: 1.15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                style: const TextStyle(
                                  color: Sequoia.labelSecondary,
                                  fontSize: 12.5,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (action != null) ...[
                          const SizedBox(width: 8),
                          action!,
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    ...children,
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    this.caption,
  });

  final String title;
  final String? caption;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                color: Sequoia.labelTertiary.withValues(alpha: 0.9),
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ),
          if (caption != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 5, 4, 0),
              child: Text(
                caption!,
                style: const TextStyle(
                  color: Sequoia.labelSecondary,
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
            ),
          const SizedBox(height: 9),
          ...children,
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({this.children, this.child})
    : assert(children != null || child != null);

  final List<Widget>? children;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (child != null) {
      content = child!;
    } else {
      final rows = children!;
      content = Column(
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            rows[index],
            if (index != rows.length - 1) const _Hairline(),
          ],
        ],
      );
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 0.8,
        ),
      ),
      child: content,
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.7,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      color: Colors.white.withValues(alpha: 0.065),
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.all(14), child: child);
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.title,
    this.subtitle,
    this.leadingIcon,
    this.leadingColor,
    this.trailing,
    this.onTap,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final IconData? leadingIcon;
  final Color? leadingColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          if (leadingIcon != null) ...[
            _IconBadge(
              icon: leadingIcon!,
              color: enabled
                  ? (leadingColor ?? Sequoia.accent)
                  : Sequoia.graphite,
              size: 30,
              radius: 8,
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: enabled
                        ? Sequoia.label
                        : Sequoia.labelSecondary.withValues(alpha: 0.65),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: enabled
                          ? Sequoia.labelSecondary
                          : Sequoia.labelTertiary,
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );

    if (onTap == null || !enabled) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
    this.iconColor,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return _SettingsRow(
      title: title,
      subtitle: subtitle,
      leadingIcon: icon,
      leadingColor: iconColor,
      onTap: () => onChanged(!value),
      trailing: Transform.scale(
        scale: 0.92,
        child: Switch(
          value: value,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _SettingsRow(
      leadingIcon: icon,
      leadingColor: iconColor,
      title: title,
      subtitle: subtitle,
      enabled: enabled,
      onTap: onTap,
      trailing: Icon(
        Icons.chevron_right_rounded,
        size: 18,
        color: Sequoia.labelTertiary,
      ),
    );
  }
}

class _Choice<T> {
  const _Choice({
    required this.value,
    required this.title,
    required this.description,
    required this.icon,
  });

  final T value;
  final String title;
  final String description;
  final IconData icon;
}

class _ChoiceGroup<T> extends StatelessWidget {
  const _ChoiceGroup({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<_Choice<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          for (var index = 0; index < options.length; index++) ...[
            _ChoiceRow(
              option: options[index],
              selected: options[index].value == value,
              onTap: () => onChanged(options[index].value),
            ),
            if (index != options.length - 1) const _Hairline(),
          ],
        ],
      ),
    );
  }
}

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _Choice<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? Sequoia.accent.withValues(alpha: 0.10)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              _IconBadge(
                icon: option.icon,
                color: selected ? Sequoia.accent : Sequoia.graphite,
                size: 32,
                radius: 9,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.title,
                      style: TextStyle(
                        color: Sequoia.label,
                        fontSize: 13.5,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      option.description,
                      style: const TextStyle(
                        color: Sequoia.labelSecondary,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? Sequoia.accent : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? Sequoia.accent
                        : Colors.white.withValues(alpha: 0.24),
                    width: 1.2,
                  ),
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        size: 13,
                        color: Colors.white,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SliderCard extends StatelessWidget {
  const _SliderCard({
    required this.title,
    required this.value,
    required this.slider,
    this.footer,
  });

  final String title;
  final String value;
  final Widget slider;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Sequoia.label,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Sequoia.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Sequoia.accent.withValues(alpha: 0.24),
                      width: 0.7,
                    ),
                  ),
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: Sequoia.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              ),
              child: slider,
            ),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  footer!,
                  style: const TextStyle(
                    color: Sequoia.labelTertiary,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProfileGrid extends StatelessWidget {
  const _ProfileGrid({required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 3 : 2;
        final spacing = 10.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final profile in kTerminalProfiles)
              GestureDetector(
                onTap: () => onChanged(profile.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: width,
                  height: 72,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: profile.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: profile.id == selected
                          ? Sequoia.accent
                          : Colors.white.withValues(alpha: 0.12),
                      width: profile.id == selected ? 1.6 : 0.8,
                    ),
                    boxShadow: profile.id == selected
                        ? [
                            BoxShadow(
                              color: Sequoia.accent.withValues(alpha: 0.22),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              profile.name,
                              style: TextStyle(
                                color: profile.foreground,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (profile.id == selected)
                            const Icon(
                              Icons.check_circle_rounded,
                              size: 15,
                              color: Sequoia.accent,
                            ),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          for (final color in profile.ansi.skip(1).take(5))
                            Container(
                              width: 7,
                              height: 7,
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TerminalPreview extends StatelessWidget {
  const _TerminalPreview({required this.profile});

  final TerminalProfile profile;

  @override
  Widget build(BuildContext context) {
    final dim = profile.foreground.withValues(alpha: 0.55);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: profile.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final color in const [
                Sequoia.closeLight,
                Sequoia.miniLight,
                Sequoia.zoomLight,
              ])
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.8),
                    shape: BoxShape.circle,
                  ),
                ),
              const Spacer(),
              Text(
                profile.name,
                style: TextStyle(color: dim, fontSize: 9.5),
              ),
            ],
          ),
          const SizedBox(height: 10),
          RichText(
            text: TextSpan(
              style: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 11,
                height: 1.45,
                color: profile.foreground,
              ),
              children: [
                TextSpan(
                  text: 'misty@phone',
                  style: TextStyle(
                    color: profile.ansi[4],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: ':', style: TextStyle(color: dim)),
                TextSpan(
                  text: '~',
                  style: TextStyle(
                    color: profile.ansi[6],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: ' \$ ', style: TextStyle(color: dim)),
                const TextSpan(text: 'echo "hello, Misty"'),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'hello, Misty',
            style: TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 11,
              height: 1.45,
              color: profile.foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenCodePreview extends StatelessWidget {
  const _OpenCodePreview({required this.preference, required this.profile});

  final String preference;
  final TerminalProfile profile;

  @override
  Widget build(BuildContext context) {
    final choice = openCodeThemeChoice(preference);
    final followsTerminal = choice.followsTerminal;
    final background = followsTerminal ? profile.background : choice.background;
    final foreground = followsTerminal ? profile.foreground : choice.foreground;
    final accent = followsTerminal ? profile.cursor : choice.accent;
    final resolved = resolveOpenCodeTheme(preference, profile);
    final light = background.computeLuminance() > 0.55;
    final dim = foreground.withValues(alpha: 0.58);
    final hairline = light
        ? Colors.black.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.10);

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 13),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hairline, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final color in const [
                Sequoia.closeLight,
                Sequoia.miniLight,
                Sequoia.zoomLight,
              ])
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.85),
                    shape: BoxShape.circle,
                  ),
                ),
              const Spacer(),
              Text(
                '${choice.title} · ${resolved.name}',
                style: TextStyle(color: dim, fontSize: 9.5),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: light ? 0.16 : 0.22),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(Icons.auto_awesome_rounded, size: 14, color: accent),
              ),
              const SizedBox(width: 9),
              Text(
                'OpenCode',
                style: TextStyle(
                  color: foreground,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 7),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: light ? 0.12 : 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  resolved.mode == 'light' ? 'Light' : 'Dark',
                  style: TextStyle(
                    color: accent,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: light
                  ? Colors.black.withValues(alpha: 0.045)
                  : Colors.white.withValues(alpha: 0.055),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: hairline, width: 0.7),
            ),
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 10.5,
                  height: 1.4,
                  color: foreground,
                ),
                children: [
                  TextSpan(
                    text: '> ',
                    style: TextStyle(color: accent, fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: 'what should we build today?'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.connected,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final String status;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.20),
            accent.withValues(alpha: 0.05),
          ],
        ),
        border: Border.all(
          color: accent.withValues(alpha: 0.26),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          _IconBadge(icon: icon, color: accent, size: 44, radius: 12),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Sequoia.label,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Sequoia.labelSecondary,
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _StatusPill(
            label: status,
            color: connected ? Sequoia.green : Sequoia.graphite,
          ),
        ],
      ),
    );
  }
}

class _RuntimeLook {
  const _RuntimeLook(this.label, this.color, this.description);

  final String label;
  final Color color;
  final String description;
}

class _LinuxHero extends StatelessWidget {
  const _LinuxHero({required this.runtime});

  final LinuxRuntime runtime;

  @override
  Widget build(BuildContext context) {
    final look = switch (runtime.status) {
      RuntimeStatus.checking => const _RuntimeLook(
        'Checking',
        Sequoia.graphite,
        'Looking for the installed workstation image.',
      ),
      RuntimeStatus.missing => const _RuntimeLook(
        'Not installed',
        Sequoia.orange,
        'Install the Ubuntu ARM64 workstation to begin.',
      ),
      RuntimeStatus.installing => _RuntimeLook(
        'Installing',
        Sequoia.blue,
        runtime.stage,
      ),
      RuntimeStatus.ready => const _RuntimeLook(
        'Ready',
        Sequoia.green,
        'Terminals, the X11 desktop, and Linux apps are ready.',
      ),
      RuntimeStatus.failed => const _RuntimeLook(
        'Needs attention',
        Sequoia.red,
        'The last setup attempt did not finish.',
      ),
    };
    final color = look.color;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.20),
            color.withValues(alpha: 0.04),
          ],
        ),
        border: Border.all(color: color.withValues(alpha: 0.28), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconBadge(
                icon: Icons.terminal_rounded,
                color: color,
                size: 44,
                radius: 12,
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ubuntu ARM64',
                      style: TextStyle(
                        color: Sequoia.label,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'PRoot workstation',
                      style: TextStyle(
                        color: Sequoia.labelSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusPill(label: look.label, color: color),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            look.description,
            style: const TextStyle(
              color: Sequoia.labelSecondary,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
          if (runtime.isBusy) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: runtime.progress == 0 ? null : runtime.progress,
                minHeight: 5,
                backgroundColor: Colors.white.withValues(alpha: 0.10),
                color: color,
              ),
            ),
          ],
          if (runtime.error != null) ...[
            const SizedBox(height: 10),
            Text(
              runtime.error!,
              style: const TextStyle(
                color: Sequoia.red,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PerfCard extends StatelessWidget {
  const _PerfCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _IconBadge(icon: icon, color: accent, size: 26, radius: 7),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Sequoia.label,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (trailing != null)
                    Text(
                      trailing!,
                      style: const TextStyle(
                        color: Sequoia.labelTertiary,
                        fontSize: 10.5,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _PerfPill extends StatelessWidget {
  const _PerfPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
          width: 0.7,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Sequoia.labelTertiary,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Sequoia.label,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PerfRow extends StatelessWidget {
  const _PerfRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Sequoia.labelSecondary,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: const TextStyle(
              color: Sequoia.label,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _PerfStat extends StatelessWidget {
  const _PerfStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Sequoia.labelTertiary,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Sequoia.label,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({
    required this.icon,
    required this.color,
    required this.size,
    required this.radius,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.30),
            color.withValues(alpha: 0.13),
          ],
        ),
        border: Border.all(color: color.withValues(alpha: 0.34), width: 0.8),
      ),
      child: Icon(icon, size: size * 0.52, color: color),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24), width: 0.7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: Sequoia.accent.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Sequoia.accent.withValues(alpha: 0.14),
            width: 0.7,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 15, color: Sequoia.labelSecondary),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Sequoia.labelSecondary,
                  fontSize: 11,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message, required this.error});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? Sequoia.red : Sequoia.green;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.24), width: 0.7),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              error
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              size: 15,
              color: color,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: color,
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sequoia-style sidebar row: a compact selection pill with a tinted icon.
class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: 0.22)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: 0.28)
                    : Colors.transparent,
                width: 0.7,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: selected ? accent : Sequoia.labelTertiary,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Sequoia.label : Sequoia.labelSecondary,
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
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

/// Compact page switcher shown when the window is too narrow for a sidebar.
class _CompactPageTab extends StatelessWidget {
  const _CompactPageTab({
    required this.label,
    required this.icon,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: 0.045),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.32)
                  : Colors.white.withValues(alpha: 0.06),
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 14,
                color: selected ? accent : Sequoia.labelTertiary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Sequoia.label : Sequoia.labelSecondary,
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
