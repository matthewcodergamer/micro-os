import 'package:flutter_test/flutter_test.dart';
import 'package:micro_os/core/desktop_input.dart';

void main() {
  group('DesktopPointerMode', () {
    test('defaults to trackpad for unknown or missing values', () {
      expect(
        DesktopPointerModeInfo.fromStorage(null),
        DesktopPointerMode.trackpad,
      );
      expect(
        DesktopPointerModeInfo.fromStorage('something-else'),
        DesktopPointerMode.trackpad,
      );
    });

    test('round-trips both modes through storage', () {
      for (final mode in DesktopPointerMode.values) {
        expect(
          DesktopPointerModeInfo.fromStorage(mode.storageValue),
          mode,
        );
      }
    });

    test('cycles through both pointer profiles', () {
      expect(
        DesktopPointerMode.trackpad.next,
        DesktopPointerMode.direct,
      );
      expect(
        DesktopPointerMode.direct.next,
        DesktopPointerMode.trackpad,
      );
    });

    test('only trackpad mode draws the virtual cursor', () {
      expect(DesktopPointerMode.trackpad.usesVisibleCursor, isTrue);
      expect(DesktopPointerMode.direct.usesVisibleCursor, isFalse);
      expect(DesktopPointerMode.trackpad.title, isNotEmpty);
      expect(DesktopPointerMode.direct.description, isNotEmpty);
    });
  });
}
