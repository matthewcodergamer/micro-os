import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../core/theme.dart';
import '../models/window_state.dart';
import '../services/linux_runtime.dart';

/// Owns the window list, stacking order and focus. This is the piece that
/// turns a pile of widgets into something that behaves like a desktop.
class DesktopState extends ChangeNotifier {
  DesktopState(this.runtime);

  final LinuxRuntime runtime;

  final List<ManagedWindow> windows = <ManagedWindow>[];

  int _sequence = 0;
  int _zCounter = 0;

  ManagedWindow? get focused {
    if (windows.isEmpty) return null;
    return windows.reduce((a, b) => a.zIndex >= b.zIndex ? a : b);
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

  /// Opens [app], or raises the existing window if it is already running.
  ManagedWindow open(
    AppId app, {
    required Size screen,
    List<String>? args,
    String? title,
  }) {
    final existing = windowFor(app);
    if (existing != null) {
      existing.minimized = false;
      focus(existing.id);
      return existing;
    }

    final window = ManagedWindow(
      id: ++_sequence,
      app: app,
      title: title ?? app.title,
      rect: _initialRect(app, screen),
      zIndex: ++_zCounter,
      args: args,
    )..pinned = false;

    windows.add(window);
    notifyListeners();
    return window;
  }

  Rect _initialRect(AppId app, Size screen) {
    final usableHeight = screen.height - kStatusBarHeight - kDockReserved;
    final compact = screen.width < 720;

    final size = app.defaultSize;
    // On phones, use a floating window with a usable title bar and resize grip
    // instead of pinning every app edge-to-edge. On tablets, keep desktop sizes.
    final width = math.min(size.width, math.max(280.0, screen.width - (compact ? 24 : 48)));
    final height = math.min(size.height, math.max(240.0, usableHeight - 24));
    final offset = compact ? 0.0 : (windows.length % 6) * 26.0;

    var left = compact ? (screen.width - width) / 2 : (screen.width - width) / 2 + offset - 60;
    var top = kStatusBarHeight + 18 + offset;

    left = left
        .clamp(8.0, math.max(8.0, screen.width - width - 8))
        .toDouble();
    top = top
        .clamp(
          kStatusBarHeight + 8,
          math.max(kStatusBarHeight + 8, screen.height - kDockReserved - height),
        )
        .toDouble();

    return Rect.fromLTWH(left, top, width, height);
  }

  void focus(int id) {
    final window = _byId(id);
    if (window == null) return;
    if (window.zIndex == _zCounter) return;
    window.zIndex = ++_zCounter;
    notifyListeners();
  }

  void close(int id) {
    windows.removeWhere((w) => w.id == id);
    notifyListeners();
  }

  void minimize(int id) {
    final window = _byId(id);
    if (window == null) return;
    window.minimized = !window.minimized;
    if (!window.minimized) window.zIndex = ++_zCounter;
    notifyListeners();
  }

  void toggleMaximize(int id, Size screen) {
    final window = _byId(id);
    if (window == null) return;

    if (window.maximized) {
      window.rect = window.restoreRect ?? window.rect;
      window.restoreRect = null;
      window.maximized = false;
    } else {
      window.restoreRect = window.rect;
      window.rect = Rect.fromLTWH(
        0,
        kStatusBarHeight,
        screen.width,
        screen.height - kStatusBarHeight - kDockReserved,
      );
      window.maximized = true;
    }
    window.zIndex = ++_zCounter;
    notifyListeners();
  }

  void move(int id, Offset delta, Size screen) {
    final window = _byId(id);
    if (window == null || window.pinned || window.maximized) return;

    final next = window.rect.shift(delta);
    final maxLeft = math.max(0.0, screen.width - 120);
    final maxTop = screen.height - kDockReserved - 40;

    window.rect = Rect.fromLTWH(
      next.left.clamp(-window.rect.width + 120, maxLeft).toDouble(),
      next.top.clamp(kStatusBarHeight, maxTop).toDouble(),
      window.rect.width,
      window.rect.height,
    );
    notifyListeners();
  }

  void resize(int id, Offset delta, Size screen) {
    final window = _byId(id);
    if (window == null || window.pinned || window.maximized) return;

    const minWidth = 280.0;
    const minHeight = 200.0;
    final maxWidth = screen.width - window.rect.left;
    final maxHeight =
        screen.height - kDockReserved - window.rect.top;

    window.rect = Rect.fromLTWH(
      window.rect.left,
      window.rect.top,
      (window.rect.width + delta.dx)
          .clamp(math.min(minWidth, maxWidth), math.max(minWidth, maxWidth))
          .toDouble(),
      (window.rect.height + delta.dy)
          .clamp(math.min(minHeight, maxHeight), math.max(minHeight, maxHeight))
          .toDouble(),
    );
    notifyListeners();
  }

  /// Resize from any corner while keeping the opposite corner anchored.
  void resizeFrom(
    int id,
    Offset delta,
    Size screen, {
    required bool fromLeft,
    required bool fromTop,
  }) {
    final window = _byId(id);
    if (window == null || window.pinned || window.maximized) return;
    const minWidth = 240.0;
    const minHeight = 160.0;
    final old = window.rect;
    var left = old.left;
    var top = old.top;
    var right = old.right;
    var bottom = old.bottom;
    if (fromLeft) {
      left = (old.left + delta.dx).clamp(0.0, right - minWidth).toDouble();
    } else {
      right = (old.right + delta.dx).clamp(left + minWidth, screen.width).toDouble();
    }
    if (fromTop) {
      top = (old.top + delta.dy).clamp(kStatusBarHeight, bottom - minHeight).toDouble();
    } else {
      bottom = (old.bottom + delta.dy).clamp(top + minHeight, screen.height - kDockReserved).toDouble();
    }
    window.rect = Rect.fromLTRB(left, top, right, bottom);
    notifyListeners();
  }

  /// Called on rotation / resize so pinned windows keep filling the screen.
  void syncToScreen(Size screen) {
    final compact = screen.width < 720;
    var changed = false;
    for (final window in windows) {
      if (window.pinned) {
        window.pinned = false;
        changed = true;
      }
      final maxWidth = math.max(280.0, screen.width - 16);
      final maxHeight = math.max(240.0, screen.height - kStatusBarHeight - kDockReserved - 8);
      final width = math.min(window.rect.width, maxWidth);
      final height = math.min(window.rect.height, maxHeight);
      final left = compact ? (screen.width - width) / 2 : window.rect.left.clamp(0.0, math.max(0.0, screen.width - width)).toDouble();
      final top = window.rect.top.clamp(kStatusBarHeight, math.max(kStatusBarHeight, screen.height - kDockReserved - height)).toDouble();
      final rect = Rect.fromLTWH(left, top, width, height);
      if (rect != window.rect) {
        window.rect = rect;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  ManagedWindow? _byId(int id) {
    for (final w in windows) {
      if (w.id == id) return w;
    }
    return null;
  }
}
