const List<String> _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

int _h12(DateTime t) => t.hour % 12 == 0 ? 12 : t.hour % 12;
String _mm(DateTime t) => t.minute.toString().padLeft(2, '0');

/// "Wed Apr 1  9:41 AM" (or "Wed 9:41 AM" when [compact]).
String menuBarDate(DateTime t, {bool compact = false}) {
  final time = '${_h12(t)}:${_mm(t)} ${t.hour >= 12 ? 'PM' : 'AM'}';
  final wd = _weekdays[t.weekday - 1];
  if (compact) return '$wd $time';
  return '$wd ${_months[t.month - 1]} ${t.day}  $time';
}

/// "Wed Apr 1" for the lock screen.
String lockDate(DateTime t) =>
    '${_weekdays[t.weekday - 1]} ${_months[t.month - 1]} ${t.day}';

/// "9:41" for the lock screen.
String lockTime(DateTime t) => '${_h12(t)}:${_mm(t)}';

/// "Nov 11, 2026"
String shortDate(DateTime t) => '${_months[t.month - 1]} ${t.day}, ${t.year}';

String humanSize(int bytes) {
  if (bytes < 1000) return '$bytes bytes';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1000.0;
  var i = 0;
  while (value >= 1000 && i < units.length - 1) {
    value /= 1000;
    i++;
  }
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[i]}';
}
