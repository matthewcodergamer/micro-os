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
    this.ansi,
  );

  final String id;
  final String name;
  final Color background;
  final Color foreground;
  final Color cursor;
  final Color selection;
  final List<Color> ansi; // 16 colors

  TerminalTheme toXterm() {
    return TerminalTheme(
      background: background,
      foreground: foreground,
      cursor: cursor,
      selection: selection,
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
    const Color(0xFF1E1E1E),
    const Color(0xFFF2F2F7),
    const Color(0xFF0A84FF),
    const Color(0x553A86FF),
    const [
      Color(0xFF000000),
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
  ),
  TerminalProfile(
    'pro',
    'Pro',
    const Color(0xFF1C1C1E),
    const Color(0xFFF2F2F7),
    const Color(0xFF0A84FF),
    const Color(0x553A86FF),
    const [
      Color(0xFF000000),
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
  ),
];

TerminalProfile profileById(String id) {
  for (final p in kTerminalProfiles) {
    if (p.id == id) return p;
  }
  return kTerminalProfiles.first;
}
