import 'package:flutter/material.dart';

import '../../case_sheet_forms/domain/perio_chart_schema.dart';
// ignore: unused_import
import 'perio_chart_groups_field.dart';

/// FDI tooth number => shape type, left-to-right per arch — matches
/// `App\Support\PlaqueChart::UPPER_TEETH`/`LOWER_TEETH` and
/// `periodontal_plaque_chart_svg.dart`'s `kPlaqueUpperTeeth`/`kPlaqueLowerTeeth`
/// exactly, so the on-screen tile and the printed tooth draw the same shape.
const _kUpperTeeth = <int, String>{
  18: 'molar', 17: 'molar', 16: 'molar',
  15: 'premolar', 14: 'premolar',
  13: 'canine',
  12: 'incisorUpper', 11: 'incisorUpper', 21: 'incisorUpper', 22: 'incisorUpper',
  23: 'canine',
  24: 'premolar', 25: 'premolar',
  26: 'molar', 27: 'molar', 28: 'molar',
};
const _kLowerTeeth = <int, String>{
  48: 'molar', 47: 'molar', 46: 'molar',
  45: 'premolar', 44: 'premolar',
  43: 'canine',
  42: 'incisorLower', 41: 'incisorLower', 31: 'incisorLower', 32: 'incisorLower',
  33: 'canine',
  34: 'premolar', 35: 'premolar',
  36: 'molar', 37: 'molar', 38: 'molar',
};
const _kSurfaces = ['buccal', 'distal', 'lingual', 'mesial'];

/// One tooth's outline, in a 0–40 box — same source as
/// `App\Support\PlaqueChart::TOOTH_SHAPES` and
/// `periodontal_plaque_chart_svg.dart`'s `kPlaqueToothShapes`, expressed as
/// Flutter `Path` commands instead of an SVG path string since this widget
/// paints and hit-tests the shape directly rather than handing it to
/// `pw.SvgImage` (print-only).
Path _toothPath(String type) {
  final path = Path();
  switch (type) {
    case 'molar':
      path.moveTo(5, 10);
      path.quadraticBezierTo(20, 0, 35, 10);
      path.quadraticBezierTo(40, 20, 35, 35);
      path.quadraticBezierTo(20, 40, 5, 35);
      path.quadraticBezierTo(0, 20, 5, 10);
      break;
    case 'premolar':
      path.moveTo(5, 10);
      path.quadraticBezierTo(20, 2, 35, 10);
      path.quadraticBezierTo(38, 25, 30, 35);
      path.quadraticBezierTo(20, 38, 10, 35);
      path.quadraticBezierTo(2, 25, 5, 10);
      break;
    case 'canine':
      path.moveTo(5, 15);
      path.lineTo(20, 2);
      path.lineTo(35, 15);
      path.lineTo(30, 35);
      path.lineTo(10, 35);
      break;
    case 'incisorUpper':
      path.moveTo(0, 0);
      path.lineTo(40, 0);
      path.lineTo(34, 40);
      path.lineTo(6, 40);
      break;
    case 'incisorLower':
    default:
      path.moveTo(5, 2);
      path.lineTo(35, 2);
      path.lineTo(32, 38);
      path.lineTo(8, 38);
      break;
  }
  path.close();
  return path;
}

/// Which quadrant sector (buccal/distal/lingual/mesial) a tap at `local`
/// (in the tooth's 0–40 box) falls into — the box's two diagonals split it
/// into the same 4 triangles `kPlaqueSectorPoints` draws, fanning out from
/// the centre (20,20). See the sector fill order in [_ToothPainter].
String _sectorAt(Offset local) {
  final belowMainDiagonal = local.dy < local.dx; // right-ish half
  final aboveAntiDiagonal = local.dy < 40 - local.dx; // top-ish half
  if (belowMainDiagonal && aboveAntiDiagonal) return 'buccal';
  if (belowMainDiagonal && !aboveAntiDiagonal) return 'distal';
  if (!belowMainDiagonal && !aboveAntiDiagonal) return 'lingual';
  return 'mesial';
}

const _kSectorPoints = {
  'buccal': [Offset(0, 0), Offset(40, 0), Offset(20, 20)],
  'distal': [Offset(40, 0), Offset(40, 40), Offset(20, 20)],
  'lingual': [Offset(40, 40), Offset(0, 40), Offset(20, 20)],
  'mesial': [Offset(0, 40), Offset(0, 0), Offset(20, 20)],
};

/// Periodontal's "Plaque Index" per-visit dental chart — a completely
/// separate feature from [PerioChartGroupsField]'s BOP/PPD/CAL tables
/// despite living in the same `chart_data` column (see
/// `App\Support\PlaqueChart`'s own doc comment): one boolean per
/// tooth/surface ("was plaque present here"), tracked across 5 visits,
/// with a live-computed percentage.
///
/// Interactive real-tooth-shape tiles (2026-08-31, by request) — a port of
/// the original's own tap-a-curved-tooth-diagram editor
/// (`dental_clinics2/doctor/periodontal_chart.php`'s `createToothForVisit()`),
/// simplified into one direct interaction that works the same on every
/// screen size: tap a quadrant of the tooth to mark/unmark plaque there, tap
/// the small "مخلوع" chip to mark the tooth extracted (which then stops
/// accepting surface taps, mirroring `App\Support\PlaqueChart::visitData()`'s
/// own "extracted teeth never count" rule). The *printed* chart
/// (`periodontal_plaque_chart_svg.dart`, via `pw.SvgImage`) draws the same
/// outlines from the same source coordinates.
///
/// [value] is `chart_data.dentalCharts` as already-decoded JSON —
/// `{visit2: {teeth: {'11': {extracted: bool, surfaces: {...}}, ...}}, ...}`.
class PlaqueChartField extends StatelessWidget {
  const PlaqueChartField({
    super.key,
    required this.visits,
    required this.value,
    required this.onChanged,
    required this.readOnly,
  });

  final List<PlaqueVisitSchema> visits;
  final Map<String, dynamic> value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool readOnly;

  Map<String, dynamic> _teethFor(String visitKey) {
    final visit = value[visitKey] as Map<String, dynamic>?;
    final teeth = visit?['teeth'] as Map<String, dynamic>?;
    return teeth ?? const {};
  }

  Map<String, dynamic> _toothData(String visitKey, int toothId) {
    final teeth = _teethFor(visitKey);
    return (teeth['$toothId'] as Map<String, dynamic>?) ?? const {};
  }

  bool _isExtracted(Map<String, dynamic> tooth) => tooth['extracted'] == true;

  bool _isMarked(Map<String, dynamic> tooth, String surface) {
    final surfaces = tooth['surfaces'] as Map<String, dynamic>?;
    return surfaces?[surface] == true;
  }

  void _setTooth(String visitKey, int toothId, Map<String, dynamic> toothData) {
    final teeth = Map<String, dynamic>.from(_teethFor(visitKey));
    teeth['$toothId'] = toothData;
    final next = Map<String, dynamic>.from(value);
    next[visitKey] = {'teeth': teeth};
    onChanged(next);
  }

  void _toggleExtracted(String visitKey, int toothId) {
    final tooth = Map<String, dynamic>.from(_toothData(visitKey, toothId));
    tooth['extracted'] = !_isExtracted(tooth);
    _setTooth(visitKey, toothId, tooth);
  }

  void _toggleSurface(String visitKey, int toothId, String surface) {
    final tooth = Map<String, dynamic>.from(_toothData(visitKey, toothId));
    final surfaces = Map<String, dynamic>.from((tooth['surfaces'] as Map<String, dynamic>?) ?? const {});
    surfaces[surface] = !_isMarked(tooth, surface);
    tooth['surfaces'] = surfaces;
    _setTooth(visitKey, toothId, tooth);
  }

  /// Mirrors `App\Support\PlaqueChart::visitData()`'s own stats exactly —
  /// an extracted tooth's surfaces never count toward the total.
  (int marked, int total) _stats(String visitKey) {
    var marked = 0;
    var total = 0;
    for (final toothId in [..._kUpperTeeth.keys, ..._kLowerTeeth.keys]) {
      final tooth = _toothData(visitKey, toothId);
      if (_isExtracted(tooth)) continue;
      total += 4;
      for (final s in _kSurfaces) {
        if (_isMarked(tooth, s)) marked++;
      }
    }
    return (marked, total);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final visit in visits) _VisitCard(field: this, visit: visit),
      ],
    );
  }
}

class _VisitCard extends StatelessWidget {
  const _VisitCard({required this.field, required this.visit});
  final PlaqueChartField field;
  final PlaqueVisitSchema visit;

  @override
  Widget build(BuildContext context) {
    final (marked, total) = field._stats(visit.key);
    final index = total > 0 ? (marked / total * 100).toStringAsFixed(1) : '0.0';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ExpansionTile(
        title: Text(visit.label, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text('Plaque Index: $index% ($marked / $total)'),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        children: [
          const Align(
            alignment: Alignment.centerRight,
            child: Text('اضغط على أي جزء من السن لتحديد السطح، واضغط "مخلوع" لتحديد سن مخلوع.', style: TextStyle(fontSize: 11, color: Colors.black54)),
          ),
          const SizedBox(height: 4),
          const Align(alignment: Alignment.centerRight, child: Text('الفك العلوي — Upper Arch')),
          _ToothArchRow(field: field, visitKey: visit.key, teeth: _kUpperTeeth),
          const Divider(),
          const Align(alignment: Alignment.centerRight, child: Text('الفك السفلي — Lower Arch')),
          _ToothArchRow(field: field, visitKey: visit.key, teeth: _kLowerTeeth),
        ],
      ),
    );
  }
}

class _ToothArchRow extends StatelessWidget {
  const _ToothArchRow({required this.field, required this.visitKey, required this.teeth});
  final PlaqueChartField field;
  final String visitKey;
  final Map<int, String> teeth;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final entry in teeth.entries) _ToothTile(field: field, visitKey: visitKey, toothId: entry.key, type: entry.value),
        ],
      ),
    );
  }
}

class _ToothTile extends StatelessWidget {
  const _ToothTile({required this.field, required this.visitKey, required this.toothId, required this.type});
  final PlaqueChartField field;
  final String visitKey;
  final int toothId;
  final String type;

  @override
  Widget build(BuildContext context) {
    final tooth = field._toothData(visitKey, toothId);
    final extracted = field._isExtracted(tooth);
    const tileSize = 38.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Column(
        children: [
          GestureDetector(
            onTapDown: (field.readOnly || extracted)
                ? null
                : (details) {
                    final scale = tileSize / 40;
                    final local = details.localPosition / scale;
                    field._toggleSurface(visitKey, toothId, _sectorAt(local));
                  },
            child: Opacity(
              opacity: extracted ? 0.4 : 1,
              child: CustomPaint(
                size: const Size(tileSize, tileSize),
                painter: _ToothPainter(type: type, tooth: tooth, isMarked: field._isMarked, extracted: extracted),
              ),
            ),
          ),
          Text('$toothId', style: const TextStyle(fontSize: 10)),
          GestureDetector(
            onTap: field.readOnly ? null : () => field._toggleExtracted(visitKey, toothId),
            child: Container(
              margin: const EdgeInsets.only(top: 1),
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: extracted ? Colors.red.shade100 : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('مخلوع', style: TextStyle(fontSize: 8, color: extracted ? Colors.red.shade700 : Colors.grey)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToothPainter extends CustomPainter {
  const _ToothPainter({required this.type, required this.tooth, required this.isMarked, required this.extracted});
  final String type;
  final Map<String, dynamic> tooth;
  final bool Function(Map<String, dynamic>, String) isMarked;
  final bool extracted;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 40;
    canvas.save();
    canvas.scale(scale);

    final path = _toothPath(type);

    canvas.save();
    canvas.clipPath(path);
    for (final surface in _kSurfaces) {
      final marked = !extracted && isMarked(tooth, surface);
      final paint = Paint()
        ..color = marked ? const Color(0xFF4CAF50).withValues(alpha: 0.7) : Colors.white
        ..style = PaintingStyle.fill;
      final points = _kSectorPoints[surface]!;
      final sectorPath = Path()
        ..moveTo(points[0].dx, points[0].dy)
        ..lineTo(points[1].dx, points[1].dy)
        ..lineTo(points[2].dx, points[2].dy)
        ..close();
      canvas.drawPath(sectorPath, paint);
    }
    canvas.restore();

    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF333333)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / scale,
    );

    if (extracted) {
      final xPaint = Paint()
        ..color = const Color(0xFFDC2626)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 / scale
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(const Offset(0, 0), const Offset(40, 40), xPaint);
      canvas.drawLine(const Offset(40, 0), const Offset(0, 40), xPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ToothPainter oldDelegate) =>
      oldDelegate.tooth != tooth || oldDelegate.extracted != extracted || oldDelegate.type != type;
}
