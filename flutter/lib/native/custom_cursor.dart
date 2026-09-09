import 'package:flutter_custom_cursor/cursor_manager.dart'
    as custom_cursor_manager;
import 'package:flutter_custom_cursor/flutter_custom_cursor.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:image/image.dart' as img2;

import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/view_rotation.dart';
import 'package:flutter_hbb/native/common.dart';

deleteCustomCursor(String key) =>
    custom_cursor_manager.CursorManager.instance.deleteCursor(key);
resetSystemCursor() {}

/// Forces a fresh native "set cursor" call to a known-good, unrotated
/// cursor. Linux's flutter_custom_cursor backend calls `gdk_window_set_cursor()`
/// directly on the whole top-level GTK window, bypassing Flutter's own
/// per-widget cursor tracking. Once a cursor with a large, rotated hotspot
/// (see ViewRotation-based cursor rotation) has been set that way, Flutter's
/// engine believes its own "default" cursor is already active and skips
/// re-issuing the native call when the pointer leaves the remote view --
/// leaving the window's actual GDK cursor hotspot stuck at the rotated
/// value even outside the remote content area. Explicitly re-issuing the
/// native call with a plain, centered-hotspot cursor works around this.
void forceResetSystemCursor(CursorModel cursor) {
  if (!isLinux_) return;
  final cursorObj = buildCursorOfCache(cursor, 1.0, preDefaultCursor.cache);
  if (cursorObj is FlutterCustomMemoryImageCursor && cursorObj.key != null) {
    custom_cursor_manager.CursorManager.instance
        .setSystemCursor(cursorObj.key!);
  }
}

MouseCursor buildCursorOfCache(
    CursorModel cursor, double scale, CursorData? cache,
    {ViewRotation rotation = ViewRotation.none}) {
  if (cache == null) {
    return MouseCursor.defer;
  } else {
    var key = cache.updateGetKey(scale);
    if (rotation.isQuarterTurn) {
      key = '${key}_rot${rotation.quarterTurns}';
    }
    if (cursor.cachedKeys.contains(key)) {
      return FlutterCustomMemoryImageCursor(key: key);
    }
    // data should be checked here, because it may be changed after `updateGetKey()`
    var data = cache.data;
    if (data == null) {
      return MouseCursor.defer;
    }
    var width = (cache.width * cache.scale).toInt();
    var height = (cache.height * cache.scale).toInt();
    var hotX = cache.hotx;
    var hotY = cache.hoty;
    // With client-side view rotation the remote view is rotated, so the
    // local pointer glyph (a mirror of the remote cursor) must be rotated
    // by the same amount and its hotspot re-mapped, otherwise the icon is
    // drawn un-rotated and offset from where it points.
    if (rotation.isQuarterTurn) {
      final img = _decodeCursorImage(data, width, height);
      if (img != null) {
        final rotated =
            img2.copyRotate(img, angle: rotation.quarterTurns * 90);
        data = isWindows_
            ? rotated.getBytes(order: img2.ChannelOrder.bgra)
            : Uint8List.fromList(img2.encodePng(rotated));
        final hot = rotation.rotateHotspot(width.toDouble(), height.toDouble(),
            Offset(hotX, hotY));
        hotX = hot.dx;
        hotY = hot.dy;
        if (rotation == ViewRotation.rot90 ||
            rotation == ViewRotation.rot270) {
          final t = width;
          width = height;
          height = t;
        }
      }
    }
    debugPrint(
        "Register custom cursor with key $key ($hotX,$hotY)");
    // [Safety]
    // It's ok to call async registerCursor in current synchronous context,
    // because activating the cursor is also an async call and will always
    // be executed after this.
    custom_cursor_manager.CursorManager.instance
        .registerCursor(custom_cursor_manager.CursorData()
          ..name = key
          ..buffer = data
          ..width = width
          ..height = height
          ..hotX = hotX
          ..hotY = hotY);
    cursor.addKey(key);
    return FlutterCustomMemoryImageCursor(key: key);
  }
}

img2.Image? _decodeCursorImage(Uint8List data, int width, int height) {
  try {
    if (isWindows_) {
      return img2.Image.fromBytes(
          bytes: data.buffer,
          width: width,
          height: height,
          order: img2.ChannelOrder.bgra);
    }
    return img2.decodePng(data);
  } catch (e) {
    debugPrint("Failed to decode cursor image: $e");
    return null;
  }
}
