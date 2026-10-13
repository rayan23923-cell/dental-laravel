import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// Finds a QR code in a still photo (JPEG/PNG bytes) and returns its text,
/// or null when there is none. Pure Dart, so it runs on Windows where
/// `mobile_scanner` has no camera support; call it through `compute` to
/// keep the UI smooth. The photo is scaled down first, which is plenty for
/// a ticket QR held up to a webcam and much faster to scan.
String? decodeQrFromImageBytes(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final image = decoded.width > 960 ? img.copyResize(decoded, width: 960) : decoded;

  final pixels = image.convert(numChannels: 4).getBytes(order: img.ChannelOrder.abgr).buffer.asInt32List();
  final source = RGBLuminanceSource(image.width, image.height, pixels);

  for (final bitmap in [BinaryBitmap(HybridBinarizer(source)), BinaryBitmap(GlobalHistogramBinarizer(source))]) {
    try {
      return QRCodeReader().decode(bitmap, hints: DecodeHints()..put(DecodeHintType.tryHarder)).text;
    } on ReaderException {
      // Not found with this binarizer; try the next one.
    }
  }
  return null;
}
