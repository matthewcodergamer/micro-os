import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// Terminal.app-style colour profiles (Basic, Grass, Homebrew, ...).
class TerminalProfile {
  const TerminalProfile(
    this.id,
    this.name,
    this.background,
    this.foreground,
    this.cursor,
    this.selection,
    this.ansi, {
    this.opencodeTheme = 'opencode',
    this.opencodeMode = 'dark',
  });

  final String id;
  final String name;
  final Color background;
  final Color foreground;
  final Color cursor;
  final Color selection;
  final List<Color> ansi; // 16 colors

  /// OpenCode TUI theme that matches this macOS Terminal profile.
  ///
  /// The terminal passes this to OpenCode through
  /// OPENCODE_CLI_CONFIG_CONTENT, so the TUI does not have to guess the
  /// terminal background. A white/cream profile gets a light OpenCode theme;
  /// every dark profile gets a matching dark theme.
  final String opencodeTheme;
  final String opencodeMode;

  TerminalTheme toXterm() {
    return TerminalTheme(
      background: background,
      foreground: foreground,
      cursor: cursor,
      selection: selection,
      searchHitBackground: selection,
      searchHitBackgroundCurrent: cursor,
      searchHitForeground: foreground,
      black: ansi[0],
      red: ansi[1],
      green: ansi[2],
      yellow: ansi[3],
      blue: ansi[4],
      magenta: ansi[5],
      cyan: ansi[6],
      white: ansi[7],
      brightBlack: ansi[8],
      brightRed: ansi[9],
      brightGreen: ansi[10],
      brightYellow: ansi[11],
      brightBlue: ansi[12],
      brightMagenta: ansi[13],
      brightCyan: ansi[14],
      brightWhite: ansi[15],
    );
  }
}

const String kDefaultTerminalProfile = 'basic';

final List<TerminalProfile> kTerminalProfiles = [
  TerminalProfile(
    'basic',
    'Basic',
    const Color(0xFF000000),
    const Color(0xFFF5F5F7),
    const Color(0xFFFFFFFF),
    const Color(0x550A84FF),
    const [
      Color(0xFF2C2C2E),
      Color(0xFFFF5F57),
      Color(0xFF28C840),
      Color(0xFFFEBC2E),
      Color(0xFF0A84FF),
      Color(0xFFBF5AF2),
      Color(0xFF5AC8FA),
      Color(0xFFD0D0D0),
      Color(0xFF808080),
      Color(0xFFFF5F57),
      Color(0xFF28C840),
      Color(0xFFFEBC2E),
      Color(0xFF0A84FF),
      Color(0xFFBF5AF2),
      Color(0xFF5AC8FA),
      Color(0xFFFFFFFF),
    ],
    opencodeTheme: 'opencode',
    opencodeMode: 'dark',
  ),
  TerminalProfile(
    'basic-light',
    'Basic Light',
    const Color(0xFFFFFFFF),
    const Color(0xFF1C1C1E),
    const Color(0xFF0A84FF),
    const Color(0x330A84FF),
    const [
      Color(0xFF3A3A3C),
      Color(0xFFC41A16),
      Color(0xFF007400),
      Color(0xFF826B28),
      Color(0xFF0000FF),
      Color(0xFFA90D91),
      Color(0xFF0F7B7B),
      Color(0xFF8E8E93),
      Color(0xFF6E6E73),
      Color(0xFFE53935),
      Color(0xFF2E7D32),
      Color(0xFF9E7B00),
      Color(0xFF0A84FF),
      Color(0xFFBF5AF2),
      Color(0xFF00A6A6),
      Color(0xFF1C1C1E),
    ],
    opencodeTheme: 'github',
    opencodeMode: 'light',
  ),
  TerminalProfile(
    'grass',
    'Grass',
    const Color(0xFF1A2F1A),
    const Color(0xFFE8F5E9),
    const Color(0xFF4CAF50),
    const Color(0x554CAF50),
    const [
      Color(0xFF0D1F0D),
      Color(0xFFE57373),
      Color(0xFF81C784),
      Color(0xFFFFD54F),
      Color(0xFF64B5F6),
      Color(0xFFBA68C8),
      Color(0xFF4DD0E1),
      Color(0xFFC8E6C9),
      Color(0xFF558B2F),
      Color(0xFFEF5350),
      Color(0xFF66BB6A),
      Color(0xFFFFCA28),
      Color(0xFF42A5F5),
      Color(0xFFAB47BC),
      Color(0xFF26C6DA),
      Color(0xFFFFFFFF),
    ],
    opencodeTheme: 'everforest',
    opencodeMode: 'dark',
  ),
  TerminalProfile(
    'homebrew',
    'Homebrew',
    const Color(0xFF000000),
    const Color(0xFF00FF00),
    const Color(0xFF00FF00),
    const Color(0x5500FF00),
    const [
      Color(0xFF000000),
      Color(0xFF990000),
      Color(0xFF00A600),
      Color(0xFF999900),
      Color(0xFF0000B2),
      Color(0xFFB200B2),
      Color(0xFF00A6B2),
      Color(0xFFBFBFBF),
      Color(0xFF666666),
      Color(0xFFE50000),
      Color(0xFF00D900),
      Color(0xFFE5E500),
      Color(0xFF0000FF),
      Color(0xFFE500E5),
      Color(0xFF00E5E5),
      Color(0xFFE5E5E5),
    ],
    opencodeTheme: 'matrix',
    opencodeMode: 'dark',
  ),
  TerminalProfile(
    'ocean',
    'Ocean',
    const Color(0xFF0B1C2C),
    const Color(0xFFE0F0FF),
    const Color(0xFF4FC3F7),
    const Color(0x554FC3F7),
    const [
      Color(0xFF0B1C2C),
      Color(0xFFEF5350),
      Color(0xFF66BB6A),
      Color(0xFFFFCA28),
      Color(0xFF42A5F5),
      Color(0xFFAB47BC),
      Color(0xFF26C6DA),
      Color(0xFFB0BEC5),
      Color(0xFF546E7A),
      Color(0xFFEF5350),
      Color(0xFF66BB6A),
      Color(0xFFFFCA28),
      Color(0xFF42A5F5),
      Color(0xFFAB47BC),
      Color(0xFF26C6DA),
      Color(0xFFFFFFFF),
    ],
    opencodeTheme: 'tokyonight',
    opencodeMode: 'dark',
  ),
  TerminalProfile(
    'pro',
    'Pro',
    const Color(0xFF1C1C1E),
    const Color(0xFFF2F2F7),
    const Color(0xFF0A84FF),
    const Color(0x553A86FF),
    const [
      Color(0xFF2C2C2E),
      Color(0xFFFF453A),
      Color(0xFF32D74B),
      Color(0xFFFFD60A),
      Color(0xFF0A84FF),
      Color(0xFFBF5AF2),
      Color(0xFF64D2FF),
      Color(0xFFD1D1D6),
      Color(0xFF8E8E93),
      Color(0xFFFF453A),
      Color(0xFF32D74B),
      Color(0xFFFFD60A),
      Color(0xFF0A84FF),
      Color(0xFFBF5AF2),
      Color(0xFF64D2FF),
      Color(0xFFFFFFFF),
    ],
    opencodeTheme: 'one-dark',
    opencodeMode: 'dark',
  ),
  TerminalProfile(
    'red-sands',
    'Red Sands',
    const Color(0xFF2A1C19),
    const Color(0xFFF5E6D3),
    const Color(0xFFFF6B4A),
    const Color(0x55FF6B4A),
    const [
      Color(0xFF3B2925),
      Color(0xFFE06C5A),
      Color(0xFF8FBF6A),
      Color(0xFFE0B15A),
      Color(0xFF6A9FD1),
      Color(0xFFC98BC4),
      Color(0xFF6FC3C3),
      Color(0xFFE7D8C7),
      Color(0xFF8D7268),
      Color(0xFFFF8A75),
      Color(0xFFA8D18A),
      Color(0xFFF2C97A),
      Color(0xFF8AB8E6),
      Color(0xFFDDA8D8),
      Color(0xFF8FD9D9),
      Color(0xFFFFF7EE),
    ],
    opencodeTheme: 'gruvbox',
    opencodeMode: 'dark',
  ),
  TerminalProfile(
    'solarized-light',
    'Solarized Light',
    const Color(0xFFFDF6E3),
    const Color(0xFF586E75),
    const Color(0xFF268BD2),
    const Color(0x33268BD2),
    const [
      Color(0xFF073642),
      Color(0xFFDC322F),
      Color(0xFF859900),
      Color(0xFFB58900),
      Color(0xFF268BD2),
      Color(0xFFD33682),
      Color(0xFF2AA198),
      Color(0xFF586E75),
      Color(0xFF002B36),
      Color(0xFFCB4B16),
      Color(0xFF657B83),
      Color(0xFF839496),
      Color(0xFF6C71C4),
      Color(0xFF93A1A1),
      Color(0xFF2AA198),
      Color(0xFFFDF6E3),
    ],
    opencodeTheme: 'solarized',
    opencodeMode: 'light',
  ),
];

TerminalProfile profileById(String id) {
  for (final p in kTerminalProfiles) {
    if (p.id == id) return p;
  }
  return kTerminalProfiles.first;
}
