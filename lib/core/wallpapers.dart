/// Desktop wallpaper catalogue.
///
/// The first entry is the approved "option 3" Misty sky. Wallpapers live under
/// `assets/wallpapers/`; `tool/fetch_thanasos_wallpapers.sh` downloads the
/// upstream Big Sur/Tahoe assets at build time, while the Misty sky is
/// committed so the onboarding screen always has its background.
class MistyWallpaper {
  const MistyWallpaper({
    required this.id,
    required this.name,
    required this.asset,
  });

  final String id;
  final String name;
  final String asset;
}

const List<MistyWallpaper> kWallpapers = <MistyWallpaper>[
  MistyWallpaper(
    id: 'misty',
    name: 'Misty Sky',
    asset: 'assets/wallpapers/option3.png',
  ),
  MistyWallpaper(
    id: 'sequoia',
    name: 'Sequoia',
    asset: 'assets/wallpapers/sequoia.jpg',
  ),
  MistyWallpaper(
    id: 'bigsur',
    name: 'Big Sur',
    asset: 'assets/wallpapers/wallpaper-bigsur.png',
  ),
];

const String kDefaultWallpaperId = 'misty';

MistyWallpaper wallpaperById(String id) {
  for (final wallpaper in kWallpapers) {
    if (wallpaper.id == id) return wallpaper;
  }
  return kWallpapers.first;
}

String wallpaperAssetFor(String id) => wallpaperById(id).asset;
