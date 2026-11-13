import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:micro_os/core/terminal_paste.dart';

void main() {
  group('splitTerminalPaste', () {
    test('keeps every chunk within the configured UTF-16 size', () {
      final input = List<String>.filled(2400, 'x').join();
      final chunks = splitTerminalPaste(input).toList();

      expect(chunks.length, greaterThan(1));
      expect(chunks.every((chunk) => chunk.length <= 500), isTrue);
      expect(chunks.join(), input);
    });

    test('never splits emoji surrogate pairs and preserves UTF-8 bytes', () {
      final input = 'NaN😀NaN🌴';
      final chunks = splitTerminalPaste(input).toList();

      for (final chunk in chunks) {
        final units = chunk.codeUnits;
        for (var i = 0; i < units.length; i++) {
          final unit = units[i];
          if (unit >= 0xD800 && unit <= 0xDBFF) {
            expect(i + 1, lessThan(units.length));
            expect(units[i + 1], inInclusiveRange(0xDC00, 0xDFFF));
          }
          if (unit >= 0xDC00 && unit <= 0xDFFF) {
            expect(i, greaterThan(0));
            expect(units[i - 1], inInclusiveRange(0xD800, 0xDBFF));
          }
        }
      }

      expect(utf8.encode(chunks.join()), utf8.encode(input));
    });

    test('preserves multiline code and mixed Unicode exactly', () {
      const input = 'echo "hello 👋"\nprint("café")\ncd /root/项目\n';
      expect(splitTerminalPaste(input).join(), input);
    });

    test('returns no chunks for empty input', () {
      expect(splitTerminalPaste('').toList(), isEmpty);
    });

    test('rejects chunk sizes that cannot preserve a surrogate pair', () {
      expect(
        () => splitTerminalPaste('text', maxCodeUnits: 1).toList(),
        throwsArgumentError,
      );
    });
  });
}
