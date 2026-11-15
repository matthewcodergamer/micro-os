import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micro_os/core/wallpapers.dart';
import 'package:micro_os/models/window_state.dart';
import 'package:micro_os/services/linux_runtime.dart';
import 'package:micro_os/state/desktop_state.dart';

void main() {
  group('DesktopState geometry', () {
    test('a window opened before the screen is measured is never zero-sized',
        () {
      final desktop = DesktopState(LinuxRuntime());

      final window = desktop.open(AppId.files);

      expect(window.rect.width, greaterThan(0));
      expect(window.rect.height, greaterThan(0));
      expect(window.rect.left.isFinite, isTrue);
      expect(window.rect.top.isFinite, isTrue);

      desktop.dispose();
    });

    test('a compact screen pins the window to the usable area', () {
      final desktop = DesktopState(LinuxRuntime());

      final window = desktop.open(AppId.settings, screen: const Size(420, 880));

      expect(window.maximized, isTrue);
      expect(window.rect.width, 420);
      expect(window.rect.top, desktop.topReserve);
      expect(window.rect.bottom, 880);

      desktop.dispose();
    });

    test('rotation clamps a floating window back inside the usable area', () {
      final desktop = DesktopState(LinuxRuntime());
      desktop.syncToScreen(const Size(1200, 800));

      final window = desktop.open(AppId.terminal, screen: const Size(1200, 800));
      expect(window.maximized, isFalse);

      desktop.syncToScreen(const Size(1000, 700));
      expect(window.rect.right, lessThanOrEqualTo(1000));
      expect(window.rect.bottom, lessThanOrEqualTo(700));

      desktop.dispose();
    });
  });

  group('Wallpapers', () {
    test('the approved Misty sky is the default wallpaper', () {
      expect(kWallpapers.first.asset, 'assets/wallpapers/option3.png');
      expect(kDefaultWallpaperId, kWallpapers.first.id);
    });

    test('an unknown wallpaper id falls back to the default', () {
      expect(wallpaperAssetFor('does-not-exist'), kWallpapers.first.asset);
    });
  });
}
