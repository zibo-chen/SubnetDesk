import 'dart:ui';

/// Local (client-side) rotation of the remote view.
///
/// The remote display is never modified. This only rotates what the local
/// client paints; input events are sent in the displayed coordinate space,
/// which for the targeted hardware-rotated panels is the peer's pointer
/// space, so the server injects them unchanged and needs no knowledge of the
/// rotation. It is meant for hardware-rotated panels whose orientation is
/// applied below the compositor (for example a tablet with a physically
/// rotated display) and therefore cannot be rotated on the server side.
enum ViewRotation {
  none,
  rot90,
  rot180,
  rot270;

  /// The [RotatedBox.quarterTurns] index of this rotation.
  int get quarterTurns => index;

  static ViewRotation fromAngle(int? angle) {
    switch (angle) {
      case 90:
        return rot90;
      case 180:
        return rot180;
      case 270:
        return rot270;
      default:
        return none;
    }
  }

  /// Whether the displayed width and height are swapped.
  bool get isQuarterTurn => this == rot90 || this == rot270;

  /// The displayed size for a base display size of [base].
  Size rotatedSize(Size base) =>
      isQuarterTurn ? Size(base.height, base.width) : base;

  /// Map a point from the base (remote) coordinate space to the displayed
  /// (virtual) coordinate space. Points are relative to their rect origins,
  /// and [base] is the base display size.
  Offset toVirtual(Offset point, Size base) {
    final w = base.width;
    final h = base.height;
    switch (this) {
      case none:
        return point;
      case rot90:
        return Offset(h - point.dy, point.dx);
      case rot180:
        return Offset(w - point.dx, h - point.dy);
      case rot270:
        return Offset(point.dy, w - point.dx);
    }
  }

  /// Map a point from the displayed (virtual) coordinate space back to the
  /// base (remote) coordinate space. The inverse of [toVirtual]; used for
  /// features where the peer draws in its own frame space, such as the
  /// whiteboard cursor of the view-only "Show my cursor" mode.
  Offset toBase(Offset point, Size base) {
    final w = base.width;
    final h = base.height;
    switch (this) {
      case none:
        return point;
      case rot90:
        return Offset(point.dy, h - point.dx);
      case rot180:
        return Offset(w - point.dx, h - point.dy);
      case rot270:
        return Offset(w - point.dy, point.dx);
    }
  }

  /// The clockwise rotation that takes this rotation to [other], as a
  /// [ViewRotation]. Used to orient content that lives in this rotation's
  /// space (for example the peer's panel-space cursor) in [other]'s space.
  ViewRotation difference(ViewRotation other) =>
      ViewRotation.values[((other.index - index) % 4 + 4) % 4];

  /// Rotate a direction vector by [quarterTurns] clockwise quarter turns.
  static Offset rotateDeltaCW(Offset delta, int quarterTurns) {
    switch (quarterTurns % 4) {
      case 1:
        return Offset(-delta.dy, delta.dx);
      case 2:
        return Offset(-delta.dx, -delta.dy);
      case 3:
        return Offset(delta.dy, -delta.dx);
      default:
        return delta;
    }
  }

  /// Rotate the hotspot of a cursor glyph drawn in a [cursorW]x[cursorH]
  /// cursor image, matching a glyph rotated by this rotation.
  Offset rotateHotspot(double cursorW, double cursorH, Offset hotspot) {
    switch (this) {
      case none:
        return hotspot;
      case rot90:
        return Offset(cursorH - hotspot.dy, hotspot.dx);
      case rot180:
        return Offset(cursorW - hotspot.dx, cursorH - hotspot.dy);
      case rot270:
        return Offset(hotspot.dy, cursorW - hotspot.dx);
    }
  }
}
