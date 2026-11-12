import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../core/theme.dart';
import '../models/window_state.dart';
import 'apps/ai_hub_app.dart';
import 'apps/desktop_session_app.dart';
import 'apps/files_app.dart';
import 'apps/settings_app.dart';
import 'apps/terminal_app.dart';
import 'dock.dart';
import 'install_screen.dart';
import 'status_bar.dart';
import 'window_frame.dart';

/// The desktop: wallpaper, window layer, menu bar, Dock.
class DesktopScreen extends StatefulWidget {
  const DesktopScreen({super.key});

  @override
  State<DesktopScreen> createState() => _DesktopScreenState();
}

class _DesktopScreenState extends State<DesktopScreen> {
  Size _size = Size.zero;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          if (size != _size) {
            _size = size;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) scope.desktop.syncToScreen(size);
            });
          }

          final compact = size.width < 720;

          return AnimatedBuilder(
            animation: scope.desktop,
            builder: (context, _) {
              final fullScreen = compact && scope.desktop.focused?.maximized == true;
              return Stack(
                children: [
                  const Positioned.fill(child: _Wallpaper()),
                  for (final window in scope.desktop.ordered)
                    if (!window.minimized)
                      Positioned(
                        left: window.rect.left,
                        top: window.rect.top,
                        width: window.rect.width,
                        height: window.rect.height,
                        child: WindowFrame(
                          window: window,
                          screen: size,
                          desktop: scope.desktop,
                          child: _contentFor(window, scope),
                        ),
                      ),
                  if (scope.desktop.windows.isEmpty && scope.runtime.isReady)
                    Positioned.fill(
                      child: _WelcomePanel(
                        onOpen: (app) => scope.desktop.open(app, screen: size),
                      ),
                    ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: StatusBar(
                      desktop: scope.desktop,
                      stats: scope.stats,
                    ),
                  ),
                  if (!keyboardOpen && !fullScreen)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: compact ? 10 : 14,
                      child: Center(
                        child: Dock(
                          desktop: scope.desktop,
                          compact: compact,
                          onOpen: (app) =>
                              scope.desktop.open(app, screen: size),
                        ),
                      ),
                    ),
                  if (!scope.runtime.isReady)
                    Positioned.fill(child: InstallScreen(runtime: scope.runtime)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _contentFor(ManagedWindow window, AppScope scope) {
    switch (window.app) {
      case AppId.terminal:
        return TerminalTabsApp(runtime: scope.runtime, argv: window.args, settings: scope.settings);
      case AppId.desktop:
        return DesktopSessionApp(runtime: scope.runtime);
      case AppId.browser:
        return DesktopSessionApp(
          runtime: scope.runtime,
          launchBrowser: true,
          singleProcess: scope.settings.singleProcessBrowser,
        );
      case AppId.files:
        return FilesApp(runtime: scope.runtime);
      case AppId.aiHub:
        return AiHubApp(runtime: scope.runtime, settings: scope.settings);
      case AppId.settings:
        return SettingsApp(runtime: scope.runtime);
    }
  }
}

/// Cheap gradient wallpaper with two soft light sources. Drawn with plain
/// containers so it costs nothing while windows are being dragged.
class _Wallpaper extends StatelessWidget {
  const _Wallpaper();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF10131B), Color(0xFF1A1430), Color(0xFF07131A)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            left: -80,
            child: _Glow(color: const Color(0xFF2F5BFF), size: 380),
          ),
          Positioned(
            bottom: -160,
            right: -100,
            child: _Glow(color: const Color(0xFF7C4DFF), size: 420),
          ),
          Positioned(
            top: 180,
            right: 40,
            child: _Glow(color: const Color(0xFF00A67E), size: 220),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}


/// First-run home surface: a clear launchpad instead of an empty wallpaper.
class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel({required this.onOpen});

  final ValueChanged<AppId> onOpen;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 600;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 52, 18, 126),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 660),
          child: Container(
            padding: EdgeInsets.all(compact ? 18 : 26),
            decoration: BoxDecoration(
              color: const Color(0xC9141925),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0x30FFFFFF)),
              boxShadow: const [
                BoxShadow(color: Color(0x55000000), blurRadius: 38, offset: Offset(0, 18)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF53B7FF), Color(0xFF6B68F5)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: const Icon(Icons.terminal_rounded, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('MICROOS WORKSPACE', style: TextStyle(color: Color(0xFF7FC6FF), fontSize: 9, letterSpacing: 1.6, fontWeight: FontWeight.w800)),
                        SizedBox(height: 3),
                        Text('Your workspace is ready', style: TextStyle(color: MicroColors.text, fontSize: 18, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const Spacer(),
                    const _ReadyPill(),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Build real projects from your phone. Open a code workspace, browse your files, or start the Linux terminal.',
                  style: TextStyle(color: MicroColors.subtle, fontSize: 12, height: 1.55),
                ),
                const SizedBox(height: 22),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth < 430 ? 1 : 2;
                    final gap = 10.0;
                    final cardWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        _LaunchCard(
                          width: cardWidth,
                          icon: Icons.auto_awesome_rounded,
                          color: const Color(0xFF00A67E),
                          title: 'OpenCode',
                          subtitle: 'AI coding agent · edit projects',
                          onTap: () => onOpen(AppId.aiHub),
                        ),
                        _LaunchCard(
                          width: cardWidth,
                          icon: Icons.folder_open_rounded,
                          color: const Color(0xFFE6A23C),
                          title: 'Phone files',
                          subtitle: 'Open Downloads and project folders',
                          onTap: () => onOpen(AppId.files),
                        ),
                        _LaunchCard(
                          width: cardWidth,
                          icon: Icons.public_rounded,
                          color: const Color(0xFF7C72F5),
                          title: 'Firefox',
                          subtitle: 'Pre-installed desktop browser',
                          onTap: () => onOpen(AppId.browser),
                        ),
                        _LaunchCard(
                          width: cardWidth,
                          icon: Icons.terminal_rounded,
                          color: const Color(0xFF3988E8),
                          title: 'Terminal',
                          subtitle: 'Python · Node · Rust · Git',
                          onTap: () => onOpen(AppId.terminal),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0x141F9D74),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0x332FCA91)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.tips_and_updates_outlined, color: Color(0xFF64D6A8), size: 17),
                      const SizedBox(width: 9),
                      const Expanded(
                        child: Text(
                          'Tip: open Phone files, find your project or Minecraft .jar, then choose “Terminal here” and run microos-jar inspect file.jar or microos-jar extract file.jar. OpenCode can work in that same folder.',
                          style: TextStyle(color: MicroColors.text, fontSize: 10, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => onOpen(AppId.settings),
                    icon: const Icon(Icons.tune_rounded, size: 16),
                    label: const Text('Set up API tokens & storage'),
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

class _ReadyPill extends StatelessWidget {
  const _ReadyPill();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0x1F35C78A),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: const Color(0x6635C78A)),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle, color: Color(0xFF59D69B), size: 12),
        SizedBox(width: 5),
        Text('READY', style: TextStyle(color: Color(0xFF83E4B5), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.7)),
      ],
    ),
  );
}

class _LaunchCard extends StatelessWidget {
  const _LaunchCard({
    required this.width,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final double width;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Material(
      color: const Color(0x18FFFFFF),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x20FFFFFF)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: MicroColors.text, fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: MicroColors.subtle, fontSize: 9, height: 1.3)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, color: MicroColors.subtle, size: 12),
            ],
          ),
        ),
      ),
    ),
  );
}
