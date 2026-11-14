import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micro_os/services/settings_store.dart';
import 'package:micro_os/ui/login_screen.dart';

void main() {
  testWidgets('animated login screen continues when no password is configured',
      (tester) async {
    final settings = SettingsStore();
    var unlocked = false;

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          settings: settings,
          onUnlock: () => unlocked = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Continue to Desktop'), findsOneWidget);
    await tester.tap(find.text('Continue to Desktop'));
    await tester.pump();

    expect(unlocked, isTrue);
    settings.dispose();
  });

  testWidgets('password login rejects wrong input and accepts the saved password',
      (tester) async {
    final settings = SettingsStore()..loginPassword = 'microos-test-password';
    var unlocked = false;

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          settings: settings,
          onUnlock: () => unlocked = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'wrong-password');
    await tester.tap(find.byTooltip('Unlock Misty OS'));
    await tester.pump();

    expect(find.text('Incorrect password. Try again.'), findsOneWidget);
    expect(unlocked, isFalse);

    await tester.enterText(find.byType(TextField), 'microos-test-password');
    await tester.tap(find.byTooltip('Unlock Misty OS'));
    await tester.pump();

    expect(unlocked, isTrue);
    settings.dispose();
  });

  testWidgets('password visibility control is available', (tester) async {
    final settings = SettingsStore()..loginPassword = 'test-password';

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(settings: settings, onUnlock: () {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Show password'), findsOneWidget);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();

    expect(find.byTooltip('Hide password'), findsOneWidget);
    settings.dispose();
  });
}
