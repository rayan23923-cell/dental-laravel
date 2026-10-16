import 'dart:typed_data';

import 'package:dental_clinic_app/features/printing/data/escpos_raster.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  Uint8List png(int width, int height, void Function(img.Image) paint) {
    final image = img.Image(width: width, height: height, numChannels: 4)..clear(img.ColorRgba8(0, 0, 0, 0));
    paint(image);
    return img.encodePng(image);
  }

  test('a black left half prints as set bits, white and transparent as clear', () {
    final bytes = escPosRaster(
      png(16, 2, (i) {
        img.fillRect(i, x1: 0, y1: 0, x2: 7, y2: 1, color: img.ColorRgba8(0, 0, 0, 255));
        img.fillRect(i, x1: 8, y1: 0, x2: 11, y2: 1, color: img.ColorRgba8(255, 255, 255, 255));
      }),
      widthDots: 16,
    );

    expect(bytes.sublist(0, 2), [0x1B, 0x40]);
    expect(bytes.sublist(2, 10), [0x1D, 0x76, 0x30, 0x00, 2, 0, 2, 0]);
    expect(bytes.sublist(10, 14), [0xFF, 0x00, 0xFF, 0x00]);
    expect(bytes.sublist(14), [0x1B, 0x64, 0x04, 0x1D, 0x56, 0x42, 0x00]);
  });

  test('tall images are split into bands and scaled to the roll width', () {
    final bytes = escPosRaster(png(192, 300, (_) {}), widthDots: 384, cut: false);
    // 192x300 scales to 384x600: bands of 255, 255 and 90 rows, 48 bytes each.
    expect(bytes.length, 2 + 3 * 8 + 48 * 600 + 3);
    expect(bytes.sublist(2, 10), [0x1D, 0x76, 0x30, 0x00, 48, 0, 255, 0]);
  });
}
