import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';

class ScreenshotHelper {
  /// Capture the widget referenced by [key] and write a PNG to [filePath].
  static Future<void> captureToFile(GlobalKey key, String filePath) async {
    try {
      final ctx = key.currentContext;
      if (ctx == null) return;
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final pixelRatio = MediaQuery.maybeOf(ctx)?.devicePixelRatio ?? ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      final file = File(filePath);
      await file.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {}
  }
}
