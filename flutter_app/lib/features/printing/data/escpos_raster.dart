import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Turns a rendered ticket image into ESC/POS bytes a thermal printer
/// prints as-is (2026-10-16): the image as a raster bitmap (`GS v 0`), a
/// short feed, then a partial cut. A bitmap rather than text because the
/// printers' own fonts have no Arabic glyphs (see `PosPrinterService`).
///
/// Transparent pixels count as white; anything darker than mid-grey prints.
Uint8List escPosRaster(Uint8List pngBytes, {required int widthDots, bool cut = true}) {
  final decoded = img.decodeImage(pngBytes);
  if (decoded == null) throw const FormatException('The ticket image could not be read.');
  final image = decoded.width == widthDots ? decoded : img.copyResize(decoded, width: widthDots);

  final width = image.width;
  final height = image.height;
  final bytesPerRow = (width + 7) >> 3;
  final out = BytesBuilder(copy: false)..add(const [0x1B, 0x40]); // ESC @: reset

  // Bands keep each command small enough for printers with little buffer.
  const bandRows = 255;
  for (var top = 0; top < height; top += bandRows) {
    final rows = math.min(bandRows, height - top);
    out.add([0x1D, 0x76, 0x30, 0x00, bytesPerRow & 0xFF, bytesPerRow >> 8, rows & 0xFF, rows >> 8]);
    final band = Uint8List(bytesPerRow * rows);
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < width; x++) {
        final p = image.getPixel(x, top + y);
        if (p.aNormalized < 0.5) continue;
        final luminance = 0.299 * p.rNormalized + 0.587 * p.gNormalized + 0.114 * p.bNormalized;
        if (luminance < 0.5) band[y * bytesPerRow + (x >> 3)] |= 0x80 >> (x & 7);
      }
    }
    out.add(band);
  }

  out.add(const [0x1B, 0x64, 0x04]); // ESC d 4: feed past the cutter
  if (cut) out.add(const [0x1D, 0x56, 0x42, 0x00]); // GS V B: partial cut
  return out.toBytes();
}
