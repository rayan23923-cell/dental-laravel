import 'case_sheet_field.dart';
import 'perio_chart_schema.dart';

class CaseSheetSection {
  const CaseSheetSection({required this.title, required this.note, required this.femaleOnly, required this.fields});

  factory CaseSheetSection.fromJson(Map<String, dynamic> json) => CaseSheetSection(
        title: json['title'] as String? ?? '',
        note: json['note'] as String?,
        femaleOnly: json['femaleOnly'] as bool? ?? false,
        fields: (json['fields'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(CaseSheetField.fromJson)
            .toList(),
      );

  final String title;
  final String? note;
  final bool femaleOnly;
  final List<CaseSheetField> fields;
}

/// `GET /api/v1/case-sheet-forms/{resource}` — the layout `App\Support\
/// CaseSheetPrintRenderer`/`SectionedForm.vue` already drive from. Record
/// values are fetched separately from the resource's own REST endpoint;
/// this is layout only.
class CaseSheetFormSchema {
  const CaseSheetFormSchema({
    required this.resource,
    required this.title,
    required this.sections,
    required this.groupColumns,
    required this.stages,
    required this.chartGroups,
    required this.chartField,
  });

  factory CaseSheetFormSchema.fromJson(Map<String, dynamic> json) => CaseSheetFormSchema(
        resource: json['resource'] as String,
        title: json['title'] as String,
        sections: (json['sections'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(CaseSheetSection.fromJson)
            .toList(),
        groupColumns: (json['groupColumns'] as List<dynamic>? ?? []).cast<String>(),
        // `stages` (the 9-row evaluation table, complete
        // denture/prosthodontics) isn't rendered by DynamicSectionForm
        // yet — same "incrementally after" scope as the composite field
        // types (see flutter_app/README.md). Still parsed here since it's
        // cheap and the raw values aren't lost, just not rendered.
        stages: (json['stages'] as List<dynamic>? ?? []).whereType<Map<String, dynamic>>().toList(),
        chartGroups: (json['chartGroups'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(PerioChartGroupSchema.fromJson)
            .toList(),
        chartField: json['chartField'] as String?,
      );

  final String resource;
  final String title;
  final List<CaseSheetSection> sections;
  final List<String> groupColumns;
  final List<Map<String, dynamic>> stages;
  final List<PerioChartGroupSchema> chartGroups;
  final String? chartField;

  /// Every field across every section, flattened — used to walk the
  /// schema once when seeding/collecting form values instead of nesting
  /// section loops at every call site.
  List<CaseSheetField> get allFields => sections.expand((s) => s.fields).toList();
}

/// All 8 case-sheet resources a doctor can create a *new* record for from
/// this app. `periodontal-charts` was the last holdout — its API `store()`
/// hard-requires `chart_data` (the per-tooth perio chart, `PerioChart.vue`
/// on the web side), a field with no plain `sections()` entry, unblocked
/// once `PerioChartGroupsField` was built (see flutter_app/README.md,
/// "Periodontal chart create"). Checked directly against every one of the
/// 8 API controllers' `validateRecord()` before ever trusting this list —
/// not guessed (see `dental_laravel/README.md`, "Case-sheet create — the
/// real blocker was patient_id, not a Patients CRUD screen").
const kCaseSheetCreatableResources = {
  'dental-charts',
  'oral-medicine-charts',
  'orthodontics-records',
  'prevention-records',
  'complete-denture-records',
  'prosthodontics-records',
  'surgeries',
  'periodontal-charts',
};

/// Extra top-level fields a resource's API `store()` requires that never
/// appear in `sections()` at all (so `DynamicSectionForm` has no field to
/// collect them from) and therefore must be injected before a create
/// `POST`. `doctor_id` is handled separately (always the logged-in
/// doctor, every resource) — this map is only for the resource-specific
/// extras beyond that.
Map<String, dynamic> caseSheetCreateDefaults(String resource) => switch (resource) {
      // OperativeForm's layout never asks for a dentition type; the web
      // controller's own doc comment confirms 'permanent' is the default
      // and the only option the ported layout exposes.
      'dental-charts' => {'chart_type': 'permanent'},
      _ => const {},
    };
