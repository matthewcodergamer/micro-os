import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micro_os/core/shell_mode.dart';
import 'package:micro_os/models/window_state.dart';
import 'package:micro_os/services/linux_runtime.dart';
import 'package:micro_os/state/desktop_state.dart';

void main() {
  group('ShellMode', () {
    test('automatic uses full-screen apps on phones and windows on tablets',
        () {
      expect(resolveMobileShell(ShellMode.automatic, const Size(390, 844)),
          isTrue);
      expect(resolveMobileShell(ShellMode.automatic, const Size(844, 390)),
          isTrue);
      expect(resolveMobileShell(ShellMode.automatic, const Size(1024, 768)),
          isFalse);
    });

    test('explicit modes ignore the screen size', () {
      expect(resolveMobileShell(ShellMode.mobile, const Size(1280, 900)),
          isTrue);
      expect(resolveMobileShell(ShellMode.desktop, const Size(390, 844)),
          isFalse);
    });

    test('storage values round-trip and unknown values fall back', () {
      for (final mode in ShellMode.values) {
        expect(shellModeFromStorage(mode.storageValue), mode);
      }
      expect(shellModeFromStorage('nonsense'), ShellMode.automatic);
      expect(shellModeFromStorage(null), ShellMode.automatic);
    });
  });

  group('DesktopState presentation', () {
    test('a phone opens apps edge to edge', () {
      final desktop = DesktopState(LinuxRuntime());
      desktop.syncToScreen(
        const Size(390, 844),
        shellMode: ShellMode.automatic,
      );

      final window = desktop.open(AppId.settings, screen: const Size(390, 844));

      expect(window.maximized, isTrue);
      expect(window.pinned, isTrue);
      expect(window.rect, const Rect.fromLTWH(0, 28, 390, 816));

      desktop.dispose();
    });

    test('desktop mode keeps a floating, screen-sized window on a phone', () {
      final desktop = DesktopState(LinuxRuntime());
      desktop.syncToScreen(
        const Size(390, 844),
        shellMode: ShellMode.desktop,
      );

      final window = desktop.open(AppId.settings, screen: const Size(390, 844));

      expect(window.maximized, isFalse);
      expect(window.pinned, isFalse);
      expect(window.rect.width, lessThanOrEqualTo(390));
      expect(window.rect.height, lessThanOrEqualTo(844));
      expect(window.rect.left, greaterThanOrEqualTo(0));

      desktop.dispose();
    });

    test('switching modes full-screens and restores windows losslessly', () {
      final desktop = DesktopState(LinuxRuntime());
      desktop.syncToScreen(
        const Size(1200, 800),
        shellMode: ShellMode.desktop,
      );
      final window = desktop.open(
        AppId.terminal,
        screen: const Size(1200, 800),
      );
      final floating = window.rect;

      desktop.syncToScreen(
        const Size(390, 844),
        shellMode: ShellMode.mobile,
      );
      expect(window.maximized, isTrue);
      expect(window.pinned, isTrue);
      expect(window.rect, const Rect.fromLTWH(0, 28, 390, 816));

      desktop.syncToScreen(
        const Size(1200, 800),
        shellMode: ShellMode.desktop,
      );
      expect(window.maximized, isFalse);
      expect(window.pinned, isFalse);
      expect(window.rect, floating);

      desktop.dispose();
    });
  });
}
