import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;

/// Backport only the layout information used by the shared access guide.
/// Its contents, sizing, focus and actions remain in HostAccessControls.
Widget win7OverlayPortal({
  required OverlayPortalController controller,
  required Widget Function(
    BuildContext,
    ({Matrix4 childPaintTransform, Size childSize, Size overlaySize}),
  ) overlayChildBuilder,
  required Widget child,
}) {
  final anchorKey = GlobalKey();
  return OverlayPortal(
    controller: controller,
    overlayChildBuilder: (context) => LayoutBuilder(
      builder: (context, constraints) {
        final anchor = anchorKey.currentContext?.findRenderObject();
        final overlay = Overlay.of(context).context.findRenderObject();
        if (anchor is! RenderBox || overlay == null || !anchor.hasSize) {
          return const SizedBox.shrink();
        }
        return overlayChildBuilder(context, (
          childPaintTransform: anchor.getTransformTo(overlay),
          childSize: anchor.size,
          overlaySize: constraints.biggest,
        ));
      },
    ),
    child: KeyedSubtree(key: anchorKey, child: child),
  );
}
