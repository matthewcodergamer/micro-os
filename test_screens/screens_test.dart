import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micro_os/core/shell_mode.dart';
import 'package:micro_os/models/window_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

void main() {
  late Directory rootfs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await loadAppFonts();
    rootfs = createPreviewRootfs();
  });

  tearDownAll(() {
    try {
      rootfs.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<PreviewApp> boot(
    WidgetTester tester,
    DeviceProfile device, {
    bool unlock = true,
    ShellMode mode = ShellMode.automatic,
  }) async {
    device.apply(tester);
    addTearDown(tester.view.reset);
    final app = PreviewApp.create(rootfs);
    app.settings.shellMode = mode;
    await tester.pumpWidget(app.build());
    await settle(tester);
    if (unlock) {
      desktopOf(tester).unlock();
      await settle(tester);
    }
    return app;
  }

  Future<void> open(WidgetTester tester, AppId app, DeviceProfile device) async {
    desktopOf(tester).open(app, screen: device.size);
    await settle(tester, frames: 10);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  void scene(String name, Future<void> Function(WidgetTester tester) body) {
    testWidgets(name, (tester) async {
      await recordingErrors(name, () async {
        await body(tester);
        await capture(tester, name);
      });
      await finish(tester);
    });
  }

  const phone = DeviceProfile.phonePortrait;
  const landscape = DeviceProfile.phoneLandscape;
  const tablet = DeviceProfile.tablet;

  scene('01-phone-login', (tester) async {
    await boot(tester, phone, unlock: false);
  });

  scene('02-phone-home', (tester) async {
    await boot(tester, phone);
  });

  scene('03-phone-dock', (tester) async {
    await boot(tester, phone);
    await tester.tapAt(
      Offset(phone.size.width / 2, phone.size.height - phone.bottomGesture - 20),
    );
    await settle(tester);
  });

  scene('04-phone-terminal', (tester) async {
    await boot(tester, phone);
    await open(tester, AppId.terminal, phone);
  });

  scene('05-phone-ai-hub', (tester) async {
    await boot(tester, phone);
    await open(tester, AppId.aiHub, phone);
  });

  scene('06-phone-finder', (tester) async {
    await boot(tester, phone);
    await open(tester, AppId.files, phone);
  });

  scene('07-phone-settings', (tester) async {
    await boot(tester, phone);
    await open(tester, AppId.settings, phone);
  });

  scene('08-phone-launchpad', (tester) async {
    await boot(tester, phone);
    await tester.tap(find.byTooltip('Launchpad'));
    await settle(tester);
  });

  scene('09-phone-control-center', (tester) async {
    await boot(tester, phone);
    await tester.tap(find.byTooltip('Control Center'));
    await settle(tester);
  });

  scene('10-landscape-desktop-mode', (tester) async {
    await boot(tester, landscape, mode: ShellMode.desktop);
    await open(tester, AppId.files, landscape);
    await open(tester, AppId.terminal, landscape);
  });

  scene('11-tablet-desktop', (tester) async {
    await boot(tester, tablet);
    await open(tester, AppId.files, tablet);
    await open(tester, AppId.settings, tablet);
    await open(tester, AppId.terminal, tablet);
  });
}
