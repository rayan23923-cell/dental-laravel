import 'dart:typed_data';

import 'package:dental_clinic_app/core/platform/qr_image_decoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

Uint8List _photoWithQr(String text) {
  final matrix = Encoder.encode(text, ErrorCorrectionLevel.m).matrix!;
  const scale = 8;
  // A grey "desk" background bigger than the downscale width, QR off-centre.
  final photo = img.Image(width: 1280, height: 720)..clear(img.ColorRgb8(180, 180, 175));
  img.fillRect(photo, x1: 380, y1: 150, x2: 380 + (matrix.width + 8) * scale, y2: 150 + (matrix.height + 8) * scale, color: img.ColorRgb8(255, 255, 255));
  for (var x = 0; x < matrix.width; x++) {
    for (var y = 0; y < matrix.height; y++) {
      if (matrix.get(x, y) == 1) {
        final px = 380 + (x + 4) * scale, py = 150 + (y + 4) * scale;
        img.fillRect(photo, x1: px, y1: py, x2: px + scale - 1, y2: py + scale - 1, color: img.ColorRgb8(0, 0, 0));
      }
    }
  }
  return Uint8List.fromList(img.encodeJpg(photo, quality: 85));
}

void main() {
  test('reads the ticket QR from a webcam-sized JPEG', () {
    const payload = '{"type":"patient_registration","id":61}';
    expect(decodeQrFromImageBytes(_photoWithQr(payload)), payload);
  });

  test('returns null when there is no QR', () {
    final blank = img.Image(width: 640, height: 480)..clear(img.ColorRgb8(200, 200, 200));
    expect(decodeQrFromImageBytes(Uint8List.fromList(img.encodeJpg(blank))), isNull);
  });
}
