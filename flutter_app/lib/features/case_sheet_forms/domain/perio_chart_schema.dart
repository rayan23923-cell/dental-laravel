/// One measurement table within a `chartGroup` — e.g. `{key: 'ppd', label:
/// 'PPD (mm)', type: 'ppd'}`. `type` is `'bop'` (a toggling present/absent
/// mark per site) or `'ppd'`/`'cal'` (a numeric millimetre value per site) —
/// mirrors `Components/PerioChart.vue`'s own `type` prop exactly.
class PerioChartTableSchema {
  const PerioChartTableSchema({required this.key, required this.label, required this.type});

  factory PerioChartTableSchema.fromJson(Map<String, dynamic> json) => PerioChartTableSchema(
        key: json['key'] as String? ?? '',
        label: json['label'] as String? ?? '',
        type: json['type'] as String? ?? 'ppd',
      );

  final String key;
  final String label;
  final String type;
}

/// One `chartGroups` entry — e.g. "Periodontal Chart — Initial", holding
/// the BOP/PPD/CAL tables for that visit stage. `App\Support\
/// PeriodontalChartForm::chartGroups()` is currently the only source of
/// these (periodontal-charts is the only resource with a non-empty
/// `chartGroups` in `CaseSheetPrint::SHEETS`).
class PerioChartGroupSchema {
  const PerioChartGroupSchema({required this.key, required this.title, required this.tables});

  factory PerioChartGroupSchema.fromJson(Map<String, dynamic> json) => PerioChartGroupSchema(
        key: json['key'] as String? ?? '',
        title: json['title'] as String? ?? '',
        tables: (json['tables'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(PerioChartTableSchema.fromJson)
            .toList(),
      );

  final String key;
  final String title;
  final List<PerioChartTableSchema> tables;
}
