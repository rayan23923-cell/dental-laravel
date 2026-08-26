import 'package:flutter/material.dart';

import '../../case_sheet_forms/domain/perio_chart_schema.dart';
import 'perio_chart_table.dart';

/// Renders every `chartGroups` entry (periodontal-charts only, today —
/// "Periodontal Chart — Initial", "After Hygiene Phase", "Follow-up",
/// each holding its own BOP/PPD/CAL tables) as a collapsible section. The
/// web page (`SectionedForm.vue`) shows all of them expanded at once,
/// fine on a wide desktop layout; collapsing each group by default here is
/// a deliberate, minor mobile-screen adaptation — 8 full 32-tooth tables
/// stacked open on a phone would be an unusable wall of tiny inputs, and
/// nothing about the data or its editability changes, only what's visible
/// without a tap.
///
/// [value] is the outer `chart_data` object as already-decoded JSON
/// (`{teeth: {}, perioChart: {...}, perioChartPostHygiene: {...}, ...}`,
/// matching the web app's own shape exactly, "teeth" placeholder
/// included so a chart saved here still parses identically in the
/// original PHP app).
class PerioChartGroupsField extends StatelessWidget {
  const PerioChartGroupsField({
    super.key,
    required this.groups,
    required this.value,
    required this.onChanged,
    required this.readOnly,
  });

  final List<PerioChartGroupSchema> groups;
  final Map<String, dynamic> value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool readOnly;

  Map<String, dynamic> _tableValue(String groupKey, String tableKey) {
    final group = value[groupKey] as Map<String, dynamic>?;
    return (group?[tableKey] as Map<String, dynamic>?) ?? {};
  }

  void _setTableValue(String groupKey, String tableKey, Map<String, dynamic> tableValue) {
    final next = Map<String, dynamic>.from(value);
    final group = Map<String, dynamic>.from((next[groupKey] as Map<String, dynamic>?) ?? {});
    group[tableKey] = tableValue;
    next[groupKey] = group;
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in groups)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: ExpansionTile(
              title: Text(group.title, style: Theme.of(context).textTheme.titleMedium),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                for (final table in group.tables)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: PerioChartTable(
                      label: table.label,
                      type: table.type,
                      value: _tableValue(group.key, table.key),
                      readOnly: readOnly,
                      onChanged: (next) => _setTableValue(group.key, table.key, next),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
