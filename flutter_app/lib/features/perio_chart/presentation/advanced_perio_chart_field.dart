import 'package:flutter/material.dart';

/// FDI tooth number => shape type — same source as `PlaqueChartField`'s own
/// maps (`App\Support\PlaqueChart::UPPER_TEETH`/`LOWER_TEETH`), duplicated
/// here rather than imported since that file's maps are private — the same
/// tradeoff already made between the web/Flutter/PHP copies of this data
/// throughout the Plaque Index feature.
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

const double _cellSize = 22;
// Spans the same width as a 3-site metric row's tooth column (3 x
// _cellSize) so every row's tooth columns line up vertically, single-value
// rows included.
const double _singleCellWidth = _cellSize * 3;

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

class _ArchRowPainter extends CustomPainter {
  const _ArchRowPainter(this.teeth);
  final Map<int, String> teeth;

  @override
  void paint(Canvas canvas, Size size) {
    final n = teeth.length;
    final toothWidth = size.width / n;
    final scale = toothWidth / 40;

    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      Paint()
        ..color = const Color(0xFFDC2626)
        ..strokeWidth = 1,
    );

    var i = 0;
    for (final type in teeth.values) {
      canvas.save();
      canvas.translate(i * toothWidth, 3 * scale);
      canvas.scale(scale);
      canvas.drawPath(
        _toothPath(type),
        Paint()
          ..color = const Color(0xFFF4F4F5)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        _toothPath(type),
        Paint()
          ..color = const Color(0xFF9CA3AF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 / scale,
      );
      canvas.restore();
      i++;
    }
  }

  @override
  bool shouldRepaint(covariant _ArchRowPainter oldDelegate) => false;
}

/// "Advanced Periodontal Chart" (2026-08-31, by request) — Flutter port of
/// `resources/js/Components/AdvancedPerioChart.vue`; see that file's own
/// doc comment for the full design rationale (functional parity with
/// periodontalchart-online.com's own charting tool, original tooth-shape
/// artwork reused from the Plaque Index feature rather than that site's
/// own illustrations, the "192 sites" denominator for BOP%/Plaque Index%).
///
/// [value] is `chart_data.advancedChart` as already-decoded JSON:
///   `{teeth: {'18': {mobility, implant, furcation,
///       buccal: {bop: [b,b,b], plaque: [b,b,b], gm: [n,n,n], pd: [n,n,n], al: [n,n,n]},
///       lingual: {...same shape...}}, ...}}`
class AdvancedPerioChartField extends StatelessWidget {
  const AdvancedPerioChartField({super.key, required this.value, required this.onChanged, required this.readOnly});

  final Map<String, dynamic> value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool readOnly;

  Map<String, dynamic> get _teeth => (value['teeth'] as Map<String, dynamic>?) ?? const {};

  Map<String, dynamic> _toothData(int tooth) => (_teeth['$tooth'] as Map<String, dynamic>?) ?? const {};

  void _setTooth(int tooth, Map<String, dynamic> data) {
    final teeth = Map<String, dynamic>.from(_teeth);
    teeth['$tooth'] = data;
    onChanged({'teeth': teeth});
  }

  dynamic _getSingle(int tooth, String key) => _toothData(tooth)[key] ?? (key == 'implant' ? false : '');

  void _setSingle(int tooth, String key, dynamic v) {
    if (readOnly) return;
    _setTooth(tooth, {..._toothData(tooth), key: v});
  }

  dynamic _getSite(int tooth, String zone, String metric, int pos) {
    final z = _toothData(tooth)[zone] as Map<String, dynamic>?;
    final arr = z?[metric] as List<dynamic>?;
    if (arr != null && pos < arr.length) return arr[pos];
    return metric == 'bop' || metric == 'plaque' ? false : '';
  }

  void _setSite(int tooth, String zone, String metric, int pos, dynamic v) {
    if (readOnly) return;
    final t = Map<String, dynamic>.from(_toothData(tooth));
    final z = Map<String, dynamic>.from((t[zone] as Map<String, dynamic>?) ?? {});
    final arr = List<dynamic>.from((z[metric] as List<dynamic>?) ?? ['', '', '']);
    arr[pos] = v;
    z[metric] = arr;
    t[zone] = z;
    _setTooth(tooth, t);
  }

  static const _kTotalSites = (16 + 16) * 2 * 3; // 32 teeth x 2 zones x 3 sites = 192

  ({String avgPd, String avgAl, String bopPct, String plaquePct, int bopMarked, int plaqueMarked}) get _stats {
    var bopMarked = 0, plaqueMarked = 0, pdCount = 0, alCount = 0;
    var pdSum = 0.0, alSum = 0.0;
    for (final tooth in [..._kUpperTeeth.keys, ..._kLowerTeeth.keys]) {
      for (final zone in ['buccal', 'lingual']) {
        for (var pos = 0; pos < 3; pos++) {
          if (_getSite(tooth, zone, 'bop', pos) == true) bopMarked++;
          if (_getSite(tooth, zone, 'plaque', pos) == true) plaqueMarked++;
          final pd = double.tryParse('${_getSite(tooth, zone, 'pd', pos)}');
          if (pd != null) {
            pdSum += pd;
            pdCount++;
          }
          final al = double.tryParse('${_getSite(tooth, zone, 'al', pos)}');
          if (al != null) {
            alSum += al;
            alCount++;
          }
        }
      }
    }
    return (
      avgPd: pdCount > 0 ? (pdSum / pdCount).toStringAsFixed(1) : '0.0',
      avgAl: alCount > 0 ? (alSum / alCount).toStringAsFixed(1) : '0.0',
      bopPct: (bopMarked / _kTotalSites * 100).toStringAsFixed(1),
      plaquePct: (plaqueMarked / _kTotalSites * 100).toStringAsFixed(1),
      bopMarked: bopMarked,
      plaqueMarked: plaqueMarked,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 4,
            children: [
              Text('Avg. Probing Depth: ${s.avgPd} mm'),
              Text('Avg. Attachment Level: ${s.avgAl} mm'),
              Text('BOP: ${s.bopPct}% (${s.bopMarked} / $_kTotalSites)'),
              Text('PI: ${s.plaquePct}% (${s.plaqueMarked} / $_kTotalSites)'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _ArchBlock(field: this, teeth: _kUpperTeeth, isUpper: true),
        const SizedBox(height: 12),
        _ArchBlock(field: this, teeth: _kLowerTeeth, isUpper: false),
        const SizedBox(height: 6),
        const Text(
          'Bleeding on Probing / Plaque: tap a site to toggle. Gingival Margin (mm, negative = recession) / Probing Depth (mm) / Attachment Level (mm): enter a value per site. Mobility (0–3) / Furcation (0–3): one value per tooth. Implant: tap to toggle.',
          style: TextStyle(fontSize: 11, color: Colors.black54),
        ),
      ],
    );
  }
}

const _kSiteRows = [
  ('bop', 'Bleeding on Probing', false),
  ('plaque', 'Plaque', false),
  ('gm', 'Gingival Margin', true),
  ('pd', 'Probing Depth', true),
  ('al', 'Attachment Level', true),
];

const _kSingleRows = [
  ('mobility', 'Mobility'),
  ('implant', 'Implant'),
  ('furcation', 'Furcation'),
];

class _ArchBlock extends StatelessWidget {
  const _ArchBlock({required this.field, required this.teeth, required this.isUpper});
  final AdvancedPerioChartField field;
  final Map<int, String> teeth;
  final bool isUpper;

  @override
  Widget build(BuildContext context) {
    // Stored zone keys are always 'buccal'/'lingual' — only the *display*
    // label and *visual row order* flip per arch, matching the same
    // anatomical convention PerioChart.vue/perio_chart_table.dart already
    // established: the two tongue-facing (inner) rows sit adjacent across
    // the arch boundary, so the upper arch's inner block sits below its
    // number row while the lower arch's inner block sits above its number
    // row (i.e. inner-first for the lower arch).
    final innerLabel = isUpper ? 'Palatal' : 'Lingual';
    final outerRows = isUpper ? _kSiteRows : _kSiteRows.reversed.toList();
    final innerRows = isUpper ? _kSiteRows.reversed.toList() : _kSiteRows;
    final firstZone = isUpper ? 'buccal' : 'lingual';
    final firstLabel = isUpper ? 'Buccal' : innerLabel;
    final firstRows = isUpper ? outerRows : innerRows;
    final secondZone = isUpper ? 'lingual' : 'buccal';
    final secondLabel = isUpper ? innerLabel : 'Buccal';
    final secondRows = isUpper ? innerRows : outerRows;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isUpper) ..._singleRows(teeth),
            for (final (key, label, signed) in firstRows) _siteRow(teeth, firstZone, '$firstLabel — $label', key, signed),
            _numberRow(teeth),
            Row(
              children: [
                const SizedBox(width: 130),
                SizedBox(
                  width: teeth.length * 3 * _cellSize,
                  height: 40,
                  child: CustomPaint(painter: _ArchRowPainter(teeth)),
                ),
              ],
            ),
            for (final (key, label, signed) in secondRows) _siteRow(teeth, secondZone, '$secondLabel — $label', key, signed),
            if (!isUpper) ..._singleRows(teeth),
          ],
        ),
      ),
    );
  }

  List<Widget> _singleRows(Map<int, String> teeth) => [
        for (final (key, label) in _kSingleRows) _singleRow(teeth, label, key),
      ];

  Widget _rowLabel(String label) => SizedBox(
        width: 130,
        child: Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey), textAlign: TextAlign.right),
      );

  Widget _singleRow(Map<int, String> teeth, String label, String key) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          _rowLabel(label),
          for (final tooth in teeth.keys) _singleCell(tooth, key),
        ],
      ),
    );
  }

  Widget _singleCell(int tooth, String key) {
    final value = field._getSingle(tooth, key);
    final isToggle = key == 'implant';
    return Container(
      width: _singleCellWidth,
      height: 20,
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400)),
      child: isToggle
          ? Material(
              color: value == true ? Colors.indigo.shade400 : Colors.transparent,
              child: InkWell(
                onTap: field.readOnly ? null : () => field._setSingle(tooth, key, !(value == true)),
                child: Center(
                  child: Text(value == true ? '✓' : '', style: TextStyle(fontSize: 11, color: value == true ? Colors.white : null)),
                ),
              ),
            )
          : TextFormField(
              key: ValueKey('single-$tooth-$key-$value'),
              initialValue: '$value' == 'null' ? '' : '$value',
              enabled: !field.readOnly,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              maxLength: 1,
              style: const TextStyle(fontSize: 11),
              decoration: const InputDecoration(counterText: '', contentPadding: EdgeInsets.zero, border: InputBorder.none),
              onChanged: (v) => field._setSingle(tooth, key, v),
            ),
    );
  }

  Widget _siteRow(Map<int, String> teeth, String zone, String label, String metric, bool signed) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          _rowLabel(label),
          for (final tooth in teeth.keys)
            Row(children: [for (var p = 0; p < 3; p++) _siteCell(tooth, zone, metric, p)]),
        ],
      ),
    );
  }

  Widget _siteCell(int tooth, String zone, String metric, int pos) {
    final value = field._getSite(tooth, zone, metric, pos);
    final isToggle = metric == 'bop' || metric == 'plaque';
    if (isToggle) {
      final marked = value == true;
      final color = metric == 'bop' ? Colors.red.shade600 : Colors.amber.shade600;
      return Container(
        width: _cellSize,
        height: 20,
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400)),
        child: Material(
          color: marked ? color : Colors.transparent,
          child: InkWell(onTap: field.readOnly ? null : () => field._setSite(tooth, zone, metric, pos, !marked)),
        ),
      );
    }
    return SizedBox(
      width: _cellSize,
      height: 20,
      child: TextFormField(
        key: ValueKey('site-$tooth-$zone-$metric-$pos-$value'),
        initialValue: '$value' == 'null' ? '' : '$value',
        enabled: !field.readOnly,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.numberWithOptions(signed: true),
        maxLength: 3,
        style: const TextStyle(fontSize: 10),
        decoration: const InputDecoration(counterText: '', contentPadding: EdgeInsets.zero, border: OutlineInputBorder(borderRadius: BorderRadius.zero)),
        onChanged: (v) => field._setSite(tooth, zone, metric, pos, v),
      ),
    );
  }

  Widget _numberRow(Map<int, String> teeth) => Row(
        children: [
          const SizedBox(width: 130),
          for (final tooth in teeth.keys)
            Container(
              width: 3 * _cellSize,
              height: 18,
              alignment: Alignment.center,
              color: Colors.grey.withValues(alpha: 0.15),
              child: Text('$tooth', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            ),
        ],
      );
}
