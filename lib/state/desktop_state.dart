import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../core/theme.dart';
import '../models/window_state.dart';
import '../services/linux_runtime.dart';

double _clampD(double v, double lo, double hi) {
  if (hi < lo) return lo;
  return v < lo ? lo : (v > hi ? hi : v);
}

/// Owns the window list, stacking order, focus and the lock state. This is
/// the piece that turns a pile of widgets into something that behaves like a
/// desktop.
///
/// Geometry is expressed in the coordinate space of the interactive layer
/// (the screen minus left/right cutout insets and minus the on-screen
/// keyboard). [topReserve] is the menu bar (plus any top cutout) and
/// [bottomReserve] is the Dock.
///
/// Phone-first behaviour (kept from the original): below
/// [kCompactBreakpoint] apps open maximized as immersive workspaces and the
/// green traffic light restores the floating desktop window.
class DesktopState extends ChangeNotifier {
  DesktopState(this.runtime);

  final LinuxRuntime runtime;

  final List<ManagedWindow> windows = <ManagedWindow>[];

  int _sequence = 0;
  int _zCounter = 0;

  /// The shell always starts at the login screen.
  bool locked = true;

  double topReserve = kMenuBarHeight;
  double bottomReserve = kDockReserved;
  double bottomInset = 0;
  Size _screen = Size.zero;

  Size get screen => _screen;
  bool get isCompact => _screen.width > 0 && _screen.width < kCompactBreakpoint;

  ManagedWindow? get focused {
    ManagedWindow? best;
    for (final w in windows) {
      if (w.minimized) continue;
      if (best == null || w.zIndex > best.zIndex) best = w;
    }
    return best;
  }

  List<ManagedWindow> get ordered {
    final list = [...windows]..sort((a, b) => a.zIndex.compareTo(b.zIndex));
    return list;
  }

  bool isRunning(AppId app) => windows.any((w) => w.app == app);

  ManagedWindow? windowFor(AppId app) {
    for (final w in windows) {
      if (w.app == app) return w;
    }
    return null;
  }

  void lock() {
    if (locked) return;
    locked = true;
    notifyListeners();
  }

  void unlock() {
    if (!locked) return;
    locked = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------- geometry

  bool _compactFor(Size s) => s.width < kCompactBreakpoint;

  /// Floating-window area: below the menu bar, above the Dock.
  Rect _area(Size screen) {
    final bottom = math.max(
      topReserve + 160.0,
      screen.height - bottomReserve - bottomInset,
    );
    return Rect.fromLTRB(0, topReserve, screen.width, bottom);
  }

  /// Where a minimized window animates while remaining mounted. Keeping its
  /// child alive preserves browser/WebView and terminal sessions across restore.
  Rect _minimizedRect(Size screen, Rect saved) => Rect.fromLTWH(
        saved.left,
        screen.height + 40,
        saved.width,
        saved.height,
      );

  /// Where a maximized window sits. On phones the Dock is hidden while a
  /// window is maximized, so it runs to the bottom edge.
  Rect _maxRect(Size screen) {
    if (_compactFor(screen)) {
      return Rect.fromLTRB(
        0,
        topReserve,
        screen.width,
        math.max(topReserve + 160.0, screen.height - bottomInset),
      );
    }
    return _area(screen);
  }

  void syncToScreen(
    Size screen, {
    double topReserve = kMenuBarHeight,
    double bottomReserve = kDockReserved,
    double bottomInset = 0,
  }) {
    final changed = _screen != screen ||
        this.topReserve != topReserve ||
        this.bottomReserve != bottomReserve ||
        this.bottomInset != bottomInset;
    _screen = screen;
    this.topReserve = topReserve;
    this.bottomReserve = bottomReserve;
    this.bottomInset = bottomInset;
    if (changed) {
      // Keep every window inside the usable area when the keyboard,
      // orientation or Dock changes. Maximized windows are glued to it.
      for (final w in windows) {
        if (w.minimized) {
          final saved = w.minimizedRestoreRect ?? w.rect;
          final width = math.min(saved.width, _area(screen).width);
          final height = math.min(saved.height, _area(screen).height);
          final area = _area(screen);
          final left = _clampD(saved.left, area.left, area.right - width);
          final top = _clampD(saved.top, area.top, area.bottom - height);
          w.minimizedRestoreRect = Rect.fromLTWH(left, top, width, height);
          w.rect = _minimizedRect(screen, w.minimizedRestoreRect!);
        } else if (w.maximized || w.pinned) {
          w.rect = _maxRect(screen);
        } else {
          final area = _area(screen);
          final width = math.min(w.rect.width, area.width);
          final height = math.min(w.rect.height, area.height);
          final left = _clampD(w.rect.left, area.left, area.right - width);
          final top = _clampD(w.rect.top, area.top, area.bottom - height);
          w.rect = Rect.fromLTWH(left, top, width, height);
        }
      }
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- windows

  ManagedWindow open(
    AppId app, {
    Size? screen,
    List<String>? args,
    bool newWindow = false,
  }) {
    // Keep the legacy screen argument used by the desktop widgets while
    // allowing callers that rely on syncToScreen() to omit it.
    final rawScreen = screen ?? _screen;
    // On the first frames _screen can still be Size.zero. Never build a window
    // with a zero/negative rect: it is invisible and looks exactly like the
    // "blank white window" bug users report.
    final layoutScreen = rawScreen.isEmpty ? const Size(1080, 1920) : rawScreen;
    if (!newWindow) {
      final existing = windowFor(app);
      if (existing != null) {
        focus(existing.id);
        return existing;
      }
    }

    final id = ++_sequence;
    final size = app.defaultSize;
    final area = _area(layoutScreen);
    final origin = Offset(
      area.left + (area.width - size.width) / 2 + (id % 5) * 24,
      area.top + (area.height - size.height) / 2 + (id % 5) * 24,
    );
    var rect = Rect.fromLTWH(
      origin.dx,
      origin.dy,
      size.width,
      size.height,
    );

    // Phone portrait: open maximized so the app owns the whole workspace.
    final maximize = _compactFor(layoutScreen);
    if (maximize) {
      rect = _maxRect(layoutScreen);
    }

    // Defensive clamp so a window can never be born with no visible area.
    final minWidth = math.min(320.0, layoutScreen.width);
    final minHeight = math.min(200.0, layoutScreen.height);
    if (rect.width < minWidth || rect.height < minHeight) {
      rect = Rect.fromLTWH(
        rect.left,
        rect.top,
        math.max(minWidth, rect.width),
        math.max(minHeight, rect.height),
      );
    }

    final w = ManagedWindow(
      id: id,
      app: app,
      title: app.title,
      rect: rect,
      zIndex: ++_zCounter,
      args: args,
    );
    if (maximize) {
      w.maximized = true;
      w.pinned = true;
    }
    windows.add(w);
    notifyListeners();
    return w;
  }

  void focus(int id) {
    final w = windows.cast<ManagedWindow?>().firstWhere(
          (x) => x!.id == id,
          orElse: () => null,
        );
    if (w == null) return;
    if (w.minimized) {
      w.minimized = false;
      if (w.minimizedRestoreRect != null) w.rect = w.minimizedRestoreRect!;
      w.minimizedRestoreRect = null;
    }
    w.zIndex = ++_zCounter;
    notifyListeners();
  }

  void close(int id) {
    windows.removeWhere((w) => w.id == id);
    notifyListeners();
  }

  void minimize(int id) {
    final w = windows.cast<ManagedWindow?>().firstWhere(
          (x) => x!.id == id,
          orElse: () => null,
        );
    if (w == null) return;
    if (w.minimized) return;
    w.minimizedRestoreRect = w.rect;
    w.minimized = true;
    w.rect = _minimizedRect(_screen.isEmpty ? const Size(1080, 1920) : _screen, w.minimizedRestoreRect!);
    notifyListeners();
  }

  void setTitle(int id, String title) {
    final w = windows.cast<ManagedWindow?>().firstWhere(
          (x) => x!.id == id,
          orElse: () => null,
        );
    if (w == null) return;
    if (w.title == title) return;
    w.title = title;
    notifyListeners();
  }

  void toggleMaximize(int id, Size screen) {
    final w = windows.cast<ManagedWindow?>().firstWhere(
          (x) => x!.id == id,
          orElse: () => null,
        );
    if (w == null) return;
    if (w.maximized) {
      w.maximized = false;
      w.pinned = false;
      w.rect = w.restoreRect ?? appDefaultRect(w.app, screen);
      w.restoreRect = null;
    } else {
      w.restoreRect ??= w.rect;
      w.maximized = true;
      w.pinned = _compactFor(screen);
      w.rect = _maxRect(screen);
    }
    focus(id);
  }

  Rect appDefaultRect(AppId app, Size screen) {
    final size = app.defaultSize;
    final area = _area(screen);
    return Rect.fromLTWH(
      area.left + (area.width - size.width) / 2,
      area.top + (area.height - size.height) / 2,
      size.width,
      size.height,
    );
  }

  void snapToHalf(int id, Size screen, {required bool left}) {
    final w = windows.cast<ManagedWindow?>().firstWhere((x) => x!.id == id, orElse: () => null);
    if (w == null) return;
    final area = _area(screen);
    w.restoreRect ??= w.rect;
    w.maximized = false;
    w.pinned = false;
    final half = area.width / 2;
    w.rect = Rect.fromLTWH(left ? area.left : area.left + half, area.top, half, area.height);
    focus(id);
  }

  void centerWindow(int id, Size screen) {
    final w = windows.cast<ManagedWindow?>().firstWhere((x) => x!.id == id, orElse: () => null);
    if (w == null) return;
    final area = _area(screen);
    final target = w.restoreRect ?? appDefaultRect(w.app, screen);
    final width = math.min(target.width, area.width);
    final height = math.min(target.height, area.height);
    w.rect = Rect.fromLTWH(
      _clampD(target.left, area.left, area.right - width),
      _clampD(target.top, area.top, area.bottom - height),
      width,
      height,
    );
    w.restoreRect = null;
    w.maximized = false;
    w.pinned = false;
    focus(id);
  }

  void move(int id, Offset delta, Size screen) {
    final w = windows.cast<ManagedWindow?>().firstWhere(
          (x) => x!.id == id,
          orElse: () => null,
        );
    if (w == null || w.maximized) return;
    final area = _area(screen);
    var left = w.rect.left + delta.dx;
    var top = w.rect.top + delta.dy;
    // Keep a little of the title bar visible.
    left = _clampD(left, area.left - w.rect.width + 80, area.right - 80);
    top = _clampD(top, area.top, area.bottom - 40);
    w.rect = Rect.fromLTWH(left, top, w.rect.width, w.rect.height);
    notifyListeners();
  }

  void resizeEdges(
    int id,
    Size screen, {
    double? left,
    double? top,
    double? right,
    double? bottom,
  }) {
    final w = windows.cast<ManagedWindow?>().firstWhere(
          (x) => x!.id == id,
          orElse: () => null,
        );
    if (w == null || w.maximized) return;
    final area = _area(screen);
    var l = w.rect.left;
    var t = w.rect.top;
    var r = w.rect.right;
    var b = w.rect.bottom;
    if (left != null) l = left;
    if (top != null) t = top;
    if (right != null) r = right;
    if (bottom != null) b = bottom;
    // Minimum size.
    if (r - l < 280) {
      if (left != null) l = r - 280;
      else r = l + 280;
    }
    if (b - t < 180) {
      if (top != null) t = b - 180;
      else b = t + 180;
    }
    // Keep inside the floating area (roughly).
    l = _clampD(l, area.left - 40, area.right - 80);
    t = _clampD(t, area.top, area.bottom - 40);
    r = _clampD(r, l + 280, area.right + 40);
    b = _clampD(b, t + 180, area.bottom + 40);
    w.rect = Rect.fromLTRB(l, t, r, b);
    notifyListeners();
  }

  @override
  void dispose() {
    windows.clear();
    super.dispose();
  }
}
