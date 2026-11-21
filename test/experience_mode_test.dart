import 'package:flutter_test/flutter_test.dart';
import 'package:micro_os/core/experience_mode.dart';

void main() {
  group('ExperienceMode', () {
    test('desktop mode selects pointer-first interaction', () {
      expect(ExperienceMode.desktop.storageValue, 'desktop');
      expect(ExperienceMode.desktop.usesTrackpadPointer, isTrue);
      expect(ExperienceModePresentation.fromStorage('desktop'), ExperienceMode.desktop);
    });

    test('mobile desktop mode selects direct-touch interaction', () {
      expect(ExperienceMode.mobileDesktop.storageValue, 'mobile-desktop');
      expect(ExperienceMode.mobileDesktop.usesTrackpadPointer, isFalse);
      expect(ExperienceModePresentation.fromStorage('mobile-desktop'), ExperienceMode.mobileDesktop);
    });

    test('unknown or missing stored values trigger first-run selection', () {
      expect(ExperienceModePresentation.fromStorage(null), isNull);
      expect(ExperienceModePresentation.fromStorage('unknown'), isNull);
    });
  });
}
