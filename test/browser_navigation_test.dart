import 'package:flutter_test/flutter_test.dart';
import 'package:micro_os/core/browser_navigation.dart';

void main() {
  group('BrowserNavigation.normalizeAddress', () {
    test('adds HTTPS to a bare host', () {
      expect(
        BrowserNavigation.normalizeAddress('example.com/path'),
        'https://example.com/path',
      );
    });

    test('preserves an explicit HTTP URL', () {
      expect(
        BrowserNavigation.normalizeAddress('http://example.com'),
        'http://example.com',
      );
    });

    test('allows the browser about page', () {
      expect(BrowserNavigation.normalizeAddress('about:blank'), 'about:blank');
    });

    test('rejects script and local-file schemes', () {
      expect(
        () => BrowserNavigation.normalizeAddress('javascript:alert(1)'),
        throwsArgumentError,
      );
      expect(
        () => BrowserNavigation.normalizeAddress('file:///etc/passwd'),
        throwsArgumentError,
      );
    });

    test('rejects embedded credentials', () {
      expect(
        () => BrowserNavigation.normalizeAddress('https://user:pass@example.com'),
        throwsArgumentError,
      );
    });
  });

  test('shell quoting protects metacharacters and apostrophes', () {
    expect(
      BrowserNavigation.shellQuote(r"https://example.com/?q=$(touch /tmp/pwned)&v=it's"),
      "'https://example.com/?q=$(touch /tmp/pwned)&v=it'\\''s'",
    );
  });

  test('only exposes known browser shortcuts', () {
    expect(BrowserNavigation.shortcutFor('back'), 'alt+Left');
    expect(BrowserNavigation.shortcutFor('forward'), 'alt+Right');
    expect(BrowserNavigation.shortcutFor('reload'), 'ctrl+r');
    expect(BrowserNavigation.shortcutFor('new-tab'), 'ctrl+t');
    expect(BrowserNavigation.shortcutFor('home'), 'alt+Home');
    expect(BrowserNavigation.shortcutFor('bookmarks'), 'ctrl+shift+b');
    expect(BrowserNavigation.shortcutFor('evil; touch /tmp/pwned'), isNull);
  });
}
