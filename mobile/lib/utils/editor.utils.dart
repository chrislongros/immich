import 'dart:math';

import 'package:crop_image/crop_image.dart';
import 'package:flutter/widgets.dart';
import 'package:openapi/api.dart';

Rect convertCropParametersToRect(CropParameters parameters, int originalWidth, int originalHeight) {
  return Rect.fromLTWH(
    parameters.x.toDouble() / originalWidth,
    parameters.y.toDouble() / originalHeight,
    parameters.width.toDouble() / originalWidth,
    parameters.height.toDouble() / originalHeight,
  );
}

CropParameters convertRectToCropParameters(Rect rect, int originalWidth, int originalHeight) {
  final x = (rect.left * originalWidth).round();
  final y = (rect.top * originalHeight).round();
  final width = (rect.width * originalWidth).round();
  final height = (rect.height * originalHeight).round();

  return CropParameters(
    x: max(x, 0).clamp(0, originalWidth),
    y: max(y, 0).clamp(0, originalHeight),
    width: max(width, 0).clamp(0, originalWidth - x),
    height: max(height, 0).clamp(0, originalHeight - y),
  );
}

Rect convertCropRectToRotated(Rect cropRect, CropRotation rotation) {
  return switch (rotation) {
    CropRotation.up => cropRect,
    CropRotation.right => Rect.fromLTWH(1 - cropRect.bottom, cropRect.left, cropRect.height, cropRect.width),
    CropRotation.down => Rect.fromLTWH(1 - cropRect.right, 1 - cropRect.bottom, cropRect.width, cropRect.height),
    CropRotation.left => Rect.fromLTWH(cropRect.top, 1 - cropRect.right, cropRect.height, cropRect.width),
  };
}

Rect convertCropRectFromRotated(Rect cropRect, CropRotation rotation) {
  return switch (rotation) {
    CropRotation.up => cropRect,
    CropRotation.right => Rect.fromLTWH(cropRect.top, 1 - cropRect.right, cropRect.height, cropRect.width),
    CropRotation.down => Rect.fromLTWH(1 - cropRect.right, 1 - cropRect.bottom, cropRect.width, cropRect.height),
    CropRotation.left => Rect.fromLTWH(1 - cropRect.bottom, cropRect.left, cropRect.height, cropRect.width),
  };
}
