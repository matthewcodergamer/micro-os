import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app_scope.dart';
import '../../core/macos_design.dart';
import '../../core/terminal_profiles.dart';
import '../../core/wallpapers.dart';
import '../../core/theme.dart';
import '../../services/github_auth.dart';
import '../../services/linux_runtime.dart';
import '../../services/performance_monitor.dart';
import '../../services/settings_store.dart';

enum _Page {
  desktop,
  wallpaper,
  pointer,
  performance,
  github,
  huggingface,
  linux,
  terminal,
  browser,
  login,
  about,
}

class SettingsApp extends StatefulWidget {
  const SettingsApp({super.key, required this.runtime});

  final LinuxRuntime runtime;

  @override
  State<SettingsApp> createState() => _SettingsAppState();
}

class _SettingsAppState extends State<SettingsApp> {
  _Page _page = _Page.desktop;
  String _search = '';

  IconData _icon(_Page page) => switch (page) {
    _Page.desktop => Icons.display_settings_rounded,
    _Page.wallpaper => Icons.wallpaper_rounded,
    _Page.pointer => Icons.mouse_rounded,
    _Page.performance => Icons.speed_rounded,
    _Page.github => Icons.code_rounded,
    _Page.huggingface => Icons.hub_rounded,
    _Page.linux => Icons.terminal_rounded,
    _Page.terminal => Icons.keyboard_rounded,
    _Page.browser => Icons.language_rounded,
    _Page.login => Icons.person_rounded,
    _Page.about => Icons.info_outline_rounded,
  };

  List<_Page> get _visiblePages => _Page.values.where((page) =>
    _title(page).toLowerCase().contains(_search.trim().toLowerCase())).toList();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final settings = scope.settings;
    final auth = scope.auth;
    final runtime = widget.runtime;
    final wide = MediaQuery.sizeOf(context).width > 600;

    final content = ListenableBuilder(
      listenable: Listenable.merge([settings, runtime]),
      builder: (context, _) {
        return switch (_page) {
          _Page.desktop => _DesktopPage(settings: settings),
          _Page.wallpaper => _WallpaperPage(settings: settings),
          _Page.pointer => _PointerPage(settings: settings),
          _Page.performance => const _PerformancePage(),
          _Page.github => _GitHubPage(auth: auth, runtime: runtime),
          _Page.huggingface => _HuggingFacePage(auth: auth, runtime: runtime),
          _Page.linux => _LinuxPage(runtime: runtime),
          _Page.terminal => _TerminalPage(settings: settings),
          _Page.browser => _BrowserPage(settings: settings),
          _Page.login => _LoginPage(settings: settings),
          _Page.about => const _AboutPage(),
        };
      },
    );

    if (wide) {
      return Row(
        children: [
          Container(
            width: Sequoia.sidebarWidth,
            decoration: BoxDecoration(
              // Sequoia sidebars are translucent over the window body rather
              // than a flat grey column.
              color: Sequoia.sidebarTint.withValues(alpha: 0.86),
              border: Border(
                right: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
              ),
            ),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(10, 3, 8, 12),
                  child: Text('SYSTEM SETTINGS', style: TextStyle(
                    color: Sequoia.labelTertiary, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 1.1)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
                  child: SizedBox(height: 34, child: TextField(
                    onChanged: (value) => setState(() => _search = value),
                    style: const TextStyle(color: Sequoia.label, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Search settings',
                      hintStyle: const TextStyle(color: Sequoia.labelTertiary, fontSize: 12),
                      prefixIcon: const Icon(Icons.search_rounded, size: 16, color: Sequoia.labelSecondary),
                      filled: true, fillColor: Colors.black.withValues(alpha: 0.16),
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  )),
                ),
                for (final page in _visiblePages)
                  _SidebarItem(
                    label: _title(page),
                    icon: _icon(page),
                    selected: _page == page,
                    onTap: () => setState(() => _page = page),
                  ),
                if (_visiblePages.isEmpty)
                  const Padding(padding: EdgeInsets.all(10), child: Text('No matching settings', style: TextStyle(color: Sequoia.labelTertiary, fontSize: 11))),
              ],
            ),
          ),
          Expanded(child: content),
        ],
      );
    }

    // Phones get a horizontal page bar instead. Without it the sidebar simply
    // disappeared below 600 px and every settings page except the first one
    // became unreachable.
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
          child: SizedBox(
            height: 34,
            child: TextField(
              onChanged: (value) => setState(() => _search = value),
              style: const TextStyle(color: Sequoia.label, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Search settings',
                hintStyle: const TextStyle(
                  color: Sequoia.labelTertiary,
                  fontSize: 12,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 16,
                  color: Sequoia.labelSecondary,
                ),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => _search = ''),
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 15,
                          color: Sequoia.labelSecondary,
                        ),
                      ),
                filled: true,
                fillColor: Sequoia.sidebarTint.withValues(alpha: 0.62),
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: _visiblePages.isEmpty
              ? const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'No matching settings',
                      style: TextStyle(
                        color: Sequoia.labelTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                )
              : ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  children: [
                    for (final page in _visiblePages)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _CompactPageTab(
                          label: _title(page),
                          selected: _page == page,
                          onTap: () => setState(() => _page = page),
                        ),
                      ),
                  ],
                ),
        ),
        const Divider(height: 1),
        Expanded(child: content),
      ],
    );
  }

  String _title(_Page p) => switch (p) {
    _Page.desktop => 'Desktop & Dock',
    _Page.wallpaper => 'Wallpaper',
    _Page.pointer => 'Trackpad & Pointer',
    _Page.performance => 'Performance',
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
        const Text(
          'Desktop & Dock',
          style: TextStyle(
            color: MicroColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 20),
        SwitchListTile(
          title: const Text(
            'Automatically hide and show the Dock',
            style: TextStyle(color: MicroColors.text),
          ),
          value: settings.dockAutoHide,
          onChanged: (v) => settings.setDockAutoHide(v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Magnify icons on hover', style: TextStyle(color: MicroColors.text)),
          subtitle: const Text('Enlarge nearby Dock icons as the pointer moves across them.', style: TextStyle(color: MicroColors.subtle, fontSize: 12)),
          value: settings.dockMagnification,
          onChanged: (value) => settings.setDockMagnification(value),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(
              child: Text('Dock icon size', style: TextStyle(color: MicroColors.text, fontWeight: FontWeight.w600)),
            ),
            Text('${(settings.dockScale * 100).round()}%', style: const TextStyle(color: MicroColors.subtle, fontSize: 12)),
          ],
        ),
        Slider(
          min: 0.8,
          max: 1.2,
          divisions: 8,
          value: (settings.dockScale as double).clamp(0.8, 1.2).toDouble(),
          label: '${(settings.dockScale * 100).round()}%',
          onChanged: (value) => settings.setDockScale(value),
        ),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Smaller', style: TextStyle(color: MicroColors.subtle, fontSize: 11)),
            Text('Larger', style: TextStyle(color: MicroColors.subtle, fontSize: 11)),
          ],
        ),
        const Divider(height: 28),
        SwitchListTile(
          title: const Text(
            'Show Android system bars',
            style: TextStyle(color: MicroColors.text),
          ),
          subtitle: const Text(
            'Temporarily restore the status and navigation bars',
            style: TextStyle(color: MicroColors.subtle, fontSize: 12),
          ),
          value: settings.systemBarsVisible,
          onChanged: (visible) async {
            await settings.setSystemBarsVisible(visible);
            await SystemChrome.setEnabledSystemUIMode(
              visible ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
            );
          },
        ),
      ],
    );
  }
}

class _PointerPage extends StatelessWidget {
  const _PointerPage({required this.settings});
  final dynamic settings;

  @override
  Widget build(BuildContext context) {
    final speed = settings.trackpadSpeed as double;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Trackpad & Pointer',
          style: TextStyle(
            color: MicroColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Tune touch gestures for the Linux desktop. Changes are saved on this device and applied to the active VNC session.',
          style: TextStyle(color: MicroColors.subtle, fontSize: 12),
        ),
        const SizedBox(height: 18),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Trackpad mode', style: TextStyle(color: MicroColors.text)),
          subtitle: const Text(
            'Move a visible pointer with relative finger movement. Turn off for direct touch-to-screen positioning.',
            style: TextStyle(color: MicroColors.subtle, fontSize: 12),
          ),
          value: settings.trackpadMode,
          onChanged: (value) => settings.setTrackpadMode(value),
        ),
        const Divider(height: 24),
        Row(
          children: [
            const Expanded(
              child: Text('Pointer speed', style: TextStyle(color: MicroColors.text, fontWeight: FontWeight.w600)),
            ),
            Text('${speed.toStringAsFixed(2)}×', style: const TextStyle(color: MicroColors.subtle, fontSize: 12)),
          ],
        ),
        Slider(
          min: 0.7,
          max: 2.2,
          divisions: 15,
          value: speed.clamp(0.7, 2.2).toDouble(),
          label: '${speed.toStringAsFixed(2)}×',
          onChanged: (value) => settings.setTrackpadSpeed(value),
        ),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Slow', style: TextStyle(color: MicroColors.subtle, fontSize: 11)),
            Text('Fast', style: TextStyle(color: MicroColors.subtle, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Sequoia.sidebarTint.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: const Text(
            'Gestures: one finger moves and clicks, a long press opens the context menu, and two fingers scroll. Use the desktop toolbar for a quick right-click or keyboard.',
            style: TextStyle(color: Sequoia.labelSecondary, fontSize: 12, height: 1.45),
          ),
        ),
      ],
    );
  }
}

class _WallpaperPage extends StatelessWidget {
  const _WallpaperPage({required this.settings});
  final dynamic settings;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const Text(
          'Wallpaper',
          style: TextStyle(
            color: MicroColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Choose the desktop background. Your selection is saved on this device.',
          style: TextStyle(color: MicroColors.subtle, fontSize: 12),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth > 650 ? 3 : 2;
            final itemWidth = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 14,
              children: [
                for (final wallpaper in kWallpapers)
                  SizedBox(
                    width: itemWidth,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => settings.setWallpaper(wallpaper.id),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: AspectRatio(
                                  aspectRatio: 16 / 10,
                                  child: Image.asset(
                                    wallpaper.asset,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: Sequoia.sidebarTint,
                                      alignment: Alignment.center,
                                      child: const Icon(Icons.image_not_supported_outlined,
                                          color: Sequoia.labelSecondary),
                                    ),
                                  ),
                                ),
                              ),
                              if (settings.wallpaper == wallpaper.id)
                                Positioned(
                                  right: 8,
                                  top: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF0A84FF),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.check, size: 14, color: Colors.white),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          Text(
                            wallpaper.name,
                            style: TextStyle(
                              color: MicroColors.text,
                              fontSize: 12,
                              fontWeight: settings.wallpaper == wallpaper.id
                                  ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
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
          'GitHub rejected this token. Check its validity and repository permissions.',
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
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'GitHub',
          style: TextStyle(
            color: MicroColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _login == null ? 'Not connected' : 'Connected as $_login',
          style: const TextStyle(color: MicroColors.subtle),
        ),
        const SizedBox(height: 16),
        const Text(
          'Use a Personal Access Token. It is stored in secure platform storage and supplied to Linux tools without writing it into project files.',
          style: TextStyle(color: MicroColors.subtle, fontSize: 12),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _token,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'GitHub Personal Access Token',
            hintText: 'ghp_…',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Verify & Save'),
            ),
            TextButton(
              onPressed: _busy || _login == null ? null : _clear,
              child: const Text('Disconnect'),
            ),
          ],
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(
            _message!,
            style: TextStyle(
              color: _error ? MicroColors.red : MicroColors.green,
              fontSize: 12,
            ),
          ),
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
      if (mounted)
        setState(() => _account = value == null ? null : 'Token saved');
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
        const Text(
          'Hugging Face',
          style: TextStyle(
            color: MicroColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _account == null ? 'Not connected' : 'Connected · $_account',
          style: const TextStyle(color: MicroColors.subtle),
        ),
        const SizedBox(height: 16),
        const Text(
          'The access token is stored securely and passed to Linux processes as HF_TOKEN.',
          style: TextStyle(color: MicroColors.subtle, fontSize: 12),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _token,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Hugging Face access token',
            hintText: 'hf_…',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Verify & Save'),
            ),
            TextButton(
              onPressed: _busy || _account == null ? null : _clear,
              child: const Text('Disconnect'),
            ),
          ],
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(
            _message!,
            style: TextStyle(
              color: _error ? MicroColors.red : MicroColors.green,
              fontSize: 12,
            ),
          ),
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
        const SnackBar(
          content: Text(
            'Storage access was not granted. You can enable it in Android app settings.',
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
          'This will terminate active Linux terminals, desktop services and browser processes.',
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
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Linux session stopped.')));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Linux',
          style: TextStyle(
            color: MicroColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Status: ${runtime.status.name}',
          style: const TextStyle(color: MicroColors.subtle),
        ),
        if (runtime.error != null) ...[
          const SizedBox(height: 8),
          Text(
            runtime.error!,
            style: const TextStyle(color: MicroColors.red, fontSize: 12),
          ),
        ],
        if (runtime.isBusy) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: runtime.progress == 0 ? null : runtime.progress,
          ),
          Text(
            runtime.stage,
            style: const TextStyle(color: MicroColors.subtle, fontSize: 13),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: runtime.isBusy ? null : () => runtime.install(),
          child: Text(
            runtime.isReady ? 'Reinstall Workstation' : 'Install Workstation',
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => _requestStorage(context),
          child: const Text('Grant Android storage access'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: !runtime.isReady || runtime.isBusy
              ? null
              : () => _repair(context),
          child: const Text('Repair Linux packages'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: runtime.hasActiveSession
              ? () => _stopSession(context)
              : null,
          child: const Text('Stop Linux session'),
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
        const Text(
          'Terminal',
          style: TextStyle(
            color: MicroColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Font size: ${settings.terminalFontSize.round()}',
          style: const TextStyle(color: MicroColors.text),
        ),
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
        const Text(
          'Browser',
          style: TextStyle(
            color: MicroColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        SwitchListTile(
          title: const Text(
            'Single-process mode',
            style: TextStyle(color: MicroColors.text),
          ),
          subtitle: const Text(
            'More stable on low-memory devices',
            style: TextStyle(color: MicroColors.subtle, fontSize: 12),
          ),
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
      if (mounted)
        setState(() => _message = 'Lock screen password saved securely.');
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
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Users & Login',
          style: TextStyle(
            color: MicroColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
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
          child: OutlinedButton(
            onPressed: _saving ? null : _saveName,
            child: const Text('Save display name'),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          settings.hasPassword
              ? 'Password protection is enabled'
              : 'No lock password is set',
          style: TextStyle(
            color: settings.hasPassword
                ? MicroColors.green
                : MicroColors.subtle,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _password,
          obscureText: !_showPassword,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'New lock screen password',
            helperText:
                'At least 4 characters. Saved using Android encrypted storage.',
            suffixIcon: IconButton(
              tooltip: _showPassword ? 'Hide password' : 'Show password',
              onPressed: () => setState(() => _showPassword = !_showPassword),
              icon: Icon(
                _showPassword ? Icons.visibility_off : Icons.visibility,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmation,
          obscureText: !_showPassword,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'Confirm new password'),
          onSubmitted: (_) => _savePassword(),
        ),
        const SizedBox(height: 8),
        const Text(
          'This password protects the Misty OS lock screen only. It does not encrypt Linux files or replace your Android device lock.',
          style: TextStyle(
            color: MicroColors.subtle,
            fontSize: 12,
            height: 1.4,
          ),
        ),
        if (settings.loginPasswordStorageUnavailable) ...[
          const SizedBox(height: 8),
          const Text(
            'Secure password storage is unavailable. Misty OS will keep the lock closed rather than bypass it.',
            style: TextStyle(color: MicroColors.red, fontSize: 12),
          ),
        ],
        if (settings.loginPasswordMigrationPending) ...[
          const SizedBox(height: 8),
          const Text(
            'An older password is still usable, but its secure migration is pending. Save a new password when storage is available.',
            style: TextStyle(color: MicroColors.amber, fontSize: 12),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              onPressed: _saving ? null : _savePassword,
              child: Text(_saving ? 'Saving…' : 'Save password'),
            ),
            TextButton(
              onPressed: _saving || !settings.hasPassword
                  ? null
                  : _removePassword,
              child: const Text('Remove password'),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: const TextStyle(color: MicroColors.red, fontSize: 12),
          ),
        ],
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(
            _message!,
            style: const TextStyle(color: MicroColors.green, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

class _AboutPage extends StatelessWidget {
  const _AboutPage();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'About Misty OS',
          style: TextStyle(
            color: MicroColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 12),
        Text(
          'Misty OS is a lightweight, cloud-native Linux workstation designed to run seamlessly on mobile hardware.',
          style: TextStyle(color: MicroColors.subtle),
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

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Performance',
                    style: TextStyle(
                      color: MicroColors.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Reset frame statistics',
                  onPressed: _monitor.resetFrameStats,
                  icon: const Icon(
                    Icons.restart_alt_rounded,
                    size: 20,
                    color: MicroColors.subtle,
                  ),
                ),
              ],
            ),
            const Text(
              'Every value is measured on this device. Sources the kernel hides are '
              'reported as unavailable instead of being estimated.',
              style: TextStyle(
                color: MicroColors.subtle,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            _PerfCard(
              title: 'Dominant bottleneck',
              trailing: snapshot.capturedAt == null
                  ? 'sampling…'
                  : 'updated ${snapshot.capturedAt!.hour.toString().padLeft(2, '0')}:'
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
              title: 'Memory',
              trailing: memory.readable
                  ? '${_mb(memory.usedMb)} of ${_mb(memory.totalMb)}'
                  : 'unavailable',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
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
                        ? '${_mb(memory.swapUsedMb)} of ${_mb(memory.swapTotalMb)}'
                        : 'no swap device',
                  ),
                  _PerfRow(
                    label: 'PSI memory stall',
                    value: pressure == null
                        ? 'unavailable'
                        : '${pressure.toStringAsFixed(1)}% · ${pressureBand(pressure)}',
                  ),
                ],
              ),
            ),
            _PerfCard(
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
                    'zram0 counters are readable on most Android kernels; when SELinux hides '
                    'them the ratio stays unavailable rather than being guessed.',
                    style: TextStyle(
                      color: MicroColors.subtle,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            _PerfCard(
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
                        : 'Frame pacing is above the 16.7 ms budget; expect visible stutter.',
                    style: TextStyle(
                      color: frames.hasData && frames.p95 <= 16.7
                          ? MicroColors.green
                          : MicroColors.subtle,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            _PerfCard(
              title: 'Top processes by RSS',
              child: snapshot.topProcesses.isEmpty
                  ? const Text(
                      'Android does not expose other applications to third-party /proc reads, '
                      'so no process list is available on this device.',
                      style: TextStyle(
                        color: MicroColors.subtle,
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
                                color: MicroColors.subtle,
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

class _PerfCard extends StatelessWidget {
  const _PerfCard({required this.title, required this.child, this.trailing});

  final String title;
  final String? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: Sequoia.groupedCard(radius: Sequoia.popoverRadius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: MicroColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (trailing != null)
                Text(
                  trailing!,
                  style: const TextStyle(
                    color: MicroColors.subtle,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
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
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: MicroColors.subtle, fontSize: 10),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: MicroColors.text,
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
              style: const TextStyle(color: MicroColors.subtle, fontSize: 12),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: const TextStyle(
              color: MicroColors.text,
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
          style: const TextStyle(color: MicroColors.subtle, fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: MicroColors.text,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Sequoia-style sidebar row: 34 px tall, 7 px radius selection pill.
class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: onTap,
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: selected
                  ? Sequoia.accent.withValues(alpha: 0.26)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
            ),
            alignment: Alignment.centerLeft,
            child: Row(children: [
              Icon(icon, size: 16, color: selected ? Sequoia.label : Sequoia.labelSecondary),
              const SizedBox(width: 9),
              Expanded(child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Sequoia.label : Sequoia.labelSecondary,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
              )),
            ]),
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
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? Sequoia.accent.withValues(alpha: 0.26)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Sequoia.label : Sequoia.labelSecondary,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
