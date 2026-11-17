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

    test('windows can snap to either half and return to their prior size', () {
      final desktop = DesktopState(LinuxRuntime());
      desktop.syncToScreen(const Size(1200, 800));
      final window = desktop.open(AppId.terminal, screen: const Size(1200, 800));
      final original = window.rect;

      desktop.snapToHalf(window.id, const Size(1200, 800), left: true);
      expect(window.rect.left, 0);
      expect(window.rect.width, 600);
      expect(window.maximized, isFalse);

      desktop.snapToHalf(window.id, const Size(1200, 800), left: false);
      expect(window.rect.left, 600);
      expect(window.rect.width, 600);

      desktop.centerWindow(window.id, const Size(1200, 800));
      expect(window.rect, original);
      desktop.dispose();
    });

    test('minimized windows remain restorable with their original geometry', () {
      final desktop = DesktopState(LinuxRuntime());
      desktop.syncToScreen(const Size(1200, 800));
      final window = desktop.open(AppId.browser, screen: const Size(1200, 800));
      final original = window.rect;

      desktop.minimize(window.id);
      expect(window.minimized, isTrue);
      expect(window.rect.top, greaterThan(800));
      expect(desktop.windowFor(AppId.browser), same(window));

      desktop.focus(window.id);
      expect(window.minimized, isFalse);
      expect(window.rect, original);
      expect(window.restoreRect, isNull);
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
