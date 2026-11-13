/// Splits clipboard text into bounded UTF-16 chunks without separating a
/// surrogate pair. The resulting strings concatenate to the exact input.
Iterable<String> splitTerminalPaste(
  String text, {
  int maxCodeUnits = 500,
}) sync* {
  if (maxCodeUnits < 2) {
    throw ArgumentError.value(maxCodeUnits, 'maxCodeUnits', 'must be at least 2');
  }

  var start = 0;
  while (start < text.length) {
    var end = (start + maxCodeUnits).clamp(0, text.length);
    if (end < text.length) {
      final previous = text.codeUnitAt(end - 1);
      final next = text.codeUnitAt(end);
      final splitsSurrogatePair =
          previous >= 0xD800 && previous <= 0xDBFF &&
          next >= 0xDC00 && next <= 0xDFFF;
      if (splitsSurrogatePair) end--;
    }
    yield text.substring(start, end);
    start = end;
  }
}
