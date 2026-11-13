/// Input validation and safe command helpers for the native Linux browser.
class BrowserNavigation {
  const BrowserNavigation._();

  static String normalizeAddress(String input) {
    final value = input.trim();
    if (value.isEmpty) {
      throw ArgumentError.value(input, 'input', 'Enter a website address');
    }

    final candidate = value.startsWith('about:')
        ? value
        : (value.contains('://') ? value : 'https://$value');
    final uri = Uri.tryParse(candidate);
    if (uri == null ||
        !const <String>['http', 'https', 'about'].contains(uri.scheme)) {
      throw ArgumentError.value(
        input,
        'input',
        'Only HTTP, HTTPS, and about: URLs are supported',
      );
    }
    if ((uri.scheme == 'http' || uri.scheme == 'https') &&
        (uri.host.isEmpty || uri.userInfo.isNotEmpty)) {
      throw ArgumentError.value(
        input,
        'input',
        'Enter a valid website address without credentials',
      );
    }
    return uri.toString();
  }

  /// Quotes one POSIX shell argument without allowing expansion or injection.
  static String shellQuote(String value) =>
      "'${value.replaceAll("'", r"'\\''")}'";

  static const Map<String, String> _shortcuts = <String, String>{
    'back': 'alt+Left',
    'forward': 'alt+Right',
    'reload': 'ctrl+r',
    'new-tab': 'ctrl+t',
    'close-tab': 'ctrl+w',
    'new-window': 'ctrl+n',
    'focus-address': 'ctrl+l',
    'home': 'alt+Home',
    'fullscreen': 'F11',
    'zoom-in': 'ctrl+plus',
    'zoom-out': 'ctrl+minus',
    'zoom-reset': 'ctrl+0',
  };

  static const Set<String> _windowActions = <String>{
    'window-minimize',
    'window-maximize',
    'window-restore',
    'window-close',
  };

  static bool isSupportedAction(String action) =>
      _shortcuts.containsKey(action) || _windowActions.contains(action);

  static String? shortcutFor(String action) => _shortcuts[action];
}
