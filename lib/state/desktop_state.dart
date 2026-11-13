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
    final bottom = math.max(topReserve + 160.0, screen.height - bottomReserve);
    return Rect.fromLTRB(0, topReserve, screen.width, bottom);
  }

  /// Where a maximized window sits. On phones the Dock is hidden while a
  /// window is maximized, so it runs to the bottom edge.
  Rect _maxRect(Size screen) {
    if (_compactFor(screen)) {
      return Rect.fromLTRB(
        0,
        topReserve,
        screen.width,
        screen.height,
      );
    }
    return _area(screen);
  }

  void syncToScreen(
    Size screen, {
    required double topReserve,
    required double bottomReserve,
    required double bottomInset,
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
      // Keep maximized windows glued to the usable area when the keyboard or
      // orientation changes.
      for (final w in windows) {
        if (w.maximized) {
          w.rect = _maxRect(screen);
        } else if (w.pinned) {
          w.rect = _maxRect(screen);
        }
      }
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- windows

  ManagedWindow open(
    AppId app, {
    List<String>? args,
    bool newWindow = false,
  }) {
    if (!newWindow) {
      final existing = windowFor(app);
      if (existing != null) {
        if (existing.minimized) {
          existing.minimized = false;
        }
        focus(existing.id);
        return existing;
      }
    }

    final id = ++_sequence;
    final size = app.defaultSize;
    final area = _area(_screen);
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
    final maximize = _compactFor(_screen);
    if (maximize) {
      rect = _maxRect(_screen);
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
    if (w.minimized) w.minimized = false;
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
    w.minimized = true;
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
      w.restoreRect = w.rect;
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

  void dispose() {
    windows.clear();
  }
}
