import 'package:flutter/material.dart';

/// FDI tooth order, port of `Components/PerioChart.vue`'s own `UPPER`/
/// `LOWER` arrays.
const kPerioUpperArch = [18, 17, 16, 15, 14, 13, 12, 11, 21, 22, 23, 24, 25, 26, 27, 28];
const kPerioLowerArch = [48, 47, 46, 45, 44, 43, 42, 41, 31, 32, 33, 34, 35, 36, 37, 38];

const double _cellSize = 26;

/// One BOP/PPD/CAL 32-tooth grid — a faithful port of
/// `Components/PerioChart.vue`, one table at a time (the web page renders
/// several of these per periodontal record, driven by `chartGroups`; see
/// `PerioChartGroupsField`). 3 sites per zone (mesial/mid/distal, stored
/// positionally, not labeled individually — matching the original, which
/// never labels them beyond their column position either).
///
/// Row order is anatomical, not arbitrary: upper arch shows buccal (the
/// cheek-facing side) on top since it faces "outward/up" in a mouth
/// diagram, then the tooth number, then palatal on the bottom (facing the
/// roof of the mouth, "inward"); the lower arch mirrors this so the two
/// tongue-facing rows (palatal/lingual) sit adjacent in the middle when a
/// doctor scans between arches — exactly the original's row order
/// (`Components/PerioChart.vue`'s template renders the lower arch's
/// "lingual" row *before* its tooth-number/buccal rows for this reason).
class PerioChartTable extends StatelessWidget {
  const PerioChartTable({
    super.key,
    required this.label,
    required this.type,
    required this.value,
    required this.onChanged,
    required this.readOnly,
    this.extractedTeeth = const [],
  });

  final String label;
  final String type; // 'bop' | 'ppd' | 'cal'
  final Map<String, dynamic> value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool readOnly;
  // FDI tooth numbers marked extracted in the Plaque Index chart — greys
  // out that tooth's whole column here, port of the original's own
  // syncDentalToPerio()/syncPerioFromDental() (`.tooth-col.missing`).
  // Visual only, same as the original: doesn't clear or disable the
  // tooth's existing site values.
  final List<int> extractedTeeth;

  bool get _isBop => type == 'bop';
  bool _isExtracted(int tooth) => extractedTeeth.contains(tooth);

  String _siteValue(int tooth, String zone, int pos) {
    final entry = value[tooth.toString()] as Map<String, dynamic>?;
    final zoneList = entry?[zone] as List<dynamic>?;
    return zoneList != null && pos < zoneList.length ? (zoneList[pos]?.toString() ?? '') : '';
  }

  void _setSite(int tooth, String zone, int pos, String newValue) {
    final next = Map<String, dynamic>.from(value);
    final key = tooth.toString();
    final current = Map<String, dynamic>.from(
      (next[key] as Map<String, dynamic>?) ?? {'buccal': ['', '', ''], 'lingual': ['', '', '']},
    );
    final zoneList = List<String>.from(
      (current[zone] as List<dynamic>?)?.map((e) => e?.toString() ?? '') ?? ['', '', ''],
    );
    zoneList[pos] = newValue;
    current[zone] = zoneList;
    next[key] = current;
    onChanged(next);
  }

  Widget _cell(BuildContext context, int tooth, String zone, int pos) {
    final current = _siteValue(tooth, zone, pos);
    final extracted = _isExtracted(tooth);
    if (_isBop) {
      final marked = current == '+';
      return Opacity(
        opacity: extracted ? 0.4 : 1,
        child: Container(
          width: _cellSize,
          height: _cellSize,
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            color: extracted ? Colors.grey.shade300 : null,
          ),
          child: Material(
            color: marked ? Colors.red.shade600 : Colors.transparent,
            child: InkWell(
              onTap: readOnly ? null : () => _setSite(tooth, zone, pos, marked ? '' : '+'),
              child: Center(
                child: Text(
                  marked ? '+' : '',
                  style: TextStyle(fontSize: 11, color: marked ? Colors.white : null, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Opacity(
      opacity: extracted ? 0.4 : 1,
      child: SizedBox(
        width: _cellSize,
        height: _cellSize,
        child: TextFormField(
          key: ValueKey('$tooth-$zone-$pos-$current'),
          initialValue: current,
          enabled: !readOnly,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 2,
          style: const TextStyle(fontSize: 11),
          decoration: InputDecoration(
            counterText: '',
            contentPadding: EdgeInsets.zero,
            border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
            filled: extracted,
            fillColor: Colors.grey.shade300,
          ),
          onChanged: (v) => _setSite(tooth, zone, pos, v),
        ),
      ),
    );
  }

  Widget _zoneRow(BuildContext context, List<int> teeth, String zone) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final tooth in teeth)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [for (var p = 0; p < 3; p++) _cell(context, tooth, zone, p)],
            ),
        ],
      );

  Widget _numberRow(List<int> teeth) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final tooth in teeth)
            Container(
              width: _cellSize * 3,
              height: 20,
              alignment: Alignment.center,
              color: _isExtracted(tooth) ? Colors.red.shade100 : Colors.grey.withValues(alpha: 0.15),
              child: Text(
                _isExtracted(tooth) ? '$tooth ✕' : tooth.toString(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: _isExtracted(tooth) ? Colors.red.shade700 : null,
                ),
              ),
            ),
        ],
      );

  Widget _archBlock(BuildContext context, List<int> teeth, bool isUpper) {
    final innerLabel = isUpper ? 'Palatal' : 'Lingual';
    final rows = isUpper
        ? [
            ('Buccal', _zoneRow(context, teeth, 'buccal')),
            (null, _numberRow(teeth)),
            (innerLabel, _zoneRow(context, teeth, 'lingual')),
          ]
        : [
            (innerLabel, _zoneRow(context, teeth, 'lingual')),
            (null, _numberRow(teeth)),
            ('Buccal', _zoneRow(context, teeth, 'buccal')),
          ];

    // Forced LTR for the same reason as the dental chart's arch rows (see
    // ToothOdontogramField._archRow): FDI tooth order and mesial/distal
    // site order are fixed anatomical readings that must not flip with
    // the app's Arabic (RTL) locale. Confirmed as a real bug, not a
    // theoretical one — a tap on a tooth's first site landed in the
    // stored array's last position before this fix (see
    // flutter_app/README.md).
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (rowLabel, row) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  children: [
                    SizedBox(width: 50, child: Text(rowLabel ?? '', style: const TextStyle(fontSize: 10, color: Colors.grey))),
                    row,
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        _archBlock(context, kPerioUpperArch, true),
        const SizedBox(height: 8),
        _archBlock(context, kPerioLowerArch, false),
      ],
    );
  }
}
