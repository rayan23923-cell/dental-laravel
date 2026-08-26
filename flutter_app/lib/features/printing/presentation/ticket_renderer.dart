import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Renders [child] to a PNG by mounting it off-screen via an
/// [OverlayEntry] — the standard way to rasterize a widget that needs
/// real layout/paint (font shaping, RTL) without it ever being visible.
/// `pixelRatio: 1.0` so the widget's logical width in dp equals the
/// output image's pixel width exactly — `TicketWidget` is built at a
/// fixed 384px width to match the printer's documented max raster width.
Future<Uint8List> renderWidgetToPng(BuildContext context, Widget child) async {
  final key = GlobalKey();
  final overlay = Overlay.of(context);
  final completer = Completer<Uint8List>();
  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (_) => Positioned(
      left: -10000,
      top: 0,
      child: Material(
        color: Colors.transparent,
        child: RepaintBoundary(key: key, child: child),
      ),
    ),
  );

  overlay.insert(entry);

  // Two frames: one to build/layout, one to guarantee paint has happened
  // before capture (a single post-frame callback occasionally raced the
  // first paint during testing).
  await WidgetsBinding.instance.endOfFrame;
  await WidgetsBinding.instance.endOfFrame;

  try {
    final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    completer.complete(byteData!.buffer.asUint8List());
  } catch (e, st) {
    completer.completeError(e, st);
  } finally {
    entry.remove();
  }

  return completer.future;
}

/// Warms the image cache for any raw bytes a ticket widget will render via
/// `Image.memory` (QR, logo) — call this *before* [renderWidgetToPng].
///
/// `Image.memory` decodes asynchronously; [renderWidgetToPng] only waits
/// two frames before snapshotting, which is enough for layout/paint of
/// already-decoded content but not reliably enough for a fresh decode of a
/// ~500px PNG, especially on slower hardware. The result was a real bug
/// (confirmed live: a printed receipt with a correctly-fetched QR PNG that
/// still came out blank) — the layout box was already sized correctly
/// (`Image.memory` reserves its `width`/`height` before the pixels are
/// ready), so nothing looked wrong until paper actually came out of the
/// printer. Precaching with the *same* `Uint8List` instance the widget
/// will use means `Image.memory`'s internal `MemoryImage` (equality is by
/// list identity, not content) hits an already-decoded cache entry instead
/// of starting a fresh decode during the capture window.
Future<void> precacheTicketImages(BuildContext context, List<Uint8List?> images) async {
  for (final bytes in images) {
    if (bytes == null) continue;
    try {
      await precacheImage(MemoryImage(bytes), context);
    } catch (_) {
      // Fail-open, matching every ticket image fetch above this call —
      // a decode failure just means that image paints blank, not a print
      // failure.
    }
  }
}
