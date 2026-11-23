import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micro_os/ui/desktop_key_bar.dart';

void main() {
  testWidgets(
    'extra keys send paired down/up events and release one-shot modifiers',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final events = <String>[];
      final texts = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Align(
              alignment: Alignment.bottomCenter,
              child: DesktopKeyBar(
                onKeyEvent: (keysym, code, down) async {
                  events.add('$code:${down ? 'down' : 'up'}');
                },
                onText: (text) async => texts.add(text),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('CTRL'));
      await tester.pump();
      expect(events, ['ControlLeft:down']);

      await tester.tap(find.text('ESC'));
      await tester.pumpAndSettle();
      expect(events, [
        'ControlLeft:down',
        'Escape:down',
        'Escape:up',
        'ControlLeft:up',
      ]);

      await tester.tap(find.text('|'));
      await tester.pump();
      expect(texts, ['|']);
      expect(events.last, 'ControlLeft:up');
    },
  );

  testWidgets('modifier lock holds Ctrl until tapped a third time',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final events = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopKeyBar(
            onKeyEvent: (keysym, code, down) async {
              events.add('$code:${down ? 'down' : 'up'}');
            },
            onText: (_) async {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('CTRL'));
    await tester.pump();
    await tester.tap(find.text('CTRL'));
    await tester.pump();
    expect(events, ['ControlLeft:down']);

    await tester.tap(find.text('CTRL'));
    await tester.pumpAndSettle();
    expect(events, ['ControlLeft:down', 'ControlLeft:up']);
  });
}
