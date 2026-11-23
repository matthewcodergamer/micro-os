import 'package:flutter/material.dart';

import 'terminal_profiles.dart';

/// An OpenCode TUI palette that can be selected independently of the shell.
///
/// OpenCode paints its own background, so a white TUI can sit inside a black
/// macOS Terminal window. [themeName] and [mode] are the values OpenCode reads
/// from `cli.json` / `OPENCODE_CLI_CONFIG_CONTENT`.
class OpenCodeThemeChoice {
  const OpenCodeThemeChoice({
    required this.id,
    required this.title,
    required this.description,
    required this.themeName,
    required this.mode,
    required this.background,
    required this.foreground,
    required this.accent,
  });

  final String id;
  final String title;
  final String description;
  final String themeName;
  final String mode;
  final Color background;
  final Color foreground;
  final Color accent;

  /// True for the option that follows the selected Terminal profile.
  bool get followsTerminal => id == 'system';
}

const String kDefaultOpenCodeTheme = 'light';

const List<OpenCodeThemeChoice> kOpenCodeThemes = <OpenCodeThemeChoice>[
  OpenCodeThemeChoice(
    id: 'light',
    title: 'White',
    description: 'GitHub Light · a clean white canvas with blue accents.',
    themeName: 'github',
    mode: 'light',
    background: Color(0xFFFFFFFF),
    foreground: Color(0xFF1F2328),
    accent: Color(0xFF0969DA),
  ),
  OpenCodeThemeChoice(
    id: 'dark',
    title: 'Graphite',
    description: 'OpenCode · the signature dark palette with a warm accent.',
    themeName: 'opencode',
    mode: 'dark',
    background: Color(0xFF0D0D0F),
    foreground: Color(0xFFEDEDED),
    accent: Color(0xFFFFB454),
  ),
  OpenCodeThemeChoice(
    id: 'system',
    title: 'Match Terminal',
    description: 'Follow the selected macOS Terminal colour profile.',
    themeName: '',
    mode: '',
    background: Color(0xFF1C1C1E),
    foreground: Color(0xFFF5F5F7),
    accent: Color(0xFF0A84FF),
  ),
  OpenCodeThemeChoice(
    id: 'ocean',
    title: 'Ocean',
    description: 'Tokyo Night · deep blue panels and periwinkle text.',
    themeName: 'tokyonight',
    mode: 'dark',
    background: Color(0xFF1A1B26),
    foreground: Color(0xFFC0CAF5),
    accent: Color(0xFF7AA2F7),
  ),
  OpenCodeThemeChoice(
    id: 'forest',
    title: 'Forest',
    description: 'Everforest · soft moss green, easy on the eyes.',
    themeName: 'everforest',
    mode: 'dark',
    background: Color(0xFF2D353B),
    foreground: Color(0xFFD3C6AA),
    accent: Color(0xFFA7C080),
  ),
  OpenCodeThemeChoice(
    id: 'rose',
    title: 'Rose',
    description: 'Catppuccin · lavender and mauve on a midnight base.',
    themeName: 'catppuccin',
    mode: 'dark',
    background: Color(0xFF1E1E2E),
    foreground: Color(0xFFCDD6F4),
    accent: Color(0xFFF5C2E7),
  ),
  OpenCodeThemeChoice(
    id: 'sand',
    title: 'Sand',
    description: 'Solarized Light · warm parchment with blue links.',
    themeName: 'solarized',
    mode: 'light',
    background: Color(0xFFFDF6E3),
    foreground: Color(0xFF586E75),
    accent: Color(0xFF268BD2),
  ),
];

class ResolvedOpenCodeTheme {
  const ResolvedOpenCodeTheme(this.name, this.mode);

  final String name;
  final String mode;
}

/// Turns a stored preference into the values OpenCode expects.
///
/// `system` follows the shell's [TerminalProfile]; everything else selects one
/// of the curated palettes above. Unknown/legacy values fall back to White.
ResolvedOpenCodeTheme resolveOpenCodeTheme(
  String preference,
  TerminalProfile profile,
) {
  if (preference == 'system') {
    return ResolvedOpenCodeTheme(profile.opencodeTheme, profile.opencodeMode);
  }
  for (final choice in kOpenCodeThemes) {
    if (choice.id == preference && !choice.followsTerminal) {
      return ResolvedOpenCodeTheme(choice.themeName, choice.mode);
    }
  }
  final fallback = kOpenCodeThemes.first;
  return ResolvedOpenCodeTheme(fallback.themeName, fallback.mode);
}

OpenCodeThemeChoice openCodeThemeChoice(String preference) {
  for (final choice in kOpenCodeThemes) {
    if (choice.id == preference) return choice;
  }
  return kOpenCodeThemes.first;
}
