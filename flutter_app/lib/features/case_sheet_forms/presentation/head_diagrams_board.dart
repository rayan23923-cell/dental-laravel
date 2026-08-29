import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Head pain-location diagrams — port of `Components/HeadDiagramsBoard.vue`,
/// itself a port of `oral_medicine.php`'s four `headDiagram{Frontal,
/// Posterior,Right,Left}` canvases
/// (`extraoral_intraoral_examination.head_diagrams`). Each is the
/// original's real reference image (same 4 JPEGs web serves from
/// `public/images/head-diagrams/`, bundled here as Flutter assets since
/// they're static, not admin-uploaded) with click-to-mark points: pick a
/// pain-quality pattern from the dropdown, tap the diagram, a symbol is
/// stamped there. Not freehand drawing — like the original, one point per
/// tap.
///
/// [value] is `{ frontal: [{x,y,type}], posterior: [...], right: [...],
/// left: [...] }`, points stored in the image's *natural* pixel space (its
/// real decoded width/height) so a chart saved at one screen size still
/// lines up when reopened at another — same reasoning the original's own
/// scaleX/scaleY conversion uses.
///
/// Symbols are redrawn pixel-for-pixel from the original's
/// `drawPainPatternForHeadDiagram()` (ported via `HeadDiagramsBoard.vue`,
/// not re-derived from the PHP): ||||| mild, wavy MMM moderate, /////
/// severe, and single letters B/D/N/P/S/T/R for
/// burning/dull/numbing/pressure/sharp/tingling/radiating.
class HeadDiagramsBoard extends StatefulWidget {
  const HeadDiagramsBoard({super.key, required this.value, required this.onChanged, this.readOnly = false});

  final Map<String, dynamic> value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool readOnly;

  @override
  State<HeadDiagramsBoard> createState() => _HeadDiagramsBoardState();
}

class _View {
  const _View(this.key, this.label, this.asset);
  final String key;
  final String label;
  final String asset;
}

const _views = [
  _View('frontal', 'Frontal', 'assets/images/head_diagrams/frontal.jpg'),
  _View('posterior', 'Posterior', 'assets/images/head_diagrams/posterior.jpg'),
  _View('right', 'Right', 'assets/images/head_diagrams/right.jpg'),
  _View('left', 'Left', 'assets/images/head_diagrams/left.jpg'),
];

const _patterns = [
  ('mild', 'Mild (|||||)'),
  ('moderate', 'Moderate (MMM)'),
  ('severe', 'Severe (/////)'),
  ('burning', 'B Burning'),
  ('dull', 'D Dull'),
  ('numbing', 'N Numbing'),
  ('pressure', 'P Pressure'),
  ('sharp', 'S Sharp'),
  ('tingling', 'T Tingling'),
  ('radiating', 'R Radiating'),
];

class _HeadDiagramsBoardState extends State<HeadDiagramsBoard> {
  final Map<String, String> _currentPattern = {for (final v in _views) v.key: 'mild'};
  final Map<String, ui.Image> _images = {};

  @override
  void initState() {
    super.initState();
    for (final v in _views) {
      _loadImage(v);
    }
  }

  Future<void> _loadImage(_View v) async {
    final data = await rootBundle.load(v.asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    if (mounted) setState(() => _images[v.key] = frame.image);
  }

  List<Map<String, dynamic>> _points(String key) =>
      ((widget.value[key] as List<dynamic>?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  void _addPoint(String key, double x, double y) {
    widget.onChanged({
      ...widget.value,
      key: [..._points(key), {'x': x, 'y': y, 'type': _currentPattern[key]}],
    });
  }

  void _clear(String key) => widget.onChanged({...widget.value, key: <Map<String, dynamic>>[]});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.75,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [for (final v in _views) _buildView(v)],
    );
  }

  Widget _buildView(_View v) {
    final image = _images[v.key];
    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          Text(v.label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Expanded(
            child: image == null
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : AspectRatio(
                    aspectRatio: image.width / image.height,
                    child: LayoutBuilder(
                      builder: (context, constraints) => GestureDetector(
                        onTapDown: widget.readOnly
                            ? null
                            : (details) {
                                final scaleX = image.width / constraints.maxWidth;
                                final scaleY = image.height / constraints.maxHeight;
                                _addPoint(
                                  v.key,
                                  details.localPosition.dx * scaleX,
                                  details.localPosition.dy * scaleY,
                                );
                              },
                        child: CustomPaint(
                          size: Size(constraints.maxWidth, constraints.maxHeight),
                          painter: _HeadDiagramPainter(image: image, points: _points(v.key)),
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<String>(
                value: _currentPattern[v.key],
                isDense: true,
                style: const TextStyle(fontSize: 10, color: Colors.black87),
                items: [for (final p in _patterns) DropdownMenuItem(value: p.$1, child: Text(p.$2))],
                onChanged: widget.readOnly ? null : (next) => setState(() => _currentPattern[v.key] = next!),
              ),
              if (!widget.readOnly)
                TextButton(
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: Size.zero),
                  onPressed: () => _clear(v.key),
                  child: const Text('مسح', style: TextStyle(fontSize: 11)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeadDiagramPainter extends CustomPainter {
  _HeadDiagramPainter({required this.image, required this.points});
  final ui.Image image;
  final List<Map<String, dynamic>> points;

  static const _letters = {
    'burning': 'B', 'dull': 'D', 'numbing': 'N', 'pressure': 'P',
    'sharp': 'S', 'tingling': 'T', 'radiating': 'R',
  };

  @override
  void paint(Canvas canvas, Size size) {
    paintImage(canvas: canvas, rect: Rect.fromLTWH(0, 0, size.width, size.height), image: image, fit: BoxFit.fill);

    // Aspect ratio is always preserved (the AspectRatio ancestor sizes
    // this canvas to image.width/image.height), so the x/y scale factors
    // the web version computes separately are always equal here — one
    // `scale` covers both, matching its `Math.min(scaleX, scaleY)`.
    final scale = size.width / image.width < 0.8 ? 0.8 : size.width / image.width;

    for (final p in points) {
      final x = (p['x'] as num).toDouble() * (size.width / image.width);
      final y = (p['y'] as num).toDouble() * (size.height / image.height);
      _drawSymbol(canvas, Offset(x, y), p['type'] as String? ?? 'mild', scale);
    }
  }

  void _drawSymbol(Canvas canvas, Offset center, String type, double scale) {
    final lineWidth = 1.2 * scale < 1.2 ? 1.2 : 1.2 * scale;
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = lineWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    canvas.save();
    canvas.translate(center.dx, center.dy);

    switch (type) {
      case 'mild':
        final spacing = 4 * scale, startX = -8 * scale, h = 20 * scale;
        for (var i = 0; i < 5; i++) {
          final xPos = startX + i * spacing;
          canvas.drawLine(Offset(xPos, -h / 2), Offset(xPos, h / 2), paint);
        }
      case 'moderate':
        final spacing = 8 * scale, startX = -8 * scale, wh = 5 * scale;
        for (var i = 0; i < 3; i++) {
          final xPos = startX + i * spacing;
          final path = Path()
            ..moveTo(xPos, 0)
            ..quadraticBezierTo(xPos + spacing / 4, -wh, xPos + spacing / 2, 0)
            ..quadraticBezierTo(xPos + (spacing * 3) / 4, wh, xPos + spacing, 0);
          canvas.drawPath(path, paint);
        }
      case 'severe':
        final spacing = 4 * scale, startX = -8 * scale, h = 20 * scale, diag = 3 * scale;
        for (var i = 0; i < 5; i++) {
          final xPos = startX + i * spacing;
          canvas.drawLine(Offset(xPos, -h / 2), Offset(xPos + diag, h / 2), paint);
        }
      default:
        final letter = _letters[type];
        if (letter != null) {
          final tp = TextPainter(
            text: TextSpan(text: letter, style: TextStyle(color: Colors.black, fontSize: 14 * scale)),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
        }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HeadDiagramPainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.points != points;
}
