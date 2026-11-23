/// Linux applications that Misty OS can launch inside the X11 desktop.
///
/// These are real desktop programs, not Flutter placeholders. Each entry keeps
/// the artwork and the guest command in one place so Launchpad, the X11 desktop
/// and the window manager all show the same icon for the same program.
class LinuxApp {
  const LinuxApp({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.command,
    required this.iconAsset,
  });

  /// Stable identifier used by settings and desktop shortcuts.
  final String id;
  final String title;
  final String subtitle;

  /// Shell command executed inside the Linux guest.
  final String command;

  /// Bundled 256px PNG artwork extracted from the application's real icon.
  final String iconAsset;
}

const List<LinuxApp> kLinuxApps = <LinuxApp>[
  LinuxApp(
    id: 'chrome',
    title: 'Chrome',
    subtitle: 'Web browser',
    command: '/usr/local/bin/start-browser.sh',
    iconAsset: 'assets/icons/linux/chrome.png',
  ),
  LinuxApp(
    id: 'blender',
    title: 'Blender',
    subtitle: '3D creation suite',
    command: 'blender',
    iconAsset: 'assets/icons/linux/blender.png',
  ),
  LinuxApp(
    id: 'files',
    title: 'Files',
    subtitle: 'Linux file manager',
    command: 'pcmanfm',
    iconAsset: 'assets/icons/linux/files.png',
  ),
  LinuxApp(
    id: 'texteditor',
    title: 'Text Editor',
    subtitle: 'Write and edit text',
    command: 'mousepad',
    iconAsset: 'assets/icons/linux/texteditor.png',
  ),
  LinuxApp(
    id: 'gimp',
    title: 'GIMP',
    subtitle: 'Image editor',
    command: 'gimp',
    iconAsset: 'assets/icons/linux/gimp.png',
  ),
  LinuxApp(
    id: 'inkscape',
    title: 'Inkscape',
    subtitle: 'Vector graphics',
    command: 'inkscape',
    iconAsset: 'assets/icons/linux/inkscape.png',
  ),
  LinuxApp(
    id: 'vlc',
    title: 'VLC',
    subtitle: 'Media player',
    command: 'vlc',
    iconAsset: 'assets/icons/linux/vlc.png',
  ),
  LinuxApp(
    id: 'writer',
    title: 'LibreOffice Writer',
    subtitle: 'Documents',
    command: 'libreoffice --writer',
    iconAsset: 'assets/icons/linux/writer.png',
  ),
  LinuxApp(
    id: 'calc',
    title: 'LibreOffice Calc',
    subtitle: 'Spreadsheets',
    command: 'libreoffice --calc',
    iconAsset: 'assets/icons/linux/calc.png',
  ),
  LinuxApp(
    id: 'geany',
    title: 'Geany',
    subtitle: 'Code editor',
    command: 'geany',
    iconAsset: 'assets/icons/linux/geany.png',
  ),
  LinuxApp(
    id: 'gitcola',
    title: 'Git Cola',
    subtitle: 'Git client',
    command: 'git-cola',
    iconAsset: 'assets/icons/linux/gitcola.png',
  ),
];

LinuxApp? linuxAppById(String id) {
  for (final app in kLinuxApps) {
    if (app.id == id) return app;
  }
  return null;
}
