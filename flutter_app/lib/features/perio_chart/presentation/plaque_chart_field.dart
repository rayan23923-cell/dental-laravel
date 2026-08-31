import 'package:flutter/material.dart';

import '../../case_sheet_forms/domain/perio_chart_schema.dart';
// ignore: unused_import
import 'perio_chart_groups_field.dart';

/// FDI tooth number => the same left-to-right per-arch order
/// `App\Support\PlaqueChart::UPPER_TEETH`/`LOWER_TEETH` use — the type
/// value itself (molar/premolar/...) only matters for the print SVG's
/// tooth shape, not for this on-screen editor, so it isn't carried here.
const _kUpperTeeth = [18, 17, 16, 15, 14, 13, 12, 11, 21, 22, 23, 24, 25, 26, 27, 28];
const _kLowerTeeth = [48, 47, 46, 45, 44, 43, 42, 41, 31, 32, 33, 34, 35, 36, 37, 38];
const _kSurfaces = ['buccal', 'distal', 'lingual', 'mesial'];
const _kSurfaceLabels = {'buccal': 'B', 'distal': 'D', 'lingual': 'L', 'mesial': 'M'};

/// Periodontal's "Plaque Index" per-visit dental chart — a completely
/// separate feature from [PerioChartGroupsField]'s BOP/PPD/CAL tables
/// despite living in the same `chart_data` column (see
/// `App\Support\PlaqueChart`'s own doc comment): one boolean per
/// tooth/surface ("was plaque present here"), tracked across 5 visits,
/// with a live-computed percentage.
///
/// Deliberately a plain checkbox grid here rather than the original's own
/// tap-a-curved-tooth-diagram editor (`dental_clinics2/doctor/
/// periodontal_chart.php`'s `createToothSVG`) — this is a boolean
/// present/absent mark per surface, not a multi-status picker the way the
/// Operative sheet's flower-chart odontogram is, so a checkbox conveys
/// the same information with far less code and no tap-target precision
/// problem on a small screen. The *printed* chart (`case_sheet_print_pdf.dart`)
/// still draws the original's real curved tooth shapes — this simplification
/// is on-screen only, the same "simpler input, faithful output" tradeoff
/// already made for [PerioChartGroupsField] itself (see its own doc
/// comment).
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
    for (final toothId in [..._kUpperTeeth, ..._kLowerTeeth]) {
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
          const Align(alignment: Alignment.centerRight, child: Text('الفك العلوي — Upper Arch')),
          for (final toothId in _kUpperTeeth) _ToothRow(field: field, visitKey: visit.key, toothId: toothId),
          const Divider(),
          const Align(alignment: Alignment.centerRight, child: Text('الفك السفلي — Lower Arch')),
          for (final toothId in _kLowerTeeth) _ToothRow(field: field, visitKey: visit.key, toothId: toothId),
        ],
      ),
    );
  }
}

class _ToothRow extends StatelessWidget {
  const _ToothRow({required this.field, required this.visitKey, required this.toothId});
  final PlaqueChartField field;
  final String visitKey;
  final int toothId;

  @override
  Widget build(BuildContext context) {
    final tooth = field._toothData(visitKey, toothId);
    final extracted = field._isExtracted(tooth);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 28, child: Text('$toothId', style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(
            child: Wrap(
              spacing: 4,
              children: [
                for (final surface in _kSurfaces)
                  FilterChip(
                    label: Text(_kSurfaceLabels[surface]!, style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    selected: !extracted && field._isMarked(tooth, surface),
                    onSelected: (field.readOnly || extracted) ? null : (_) => field._toggleSurface(visitKey, toothId, surface),
                  ),
              ],
            ),
          ),
          FilterChip(
            label: const Text('مخلوع', style: TextStyle(fontSize: 11)),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            selected: extracted,
            selectedColor: Colors.red.shade100,
            onSelected: field.readOnly ? null : (_) => field._toggleExtracted(visitKey, toothId),
          ),
        ],
      ),
    );
  }
}
