import 'package:flutter/material.dart';

/// The target-pattern surface polygons every tooth icon draws, copied
/// point-for-point (in the original's own 0–30 viewBox) from
/// `Components/ToothOdontogram.vue`'s `SURFACE_POINTS`, which itself was
/// copied from `dental_clinics2/doctor/operative.php`'s SVG.
const Map<String, List<Offset>> kSurfacePoints = {
  'top': [Offset(0, 0), Offset(30, 0), Offset(20, 10), Offset(10, 10)],
  'left': [Offset(0, 0), Offset(10, 10), Offset(10, 20), Offset(0, 30)],
  'bottom': [Offset(0, 30), Offset(10, 20), Offset(20, 20), Offset(30, 30)],
  'right': [Offset(30, 0), Offset(20, 10), Offset(20, 20), Offset(30, 30)],
  'center': [Offset(10, 10), Offset(20, 10), Offset(20, 20), Offset(10, 20)],
};

Path _scaledPath(List<Offset> points, double scale) {
  final path = Path()..moveTo(points.first.dx * scale, points.first.dy * scale);
  for (final p in points.skip(1)) {
    path.lineTo(p.dx * scale, p.dy * scale);
  }
  return path..close();
}

/// Draws one tooth's flower icon: the five surface polygons (uniformly
/// overridden by [toothLevelFill] for missing/extracted/non_vital, per
/// `kToothLevelFill`) plus the original's overlay marks — a red X for
/// extracted, an orange ring for retained_root, a black ring for crown.
class ToothFlowerPainter extends CustomPainter {
  const ToothFlowerPainter({
    required this.fillFor,
    this.toothLevelFill,
    this.opacity = 1,
    this.extracted = false,
    this.retainedRoot = false,
    this.crown = false,
    this.selectedSurface,
    this.strokeWidth = 1.5,
  });

  final Color Function(String surfaceId) fillFor;
  final Color? toothLevelFill;
  final double opacity;
  final bool extracted;
  final bool retainedRoot;
  final bool crown;
  final String? selectedSurface;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 30;
    final fillPaint = Paint()..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = Colors.black;

    canvas.saveLayer(Offset.zero & size, Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
    for (final entry in kSurfacePoints.entries) {
      final path = _scaledPath(entry.value, scale);
      fillPaint.color = toothLevelFill ?? fillFor(entry.key);
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);
      if (selectedSurface == entry.key) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth * 1.6
            ..color = const Color(0xFF6366F1),
        );
      }
    }
    canvas.restore();

    if (extracted) {
      final xPaint = Paint()
        ..color = const Color(0xFFDC3545)
        ..strokeWidth = size.width * 0.1
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(size.width * 0.1, size.height * 0.1), Offset(size.width * 0.9, size.height * 0.9), xPaint);
      canvas.drawLine(Offset(size.width * 0.9, size.height * 0.1), Offset(size.width * 0.1, size.height * 0.9), xPaint);
    }
    if (retainedRoot) {
      canvas.drawCircle(
        size.center(Offset.zero),
        size.width * 0.47,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.07
          ..color = const Color(0xFFFD7E14),
      );
    }
    if (crown) {
      canvas.drawCircle(
        size.center(Offset.zero),
        size.width * 0.47,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.07
          ..color = Colors.black,
      );
    }
  }

  /// Which surface (if any) contains [localPosition] — used by the modal's
  /// large preview so tapping a polygon jumps to that surface's status row,
  /// mirroring the original's click-to-select behaviour.
  static String? hitTestSurface(Offset localPosition, Size size) {
    final scale = size.width / 30;
    for (final entry in kSurfacePoints.entries) {
      if (_scaledPath(entry.value, scale).contains(localPosition)) return entry.key;
    }
    return null;
  }

  // Always true: `fillFor` is a closure over per-surface status colors that
  // can change between builds without any of the other fields changing —
  // closures aren't comparable, so there's no way to detect that case other
  // than always repainting. These icons are a handful of tiny polygons, so
  // the cost is negligible and only paid when the widget actually rebuilds.
  @override
  bool shouldRepaint(covariant ToothFlowerPainter oldDelegate) => true;
}
