import 'dart:ui';

enum OriginCorner { bottomLeft, topLeft, bottomRight, topRight }

class FieldConfig {
  final Size fieldSizeMeters; // e.g., 57.573 x 26.417 (Reefscape)
  final Rect pixelRect; // pixel rect in the image to map (TL->BR in image coords)
  final OriginCorner originCorner;
  FieldConfig({
    required this.fieldSizeMeters,
    required this.pixelRect,
    this.originCorner = OriginCorner.bottomLeft,
  });

  // meter -> pixel in image coordinates (y down), then caller maps to canvas
  Offset fieldToImagePx(Offset m) {
    final sx = pixelRect.width / fieldSizeMeters.width;
    final sy = pixelRect.height / fieldSizeMeters.height;
    switch (originCorner) {
      case OriginCorner.bottomLeft:
        return Offset(
          pixelRect.left + m.dx * sx,
          pixelRect.bottom - m.dy * sy,
        );
      case OriginCorner.topLeft:
        return Offset(pixelRect.left + m.dx * sx, pixelRect.top + m.dy * sy);
      case OriginCorner.bottomRight:
        return Offset(pixelRect.right - m.dx * sx, pixelRect.bottom - m.dy * sy);
      case OriginCorner.topRight:
        return Offset(pixelRect.right - m.dx * sx, pixelRect.top + m.dy * sy);
    }
  }

  // image pixel -> meter
  Offset imagePxToField(Offset px) {
    final sx = fieldSizeMeters.width / pixelRect.width;
    final sy = fieldSizeMeters.height / pixelRect.height;
    switch (originCorner) {
      case OriginCorner.bottomLeft:
        return Offset(
          (px.dx - pixelRect.left) * sx,
          (pixelRect.bottom - px.dy) * sy,
        );
      case OriginCorner.topLeft:
        return Offset((px.dx - pixelRect.left) * sx, (px.dy - pixelRect.top) * sy);
      case OriginCorner.bottomRight:
        return Offset(
          (pixelRect.right - px.dx) * sx,
          (pixelRect.bottom - px.dy) * sy,
        );
      case OriginCorner.topRight:
        return Offset(
          (pixelRect.right - px.dx) * sx,
          (px.dy - pixelRect.top) * sy,
        );
    }
  }
}
