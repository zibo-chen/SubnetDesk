import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'package:flutter_hbb/common.dart';

Future<ui.Image?> decodeImageFromPixels(
  Uint8List pixels,
  int width,
  int height,
  ui.PixelFormat format, {
  int? rowBytes,
  int? targetWidth,
  int? targetHeight,
  bool allowUpscaling = true,
}) async {
  if (targetWidth != null) {
    assert(allowUpscaling || targetWidth <= width);
    if (!(allowUpscaling || targetWidth <= width)) {
      print("not allow upscaling but targetWidth > width");
      return null;
    }
  }
  if (targetHeight != null) {
    assert(allowUpscaling || targetHeight <= height);
    if (!(allowUpscaling || targetHeight <= height)) {
      print("not allow upscaling but targetHeight > height");
      return null;
    }
  }

  final ui.ImmutableBuffer buffer;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
  } catch (e) {
    return null;
  }

  final ui.ImageDescriptor descriptor;
  try {
    descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      rowBytes: rowBytes,
      pixelFormat: format,
    );
    if (!allowUpscaling) {
      if (targetWidth != null && targetWidth > descriptor.width) {
        targetWidth = descriptor.width;
      }
      if (targetHeight != null && targetHeight > descriptor.height) {
        targetHeight = descriptor.height;
      }
    }
  } catch (e) {
    print("ImageDescriptor.raw failed: $e");
    buffer.dispose();
    return null;
  }

  final ui.Codec codec;
  try {
    codec = await descriptor.instantiateCodec(
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
  } catch (e) {
    print("instantiateCodec failed: $e");
    buffer.dispose();
    descriptor.dispose();
    return null;
  }

  final ui.FrameInfo frameInfo;
  try {
    frameInfo = await codec.getNextFrame();
  } catch (e) {
    print("getNextFrame failed: $e");
    codec.dispose();
    buffer.dispose();
    descriptor.dispose();
    return null;
  }

  codec.dispose();
  buffer.dispose();
  descriptor.dispose();
  return frameInfo.image;
}

class ImagePainter extends CustomPainter {
  ImagePainter({
    required this.image,
    required this.x,
    required this.y,
    required this.scale,
    this.quarterTurns = 0,
    this.virtualSize,
  });

  ui.Image? image;
  double x;
  double y;
  double scale;

  /// Number of clockwise quarter turns (0-3) to rotate the image by around
  /// its center. [virtualSize] is the displayed (rotated) size of the image,
  /// used to keep the rotated image centered on its unrotated box.
  int quarterTurns;
  Size? virtualSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (image == null) return;
    if (x.isNaN || y.isNaN) return;
    canvas.scale(scale, scale);
    // https://github.com/flutter/flutter/issues/76187#issuecomment-784628161
    // https://api.flutter-io.cn/flutter/dart-ui/FilterQuality.html
    var paint = Paint();
    if ((scale - 1.0).abs() > 0.001) {
      paint.filterQuality = FilterQuality.medium;
      if (scale > 10.00000) {
        paint.filterQuality = FilterQuality.high;
      }
    }
    // It's strange that if (scale < 0.5 && paint.filterQuality == FilterQuality.medium)
    // The canvas.drawImage will not work on web
    if (isWeb) {
      paint.filterQuality = FilterQuality.high;
    }
    if (quarterTurns % 4 == 0) {
      canvas.drawImage(
          image!, Offset(x.toInt().toDouble(), y.toInt().toDouble()), paint);
      return;
    }
    final w = image!.width.toDouble();
    final h = image!.height.toDouble();
    var dx = x;
    var dy = y;
    final vs = virtualSize;
    if (vs != null) {
      // Shift so the rotated image stays centered on the displayed box.
      dx += (vs.width - w) / 2;
      dy += (vs.height - h) / 2;
    }
    canvas.save();
    canvas.translate(dx + w / 2, dy + h / 2);
    canvas.rotate(math.pi / 2 * quarterTurns);
    canvas.drawImage(image!, Offset(-w / 2, -h / 2), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return oldDelegate != this;
  }
}
