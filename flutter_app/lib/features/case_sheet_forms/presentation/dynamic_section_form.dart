import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../dental_chart/presentation/tooth_odontogram_field.dart';
import '../../endodontics/presentation/endodontics_field.dart';
import '../../perio_chart/presentation/advanced_perio_chart_sessions_field.dart';
import '../../perio_chart/presentation/perio_chart_groups_field.dart';
import '../../perio_chart/presentation/plaque_chart_field.dart';
import '../domain/case_sheet_field.dart';
import '../domain/case_sheet_form_schema.dart';
import 'extraoral_intraoral_exam_field.dart';
import 'family_history_field.dart';
import 'history_of_complaint_field.dart';
import 'prosthodontics_dental_arch_svg.dart';
import 'quadrant_repeater_field.dart';
import 'quadrant_teeth_field.dart';
import 'social_history_field.dart';
import 'surgical_history_field.dart';
import 'teeth_squares_grid_field.dart';
import 'value_details_checklist_field.dart';

/// Renders any of the 8 case-sheet resources from its
/// `CaseSheetFormSchema` — one generic widget instead of 12 bespoke
/// screens, mirroring `resources/js/Pages/Specialty/SectionedForm.vue`
/// on the web side (see flutter_app/README.md §4).
///
/// Supports: text, textarea, number, decimal, date, time, select, radio,
/// checkboxes, boolean, `teeth` (the real FDI-cross quadrant picker, see
/// `QuadrantTeethField` — was a plain comma-list text field until
/// 2026-08-29, matching web's `QuadrantTeeth.vue` now),
/// `dental_chart` (the full odontogram, see `ToothOdontogramField`),
/// `endodontics` (the Operative sheet's root-canal treatment record, see
/// `EndodonticsField`), and `extraoral_exam` (Oral Medicine's muscle-
/// tenderness/TMJ grid plus the four head pain-location diagrams, see
/// `ExtraoralIntraoralExamField`/`HeadDiagramsBoard` — added 2026-08-29,
/// by request, since it's the one Oral Medicine composite involving real
/// reference images with tap-to-mark drawings, matching web's
/// `HeadDiagramsBoard.vue`), and Oral Medicine's other five JSON-blob
/// composites (2026-08-29, by request — a live screenshot showed all
/// five still rendering as "غير مدعوم في التطبيق بعد" placeholders):
/// `history_complaint` (`HistoryOfComplaintField` — the 28-item symptom
/// checklist plus six follow-up questions and a pain scale),
/// `pmh_checklist` (`ValueDetailsChecklistField`, generic over the
/// field's own `options`), `surgical_history`/`family_history`/
/// `social_history` (their own dedicated fields, each a direct port of
/// the matching `Components/*Section.vue`), and Orthodontics'
/// `teeth_squares_grid`/`quadrant_repeater` (`TeethSquaresGridField`/
/// `QuadrantRepeaterField`, added the same day — the "Number of Teeth"
/// 4×16 marking grid and the two repeating info+quadrant-picker lists,
/// "Stages of treatment"/"Appliance type & Design"; the latter reuses
/// `QuadrantTeethField` per row rather than a second tooth-picker
/// implementation). A resource's `chartGroups`/`chartField`
/// (periodontal-charts only, today — the BOP/PPD/CAL per-tooth tables)
/// are rendered separately, after every `sections()` card, via
/// `PerioChartGroupsField` — they're not `sections()` fields at all, so
/// they sit outside the field-type switch below entirely. Every other
/// unhandled type renders as a read-only placeholder instead of an
/// editable control — and, critically, is never touched by
/// `buildSubmitPayload()`, so saving never silently drops data this form
/// can't edit yet. For a *grouped* field (e.g. one subkey inside
/// Orthodontics' `examination_data` blob) this means the group is
/// reassembled from a copy of its original decoded object with only the
/// supported subkeys overwritten — an unsupported sibling subkey inside
/// the same JSON blob survives a save untouched rather than being wiped
/// because this form didn't render a control for it.
/// Oral Medicine's JSON-blob columns — none carry an Eloquent 'array'
/// cast, so they arrive as (and must be re-serialized back into) a JSON
/// *string*, unlike `dental_chart`/`endodontics`. Mirrors
/// `SectionedForm.vue`'s identically-named `JSON_BLOB_FIELD_TYPES`.
const _jsonBlobFieldTypes = {
  'extraoral_exam', 'history_complaint', 'pmh_checklist',
  'surgical_history', 'family_history', 'social_history',
};

class DynamicSectionForm extends StatefulWidget {
  const DynamicSectionForm({
    super.key,
    required this.resource,
    required this.schema,
    required this.record,
    required this.readonly,
    required this.onSubmit,
    required this.t,
    this.supervisorEditableFields = const [],
  });

  /// Translations for this form's own static chrome (buttons, "Sign",
  /// "Cancel", required-field errors, …) — never applied to `field.label`/
  /// `section.title`, which come from the server's own case-sheet layout
  /// registry and stay exactly as-is regardless of locale, by request (see
  /// `app_translations.dart`'s class doc). Passed in from
  /// `CaseSheetFormScreen`, the one `ConsumerWidget` in this chain — this
  /// widget and its private field-type widgets below are plain
  /// `StatefulWidget`s with no `ref` of their own, so `t` rides down
  /// through `state`/`widget.state` the same way `readonly` already does,
  /// rather than converting this whole subtree to Riverpod.
  final Map<String, String> t;

  /// The case-sheet resource slug (e.g. `"prosthodontics-records"`) — used
  /// only to gate the resource-specific extras below `sections()`
  /// (currently just the prosthodontics dental-arch preview), matching how
  /// `Api\CaseSheetPrintController` scopes its own `dental_arch` key the
  /// same way.
  final String resource;

  final CaseSheetFormSchema schema;

  /// The raw record JSON (a case-sheet REST resource's `data` object).
  final Map<String, dynamic> record;
  final bool readonly;
  final Future<void> Function(Map<String, dynamic> payload) onSubmit;

  /// This viewer's own supervisor-editable fields (mirrors
  /// `App\Support\CaseSheetSupervisorFields` — empty for a doctor's own
  /// edit, populated only for a staff viewer via
  /// `Api\CaseSheetController::open()`'s `supervisor_editable_fields`).
  /// A field in this list stays editable even though [readonly] is true,
  /// per the supervisor-preview feature (2026-08-28): staff may view but
  /// never save, except these.
  final List<String> supervisorEditableFields;

  @override
  State<DynamicSectionForm> createState() => DynamicSectionFormState();
}

class DynamicSectionFormState extends State<DynamicSectionForm> {
  Map<String, String> get t => widget.t;

  final _formKey = GlobalKey<FormState>();
  final Map<String, dynamic> _values = {};
  final Map<String, Map<String, dynamic>> _groupOriginals = {};
  final Map<String, TextEditingController> _controllers = {};
  Map<String, dynamic> _chartValue = {};
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _seed();
  }

  Map<String, dynamic> _parseGroup(dynamic raw) {
    if (raw == null) return {};
    if (raw is Map<String, dynamic>) return raw;
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        return decoded is Map<String, dynamic> ? decoded : {};
      } catch (_) {
        return {};
      }
    }
    return {};
  }

  void _seed() {
    for (final group in widget.schema.groupColumns) {
      _groupOriginals[group] = _parseGroup(widget.record[group]);
    }

    final chartField = widget.schema.chartField;
    if (chartField != null) {
      _chartValue = _parseGroup(widget.record[chartField]);
    }

    for (final field in widget.schema.allFields) {
      dynamic raw;
      final group = field.group;
      if (group != null) {
        raw = _groupOriginals[group]?[field.key];
      } else {
        raw = widget.record[field.key];
      }
      _values[field.formKey] = _coerce(field, raw);

      if (_isTextControlled(field.type)) {
        _controllers[field.formKey] = TextEditingController(text: (_values[field.formKey] as String?) ?? '');
      }
    }

    // Stage rows (Prosthodontics/Complete Denture's 9-row evaluation
    // table) bind to `stage_{key}_{signature,date,grade}` columns, the
    // original's own naming — not `sections()` fields, so not covered by
    // the loop above; matches `SectionedForm.vue`'s identical stage-row
    // seeding. Added 2026-08-29, by request: this table (the one place
    // `diagnosis_instructor_signature`'s per-stage sign-off actually
    // lives) wasn't rendered on Flutter at all before, so a supervisor
    // had no way to fill it in on mobile even though the permission
    // model already reserved it for them (`CaseSheetSupervisorFields`).
    for (final stage in widget.schema.stages) {
      final key = stage['key'] as String;
      for (final part in ['signature', 'date', 'grade']) {
        final formKey = 'stage_${key}_$part';
        final raw = widget.record[formKey];
        _values[formKey] = part == 'date' ? _coerceDate(raw) : (raw?.toString() ?? '');
        if (part != 'date') {
          _controllers[formKey] = TextEditingController(text: _values[formKey] as String);
        }
      }
    }
  }

  /// Same date-string normalization as `_coerce()`'s `'date'` case — kept
  /// separate since stage fields aren't `CaseSheetField`s and don't go
  /// through `_coerce()`.
  String _coerceDate(dynamic raw) {
    final s = raw?.toString();
    if (s == null || s.isEmpty) return '';
    final match = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(s);
    return match?.group(1) ?? s;
  }

  bool _isTextControlled(String type) =>
      const {'text', 'textarea', 'number', 'decimal'}.contains(type);

  dynamic _coerce(CaseSheetField field, dynamic raw) {
    switch (field.type) {
      case 'boolean':
        if (raw is bool) return raw;
        if (raw is String) return ['1', 'yes', 'true', 'on'].contains(raw.toLowerCase());
        return raw == 1;
      case 'checkboxes':
        if (raw is List) return raw.map((e) => e.toString()).toList();
        return <String>[];
      case 'date':
        final s = raw?.toString();
        if (s == null || s.isEmpty) return '';
        final match = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(s);
        return match?.group(1) ?? s;
      case 'time':
        final s = raw?.toString();
        return (s != null && s.length >= 5) ? s.substring(0, 5) : (s ?? '');
      case 'dental_chart':
        return raw is List ? List<dynamic>.from(raw) : <dynamic>[];
      case 'endodontics':
        return _parseGroup(raw);
      case 'teeth_squares_grid':
      case 'quadrant_repeater':
        // Grouped subkeys (inside `examination_data`) whose value is
        // itself an object/array, not a scalar — unlike the JSON-blob
        // *columns* below, the whole group's JSON string is decoded once
        // in `_seed()`/`_parseGroup()`, so `raw` here already arrived as
        // a real `Map` (or a `List` — an empty `[]` on a fresh record,
        // per `OrthodonticsRecordController::prepare()`'s defaults — not
        // yet ever a populated list, since both PHP-side callers only
        // ever write associative keys into these two). The existing
        // group-reassembly in `buildSubmitPayload()` re-encodes the
        // *whole* group column, so no per-field `jsonEncode` is needed
        // here the way `extraoral_exam` etc. below need one.
        return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      case 'extraoral_exam':
      case 'history_complaint':
      case 'pmh_checklist':
      case 'surgical_history':
      case 'family_history':
      case 'social_history':
        // None of Oral Medicine's six JSON-blob composite columns carry
        // an Eloquent 'array' cast (unlike `endodontics_data` above) —
        // see `_jsonBlobFieldTypes`/`buildSubmitPayload()`'s matching
        // `jsonEncode` for the other half of this.
        return _parseGroup(raw);
      default:
        return raw?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> buildSubmitPayload() {
    final payload = <String, dynamic>{};
    final groupBuckets = <String, Map<String, dynamic>>{
      for (final g in widget.schema.groupColumns) g: Map<String, dynamic>.from(_groupOriginals[g] ?? {}),
    };

    for (final field in widget.schema.allFields) {
      if (!field.isSupported) continue; // leave unsupported fields untouched — see class doc.
      // A field this viewer can't edit (`fieldDisabled()` — most often a
      // doctor looking at a supervisor-only grade/signature) is left out
      // of the payload entirely rather than echoed back, matching this
      // endpoint's own `sometimes`-validated partial-update contract (see
      // `CaseSheetRecordRepository.update()`'s doc comment): omitted means
      // "untouched," never "clear this." Echoing it back used to be
      // harmless when the echoed value was always fresh, but a real
      // production bug this session (`EnforceCaseSheetAccess` 403-ing a
      // doctor's own save) showed that isn't guaranteed even online, and
      // matters much more once a save can queue offline for hours against
      // a cached, possibly-stale value. **Grouped fields are the one
      // exception** — a group's whole JSON blob is always resubmitted
      // below regardless (`groupBuckets`), so an individual disabled
      // subkey still rides along unchanged from `_groupOriginals`; omitting
      // just that subkey from the blob would read as "clear it," not
      // "unchanged" (`EnforceCaseSheetAccess::changedFields()`'s grouped
      // diff treats a missing subkey as `''`). Only 2 of the 8 resources
      // have a supervisor-only *grouped* subkey at all
      // (`prevention-records`/`oral-medicine-charts`), and this doesn't
      // make their existing staleness exposure any worse than an ordinary
      // stale page reload already was — a real fix needs a fresher
      // baseline than this form has, not a payload-shape change.
      if (fieldDisabled(field)) continue;
      final value = _values[field.formKey];

      if (field.group != null) {
        groupBuckets[field.group!]![field.key] = value;
      } else if (_jsonBlobFieldTypes.contains(field.type)) {
        // See `_coerce()`'s matching comment — none of these columns has
        // an Eloquent cast, so the Map this form works with must be
        // stringified before it reaches the API, unlike `endodontics`'s
        // `endodontics_data` (which does have one and is sent as-is).
        payload[field.key] = jsonEncode(value);
      } else {
        payload[field.key] = value;
      }
    }

    for (final entry in groupBuckets.entries) {
      payload[entry.key] = jsonEncode(entry.value);
    }

    final chartField = widget.schema.chartField;
    if (chartField != null) {
      // `teeth` is a legacy placeholder the original web app always
      // emits too (`SectionedForm.vue`'s own `submit()`) — kept so a
      // chart saved here parses identically in the original PHP app.
      payload[chartField] = jsonEncode({'teeth': {}, ..._chartValue});
    }

    // Stage rows — see `_seed()`'s matching comment; flat top-level
    // columns like everything else here, never grouped. Same
    // fieldDisabled()-skip reasoning as above, via `stageFieldDisabled()`
    // — every stage's signature/date/grade is supervisor-only on the two
    // resources that have stages at all (Prosthodontics/Complete Denture),
    // so unconditionally echoing these back was exactly what triggered the
    // real 403 bug this fix traces back to.
    for (final stage in widget.schema.stages) {
      final key = stage['key'] as String;
      for (final part in ['signature', 'date', 'grade']) {
        if (stageFieldDisabled(key, part)) continue;
        final formKey = 'stage_${key}_$part';
        payload[formKey] = _values[formKey];
      }
    }

    return payload;
  }

  /// Two independent reasons a field can be locked (2026-08-29, reworked
  /// — mirrors `SectionedForm.vue`'s identically-restructured
  /// `fieldDisabled()`, see its comment for the full history):
  ///
  /// 1. It's in `widget.schema.supervisorFields` — the registry's full,
  ///    unconditional list — and this viewer isn't allowed to edit it
  ///    (`supervisorEditableFields` is always `[]` for a doctor). Locked
  ///    regardless of `widget.readonly`, since a doctor's own edit screen
  ///    has `readonly == false`: previously these rendered as ordinary,
  ///    fully-editable fields on a doctor's own page, which is what was
  ///    reported ("معلومات المشرف... يجب ازالتهما من صفحة الطبيب"),
  ///    then clarified to stay visible, just locked rather than removed
  ///    ("فقط اظهر... لكن لايمكن تعديلها من الطبيب").
  /// 2. Every other field stays locked under the pre-existing `readonly`
  ///    rule (a staff supervisor-preview may look but not touch anything
  ///    outside their own handful of fields).
  ///
  /// Grouped subkeys use `field.key` (not `formKey`) since that's the bare
  /// name the registry lists (e.g. Prevention's `senior_name`).
  bool fieldDisabled(CaseSheetField field) => widget.schema.supervisorFields.contains(field.key)
      ? !widget.supervisorEditableFields.contains(field.key)
      : widget.readonly && !widget.supervisorEditableFields.contains(field.key);

  /// Same two-reason logic as [fieldDisabled], for the stage-evaluation
  /// table's rows (Prosthodontics/Complete Denture) — these aren't
  /// `CaseSheetField`s, so they need their own check against the same
  /// `stage_{key}_{part}`-keyed entries `CaseSheetSupervisorFields::
  /// stageFields()` puts in both `supervisorFields` and
  /// `supervisorEditableFields`. Mirrors `SectionedForm.vue`'s
  /// identically-named `stageFieldDisabled()`.
  bool stageFieldDisabled(String stageKey, String part) {
    final key = 'stage_${stageKey}_$part';
    return widget.schema.supervisorFields.contains(key)
        ? !widget.supervisorEditableFields.contains(key)
        : widget.readonly && !widget.supervisorEditableFields.contains(key);
  }

  /// The Save button was unconditionally hidden under `readonly` —
  /// correct while staff were fully locked out, but a supervisor with
  /// actual editable fields needs it to save those.
  bool get canSubmit => !widget.readonly || widget.supervisorEditableFields.isNotEmpty;

  /// Public entry point for "مسح رمز المريض" (2026-08-28) —
  /// `CaseSheetFormScreen` calls this via a `GlobalKey<DynamicSectionFormState>`
  /// after resolving a scanned patient-registration QR, once per mapped
  /// field. Only fills a field that's currently blank — never overwrites
  /// something already typed, per the user's own framing of this feature.
  /// `formKey` (not `field.key`) is the right address here: it's exactly
  /// what `_values`/`_controllers` are keyed by, grouped fields included
  /// (mirrors `SectionedForm.vue`'s `form[key]` target).
  void setFieldIfBlank(String formKey, String value) {
    final current = _values[formKey];
    final isBlank = current == null || (current is String && current.isEmpty);
    if (!isBlank) return;

    final controller = _controllers[formKey];
    if (controller != null) {
      // Setting .text already repaints this field; onChanged only fires
      // on user interaction, so _values needs updating here too.
      controller.text = value;
      _values[formKey] = value;
    } else {
      setState(() => _values[formKey] = value);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;

    setState(() => _submitting = true);
    try {
      await widget.onSubmit(buildSubmitPayload());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// FDI tooth numbers marked extracted in the Plaque Index chart, fed into
  /// `PerioChartGroupsField`'s BOP/PPD/CAL tables so a pulled tooth shows
  /// the same greyed-out column everywhere — port of the original's own
  /// `syncDentalToPerio()`/`syncPerioFromDental()`. All 5 visits already
  /// carry the same `extracted` flag in sync with each other
  /// (`PlaqueChartField._toggleExtractedAllVisits()`), so reading across
  /// every visit here is belt-and-braces rather than strictly necessary.
  List<int> get _extractedTeeth {
    final dentalCharts = _chartValue['dentalCharts'] as Map<String, dynamic>?;
    if (dentalCharts == null) return const [];
    final ids = <int>{};
    for (final visit in widget.schema.plaqueVisits) {
      final teeth = (dentalCharts[visit.key] as Map<String, dynamic>?)?['teeth'] as Map<String, dynamic>?;
      teeth?.forEach((id, data) {
        if (data is Map && data['extracted'] == true) {
          final n = int.tryParse(id);
          if (n != null) ids.add(n);
        }
      });
    }
    return ids.toList();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final section in widget.schema.sections) _SectionCard(section: section, state: this),
          if (widget.resource == 'prosthodontics-records') _ProsthodonticsDentalArchPreview(state: this),
          if (widget.schema.stages.isNotEmpty) _StageEvaluationTable(stages: widget.schema.stages, state: this),
          if (widget.schema.chartGroups.isNotEmpty)
            PerioChartGroupsField(
              groups: widget.schema.chartGroups,
              value: _chartValue,
              readOnly: widget.readonly,
              onChanged: (next) => setState(() => _chartValue = next),
              extractedTeeth: _extractedTeeth,
            ),
          if (widget.schema.plaqueVisits.isNotEmpty)
            PlaqueChartField(
              visits: widget.schema.plaqueVisits,
              // Lives under its own `dentalCharts` top-level key inside the
              // same `_chartValue`/`chart_data` map `PerioChartGroupsField`
              // above already reads/writes — see PlaqueChartField's own doc
              // comment for why it's a sibling key rather than a separate
              // form field/column. No change needed to buildSubmitPayload()'s
              // `{'teeth': {}, ..._chartValue}` spread: this key rides along
              // with every other `_chartValue` entry automatically.
              value: (_chartValue['dentalCharts'] as Map<String, dynamic>?) ?? const {},
              readOnly: widget.readonly,
              onChanged: (next) => setState(() => _chartValue = {..._chartValue, 'dentalCharts': next}),
            ),
          if (widget.schema.advancedPerioChart)
            // "Advanced Periodontal Chart" — a completely separate 32-tooth
            // grid mechanism from chartGroups/plaqueVisits above (this
            // resource has neither), sharing the same `_chartValue`/
            // `chart_data` map under its own `advancedChart` key, which now
            // holds a doctor-managed list of sessions rather than one
            // snapshot (2026-09-04, matching the web the same day). See
            // AdvancedPerioChartSessionsField's own doc comment. No change
            // needed to buildSubmitPayload()'s existing spread, same
            // reasoning as `dentalCharts` above — this key rides along
            // opaquely either way.
            AdvancedPerioChartSessionsField(
              value: (_chartValue['advancedChart'] as Map<String, dynamic>?) ?? const {},
              readOnly: widget.readonly,
              onChanged: (next) => setState(() => _chartValue = {..._chartValue, 'advancedChart': next}),
            ),
          if (canSubmit) ...[
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(t['caseSheetForm.saveButton']!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Stages and evaluation — the 9-row sign-off table on Prosthodontics/
/// Complete Denture (`diagnosis_instructor_signature` plus a
/// `stage_{key}_{signature,date,grade}` triple per stage), added
/// 2026-08-29 by request: this table is where the supervisor-only
/// signature/date/grade fields actually live, and it wasn't rendered on
/// Flutter at all before (`CaseSheetFormSchema.stages` was parsed but
/// never displayed — see its own doc comment) even though the permission
/// model (`CaseSheetSupervisorFields::stageFields()`) already reserved
/// every one of these cells for staff. A vertical card-per-stage layout,
/// not `SectionedForm.vue`'s wide HTML table — three columns of text
/// input don't fit a phone screen without cramming or horizontal scroll,
/// and this form has no other table-shaped field that would set a
/// precedent to match.
class _StageEvaluationTable extends StatelessWidget {
  const _StageEvaluationTable({required this.stages, required this.state});
  final List<Map<String, dynamic>> stages;
  final DynamicSectionFormState state;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(state.t['caseSheetForm.stagesEvaluationHeading']!, style: Theme.of(context).textTheme.titleMedium),
            for (final stage in stages) _StageRow(stage: stage, state: state),
          ],
        ),
      ),
    );
  }
}

class _StageRow extends StatefulWidget {
  const _StageRow({required this.stage, required this.state});
  final Map<String, dynamic> stage;
  final DynamicSectionFormState state;

  @override
  State<_StageRow> createState() => _StageRowState();
}

class _StageRowState extends State<_StageRow> {
  @override
  Widget build(BuildContext context) {
    final key = widget.stage['key'] as String;
    final label = widget.stage['label'] as String? ?? key;
    final note = widget.stage['note'] as String?;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (note != null) Text(note, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _StageSignatureField(stageKey: key, state: widget.state)),
              const SizedBox(width: 8),
              // `onChanged` forces this row to rebuild so
              // `_StageSignatureField` re-checks "grade + date filled" —
              // otherwise a sibling widget's own local setState() (or, for
              // the grade field below, none at all previously) never
              // reached it. See that field's matching comment.
              Expanded(child: _StageDateField(stageKey: key, state: widget.state, onChanged: () => setState(() {}))),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: widget.state._controllers['stage_${key}_grade'],
                  enabled: !widget.state.stageFieldDisabled(key, 'grade'),
                  style: const TextStyle(fontSize: 13),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: const [NumericGradeFormatter()],
                  decoration: InputDecoration(labelText: widget.state.t['caseSheetForm.gradeLabel'], hintText: '9', isDense: true, border: const OutlineInputBorder()),
                  onChanged: (v) => setState(() => widget.state._values['stage_${key}_grade'] = v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Same auto-captured signature as `_SignatureField` above, just keyed by
/// the stage table's own `stage_{key}_signature` naming — mirrors
/// `SectionedForm.vue`'s matching stage-table `<td>` branch.
class _StageSignatureField extends StatefulWidget {
  const _StageSignatureField({required this.stageKey, required this.state});
  final String stageKey;
  final DynamicSectionFormState state;

  @override
  State<_StageSignatureField> createState() => _StageSignatureFieldState();
}

class _StageSignatureFieldState extends State<_StageSignatureField> {
  static const _sentinel = '__SIGN__';
  String get _formKey => 'stage_${widget.stageKey}_signature';

  /// "يجب ان يملئ حقل الدرجة والتاريخ حتى يوقع" (2026-08-30) — mirrors
  /// `SectionedForm.vue`'s matching `stageReadyToSign()`; enforced again,
  /// robustly, server-side in `App\Support\CaseSheetSignatures` (this is
  /// only the client-side convenience). Relies on `_StageRow` rebuilding
  /// this widget whenever the grade/date siblings change — see that
  /// widget's matching comment.
  bool get _readyToSign {
    final grade = (widget.state._values['stage_${widget.stageKey}_grade'] as String? ?? '').trim();
    final date = (widget.state._values['stage_${widget.stageKey}_date'] as String? ?? '').trim();
    return grade.isNotEmpty && date.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.state._values[_formKey] as String? ?? '';
    final disabled = widget.state.stageFieldDisabled(widget.stageKey, 'signature');

    if (value.isNotEmpty && value != _sentinel) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          border: Border.all(color: Colors.green.shade200),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(value, style: TextStyle(fontSize: 12, color: Colors.green.shade800)),
      );
    }

    if (value == _sentinel) {
      return Row(children: [
        Expanded(child: Text(widget.state.t['caseSheetForm.stageSignPendingNote']!, style: TextStyle(fontSize: 11, color: Colors.indigo.shade800))),
        IconButton(
          icon: const Icon(Icons.close, size: 16),
          onPressed: () => setState(() => widget.state._values[_formKey] = ''),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ]);
    }

    final readyToSign = _readyToSign;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton(
          onPressed: (disabled || !readyToSign) ? null : () => setState(() => widget.state._values[_formKey] = _sentinel),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
          child: Text(widget.state.t['caseSheetForm.signButton']!, style: const TextStyle(fontSize: 12)),
        ),
        if (!disabled && !readyToSign)
          Text(widget.state.t['caseSheetForm.completeGradeDateFirst']!, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ],
    );
  }
}

class _StageDateField extends StatefulWidget {
  const _StageDateField({required this.stageKey, required this.state, this.onChanged});
  final String stageKey;
  final DynamicSectionFormState state;
  final VoidCallback? onChanged;

  @override
  State<_StageDateField> createState() => _StageDateFieldState();
}

class _StageDateFieldState extends State<_StageDateField> {
  String get _formKey => 'stage_${widget.stageKey}_date';

  @override
  Widget build(BuildContext context) {
    final value = widget.state._values[_formKey] as String? ?? '';
    final disabled = widget.state.stageFieldDisabled(widget.stageKey, 'date');
    return InkWell(
      onTap: disabled ? null : () => _pick(value),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: widget.state.t['caseSheetForm.dateLabel'],
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today, size: 16),
        ),
        child: Text(value.isEmpty ? '—' : value, style: const TextStyle(fontSize: 13)),
      ),
    );
  }

  Future<void> _pick(String current) async {
    final initial = DateTime.tryParse(current) ?? DateTime.now();
    final picked = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(1950), lastDate: DateTime(2100));
    if (picked != null) {
      setState(() => widget.state._values[_formKey] = DateFormat('yyyy-MM-dd').format(picked));
      widget.onChanged?.call();
    }
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section, required this.state});
  final CaseSheetSection section;
  final DynamicSectionFormState state;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(section.title, style: Theme.of(context).textTheme.titleMedium),
            if (section.note != null) ...[
              const SizedBox(height: 4),
              Text(section.note!, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            for (final field in section.fields) Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _FieldWidget(field: field, state: state),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live preview of the same anatomical dental-arch SVG the printed
/// document shows (`buildProsthodonticsDentalArchSvg`, also used by
/// `case_sheet_print_pdf.dart` and the web `prosthodontics-dental-arch.blade.php`
/// partial) — added inline in the editable form too (by request, "كيس شيت
/// الطالب لا يظهر مخطط الاسنان svg"), so a student sees the same coloured
/// chart while filling the sheet, not only after printing. Reads straight
/// from `state._values` (the "Missing Teeth"/"Caries teeth" quadrant
/// pickers in "B- Intraoral Examination" above), converted to FDI the same
/// way `CaseSheetPrintRenderer::prosthodonticsDentalArch()` does —
/// `_QuadrantTeethFieldWidgetState` routes its `onChanged` through this
/// state's own `setState` (not just its own) specifically so toggling a
/// tooth there rebuilds this preview live.
class _ProsthodonticsDentalArchPreview extends StatelessWidget {
  const _ProsthodonticsDentalArchPreview({required this.state});
  final DynamicSectionFormState state;

  @override
  Widget build(BuildContext context) {
    final missing = quadrantCodesToFdi(state._values['missing_teeth'] as String? ?? '');
    final caries = quadrantCodesToFdi(state._values['caries_teeth'] as String? ?? '');
    final svg = buildProsthodonticsDentalArchSvg(missingFdi: missing, cariousFdi: caries);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(state.t['caseSheetForm.dentalArchHeading']!, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Center(child: SizedBox(width: 220, child: SvgPicture.string(svg))),
          ],
        ),
      ),
    );
  }
}

class _FieldWidget extends StatelessWidget {
  const _FieldWidget({required this.field, required this.state});
  final CaseSheetField field;
  final DynamicSectionFormState state;

  @override
  Widget build(BuildContext context) {
    if (!field.isSupported) return _UnsupportedField(field: field, state: state);

    switch (field.type) {
      case 'boolean':
        return _BooleanField(field: field, state: state);
      case 'select':
        return _SelectField(field: field, state: state);
      case 'radio':
        return _RadioField(field: field, state: state);
      case 'checkboxes':
        return _CheckboxesField(field: field, state: state);
      case 'date':
        return _DateField(field: field, state: state);
      case 'time':
        return _TimeField(field: field, state: state);
      case 'textarea':
        return _TextField(field: field, state: state, multiline: true);
      case 'teeth':
        return _QuadrantTeethFieldWidget(field: field, state: state);
      case 'dental_chart':
        return _DentalChartFieldWidget(field: field, state: state);
      case 'endodontics':
        return _EndodonticsFieldWidget(field: field, state: state);
      case 'extraoral_exam':
        return _ExtraoralExamFieldWidget(field: field, state: state);
      case 'history_complaint':
        return _HistoryComplaintFieldWidget(field: field, state: state);
      case 'pmh_checklist':
        return _PmhChecklistFieldWidget(field: field, state: state);
      case 'surgical_history':
        return _SurgicalHistoryFieldWidget(field: field, state: state);
      case 'family_history':
        return _FamilyHistoryFieldWidget(field: field, state: state);
      case 'social_history':
        return _SocialHistoryFieldWidget(field: field, state: state);
      case 'teeth_squares_grid':
        return _TeethSquaresGridFieldWidget(field: field, state: state);
      case 'quadrant_repeater':
        return _QuadrantRepeaterFieldWidget(field: field, state: state);
      case 'signature':
        return _SignatureField(field: field, state: state);
      default: // text, number, decimal
        return _TextField(field: field, state: state, multiline: false);
    }
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.field});
  final CaseSheetField field;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(
        TextSpan(
          text: field.label,
          style: Theme.of(context).textTheme.labelLarge,
          children: field.required ? const [TextSpan(text: ' *', style: TextStyle(color: Colors.red))] : null,
        ),
      ),
    );
  }
}

/// Auto-captured signature (2026-08-30, by request) — mirrors
/// `SectionedForm.vue`'s matching `field.type === 'signature'` branch:
/// once signed, `App\Support\CaseSheetSignatures` immutably stamps the
/// real signer + timestamp server-side, so this only ever shows a
/// "توقيع" button (unsigned), a pending state (sentinel sent, not yet
/// saved), or the stamped read-only text (signed) — never a free-text
/// input.
class _SignatureField extends StatefulWidget {
  const _SignatureField({required this.field, required this.state});
  final CaseSheetField field;
  final DynamicSectionFormState state;

  @override
  State<_SignatureField> createState() => _SignatureFieldState();
}

class _SignatureFieldState extends State<_SignatureField> {
  static const _sentinel = '__SIGN__';

  @override
  Widget build(BuildContext context) {
    final value = widget.state._values[widget.field.formKey] as String? ?? '';
    final disabled = widget.state.fieldDisabled(widget.field);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(field: widget.field),
        if (value.isNotEmpty && value != _sentinel)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              border: Border.all(color: Colors.green.shade200),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(children: [
              Icon(Icons.verified, size: 16, color: Colors.green.shade700),
              const SizedBox(width: 6),
              Expanded(child: Text(value, style: TextStyle(color: Colors.green.shade800))),
            ]),
          )
        else if (value == _sentinel)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              border: Border.all(color: Colors.indigo.shade200),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(children: [
              Expanded(child: Text(widget.state.t['caseSheetForm.willBeRecordedNote']!, style: TextStyle(color: Colors.indigo.shade800))),
              TextButton(
                onPressed: () => setState(() => widget.state._values[widget.field.formKey] = ''),
                child: Text(widget.state.t['caseSheetForm.cancelAction']!),
              ),
            ]),
          )
        else
          OutlinedButton.icon(
            onPressed: disabled ? null : () => setState(() => widget.state._values[widget.field.formKey] = _sentinel),
            icon: const Icon(Icons.draw, size: 18),
            label: Text(widget.state.t['caseSheetForm.signButton']!),
          ),
      ],
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({required this.field, required this.state, required this.multiline});
  final CaseSheetField field;
  final DynamicSectionFormState state;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(field: field),
        TextFormField(
          controller: state._controllers[field.formKey],
          enabled: !state.fieldDisabled(field),
          maxLines: multiline ? 3 : 1,
          keyboardType: field.type == 'number'
              ? TextInputType.number
              : field.type == 'decimal'
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
          inputFormatters: field.type == 'number' || field.type == 'decimal' ? [NumericGradeFormatter(decimal: field.type == 'decimal')] : null,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            isDense: true,
            helperText: field.help,
          ),
          validator: field.required ? (v) => (v == null || v.trim().isEmpty) ? state.t['caseSheetForm.requiredField'] : null : null,
          onChanged: (v) => state._values[field.formKey] = v,
        ),
      ],
    );
  }
}

class _BooleanField extends StatefulWidget {
  const _BooleanField({required this.field, required this.state});
  final CaseSheetField field;
  final DynamicSectionFormState state;

  @override
  State<_BooleanField> createState() => _BooleanFieldState();
}

class _BooleanFieldState extends State<_BooleanField> {
  @override
  Widget build(BuildContext context) {
    final value = widget.state._values[widget.field.formKey] as bool? ?? false;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(widget.field.label),
      value: value,
      onChanged: widget.state.fieldDisabled(widget.field)
          ? null
          : (v) => setState(() => widget.state._values[widget.field.formKey] = v),
    );
  }
}

class _SelectField extends StatefulWidget {
  const _SelectField({required this.field, required this.state});
  final CaseSheetField field;
  final DynamicSectionFormState state;

  @override
  State<_SelectField> createState() => _SelectFieldState();
}

class _SelectFieldState extends State<_SelectField> {
  @override
  Widget build(BuildContext context) {
    final value = widget.state._values[widget.field.formKey] as String?;
    final validValue = widget.field.options.any((o) => o.value == value) ? value : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(field: widget.field),
        DropdownButtonFormField<String>(
          initialValue: validValue,
          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
          items: [
            DropdownMenuItem(value: null, child: Text(widget.state.t['caseSheetForm.selectOptionPlaceholder']!)),
            for (final o in widget.field.options) DropdownMenuItem(value: o.value, child: Text(o.label)),
          ],
          onChanged: widget.state.fieldDisabled(widget.field)
              ? null
              : (v) => setState(() => widget.state._values[widget.field.formKey] = v ?? ''),
          validator: widget.field.required ? (v) => (v == null || v.isEmpty) ? widget.state.t['caseSheetForm.requiredField'] : null : null,
        ),
      ],
    );
  }
}

class _RadioField extends StatefulWidget {
  const _RadioField({required this.field, required this.state});
  final CaseSheetField field;
  final DynamicSectionFormState state;

  @override
  State<_RadioField> createState() => _RadioFieldState();
}

class _RadioFieldState extends State<_RadioField> {
  @override
  Widget build(BuildContext context) {
    final value = widget.state._values[widget.field.formKey] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(field: widget.field),
        RadioGroup<String>(
          groupValue: value,
          onChanged: (v) {
            if (widget.state.fieldDisabled(widget.field)) return;
            setState(() => widget.state._values[widget.field.formKey] = v ?? '');
          },
          child: Wrap(
            spacing: 12,
            children: [
              for (final o in widget.field.options)
                InkWell(
                  onTap: widget.state.fieldDisabled(widget.field)
                      ? null
                      : () => setState(() => widget.state._values[widget.field.formKey] = o.value),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Radio<String>(value: o.value),
                      Text(o.label),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CheckboxesField extends StatefulWidget {
  const _CheckboxesField({required this.field, required this.state});
  final CaseSheetField field;
  final DynamicSectionFormState state;

  @override
  State<_CheckboxesField> createState() => _CheckboxesFieldState();
}

class _CheckboxesFieldState extends State<_CheckboxesField> {
  @override
  Widget build(BuildContext context) {
    final value = (widget.state._values[widget.field.formKey] as List<String>? ?? []);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(field: widget.field),
        Wrap(
          spacing: 4,
          children: [
            for (final o in widget.field.options)
              FilterChip(
                label: Text(o.label),
                selected: value.contains(o.value),
                onSelected: widget.state.fieldDisabled(widget.field)
                    ? null
                    : (selected) => setState(() {
                          final next = List<String>.from(value);
                          selected ? next.add(o.value) : next.remove(o.value);
                          widget.state._values[widget.field.formKey] = next;
                        }),
              ),
          ],
        ),
      ],
    );
  }
}

class _DateField extends StatefulWidget {
  const _DateField({required this.field, required this.state});
  final CaseSheetField field;
  final DynamicSectionFormState state;

  @override
  State<_DateField> createState() => _DateFieldState();
}

class _DateFieldState extends State<_DateField> {
  @override
  Widget build(BuildContext context) {
    final value = widget.state._values[widget.field.formKey] as String? ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(field: widget.field),
        InkWell(
          onTap: widget.state.fieldDisabled(widget.field) ? null : () => _pick(context, value),
          child: InputDecorator(
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, suffixIcon: Icon(Icons.calendar_today, size: 18)),
            child: Text(value.isEmpty ? widget.state.t['caseSheetForm.selectDatePlaceholder']! : value),
          ),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context, String current) async {
    final initial = DateTime.tryParse(current) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1950),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => widget.state._values[widget.field.formKey] = DateFormat('yyyy-MM-dd').format(picked));
    }
  }
}

class _TimeField extends StatefulWidget {
  const _TimeField({required this.field, required this.state});
  final CaseSheetField field;
  final DynamicSectionFormState state;

  @override
  State<_TimeField> createState() => _TimeFieldState();
}

class _TimeFieldState extends State<_TimeField> {
  @override
  Widget build(BuildContext context) {
    final value = widget.state._values[widget.field.formKey] as String? ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(field: widget.field),
        InkWell(
          onTap: widget.state.fieldDisabled(widget.field) ? null : () => _pick(context, value),
          child: InputDecorator(
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, suffixIcon: Icon(Icons.access_time, size: 18)),
            child: Text(value.isEmpty ? widget.state.t['caseSheetForm.selectTimePlaceholder']! : value),
          ),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context, String current) async {
    final parts = current.split(':');
    final initial = parts.length == 2
        ? TimeOfDay(hour: int.tryParse(parts[0]) ?? 0, minute: int.tryParse(parts[1]) ?? 0)
        : TimeOfDay.now();
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      final h = picked.hour.toString().padLeft(2, '0');
      final m = picked.minute.toString().padLeft(2, '0');
      setState(() => widget.state._values[widget.field.formKey] = '$h:$m');
    }
  }
}

class _QuadrantTeethFieldWidget extends StatefulWidget {
  const _QuadrantTeethFieldWidget({required this.field, required this.state});
  final CaseSheetField field;
  final DynamicSectionFormState state;

  @override
  State<_QuadrantTeethFieldWidget> createState() => _QuadrantTeethFieldWidgetState();
}

class _QuadrantTeethFieldWidgetState extends State<_QuadrantTeethFieldWidget> {
  @override
  Widget build(BuildContext context) {
    final value = widget.state._values[widget.field.formKey] as String? ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(field: widget.field),
        QuadrantTeethField(
          value: value,
          readOnly: widget.state.fieldDisabled(widget.field),
          // Routed through the *parent* form's setState, not just this
          // widget's own — every other field widget in this file only
          // calls its own local setState, but `missing_teeth`/
          // `caries_teeth` specifically need to rebuild a sibling
          // (`_ProsthodonticsDentalArchPreview`), which only the parent
          // form's rebuild reaches.
          onChanged: (next) => widget.state.setState(() => widget.state._values[widget.field.formKey] = next),
        ),
      ],
    );
  }
}

class _ExtraoralExamFieldWidget extends StatefulWidget {
  const _ExtraoralExamFieldWidget({required this.field, required this.state});
  final CaseSheetField field;
  final DynamicSectionFormState state;

  @override
  State<_ExtraoralExamFieldWidget> createState() => _ExtraoralExamFieldWidgetState();
}

class _ExtraoralExamFieldWidgetState extends State<_ExtraoralExamFieldWidget> {
  @override
  Widget build(BuildContext context) {
    final value = widget.state._values[widget.field.formKey] as Map<String, dynamic>? ?? const {};
    // No `_FieldLabel` here, matching `_EndodonticsFieldWidget` — this
    // composite's own internal headings ("Muscle tenderness", "Head
    // pain-location diagrams", …) already label its sub-sections, and the
    // schema's own field label ("Extraoral / Intraoral Examination") is
    // already shown by the section card title above it.
    return ExtraoralIntraoralExamField(
      value: value,
      readOnly: widget.state.fieldDisabled(widget.field),
      onChanged: (next) => setState(() => widget.state._values[widget.field.formKey] = next),
    );
  }
}

class _HistoryComplaintFieldWidget extends StatefulWidget {
  const _HistoryComplaintFieldWidget({required this.field, required this.state});
  final CaseSheetField field;
  final DynamicSectionFormState state;

  @override
  State<_HistoryComplaintFieldWidget> createState() => _HistoryComplaintFieldWidgetState();
}

class _HistoryComplaintFieldWidgetState extends State<_HistoryComplaintFieldWidget> {
  @override
  Widget build(BuildContext context) {
    final value = widget.state._values[widget.field.formKey] as Map<String, dynamic>? ?? const {};
    // No `_FieldLabel` — matches `_ExtraoralExamFieldWidget`: the schema's
    // own field label is already shown by the section card title above it.
    return HistoryOfComplaintField(
      value: value,
      readOnly: widget.state.fieldDisabled(widget.field),
      onChanged: (next) => setState(() => widget.state._values[widget.field.formKey] = next),
    );
  }
}

class _PmhChecklistFieldWidget extends StatefulWidget {
  const _PmhChecklistFieldWidget({required this.field, required this.state});
  final CaseSheetField field;
  final DynamicSectionFormState state;

  @override
  State<_PmhChecklistFieldWidget> createState() => _PmhChecklistFieldWidgetState();
}

class _PmhChecklistFieldWidgetState extends State<_PmhChecklistFieldWidget> {
  @override
  Widget build(BuildContext context) {
    final value = widget.state._values[widget.field.formKey] as Map<String, dynamic>? ?? const {};
    // PMH's own `options` are `{key, label}` pairs (see `App\Support\
    // OralMedicineForm`), not the `{value, label}` shape
    // `CaseSheetField.options` assumes for select/radio/checkboxes — read
    // the raw list directly rather than through that getter.
    final items = (widget.field.raw['options'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((o) => (o['key'] as String, o['label'] as String? ?? o['key'] as String))
        .toList();
    return ValueDetailsChecklistField(
      value: value,
      items: items,
      readOnly: widget.state.fieldDisabled(widget.field),
      onChanged: (next) => setState(() => widget.state._values[widget.field.formKey] = next),
    );
  }
}

class _TeethSquaresGridFieldWidget extends StatefulWidget {
  const _TeethSquaresGridFieldWidget({required this.field, required this.state});
  final CaseSheetField field;
  final DynamicSectionFormState state;

  @override
  State<_TeethSquaresGridFieldWidget> createState() => _TeethSquaresGridFieldWidgetState();
}

class _TeethSquaresGridFieldWidgetState extends State<_TeethSquaresGridFieldWidget> {
  @override
  Widget build(BuildContext context) {
    final value = widget.state._values[widget.field.formKey] as Map<String, dynamic>? ?? const {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(field: widget.field),
        TeethSquaresGridField(
          value: value,
          readOnly: widget.state.fieldDisabled(widget.field),
          onChanged: (next) => setState(() => widget.state._values[widget.field.formKey] = next),
        ),
      ],
    );
  }
}

class _QuadrantRepeaterFieldWidget extends StatefulWidget {
  const _QuadrantRepeaterFieldWidget({required this.field, required this.state});
  final CaseSheetField field;
  final DynamicSectionFormState state;

  @override
  State<_QuadrantRepeaterFieldWidget> createState() => _QuadrantRepeaterFieldWidgetState();
}

class _QuadrantRepeaterFieldWidgetState extends State<_QuadrantRepeaterFieldWidget> {
  @override
  Widget build(BuildContext context) {
    final value = widget.state._values[widget.field.formKey] as Map<String, dynamic>? ?? const {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(field: widget.field),
        QuadrantRepeaterField(
          value: value,
          readOnly: widget.state.fieldDisabled(widget.field),
          itemLabel: widget.field.itemLabel ?? 'Item',
          infoLabel: widget.field.infoLabel ?? 'Information',
          onChanged: (next) => setState(() => widget.state._values[widget.field.formKey] = next),
        ),
      ],
    );
  }
}

class _SurgicalHistoryFieldWidget extends StatefulWidget {
  const _SurgicalHistoryFieldWidget({required this.field, required this.state});
  final CaseSheetField field;
  final DynamicSectionFormState state;

  @override
  State<_SurgicalHistoryFieldWidget> createState() => _SurgicalHistoryFieldWidgetState();
}

class _SurgicalHistoryFieldWidgetState extends State<_SurgicalHistoryFieldWidget> {
  @override
  Widget build(BuildContext context) {
    final value = widget.state._values[widget.field.formKey] as Map<String, dynamic>? ?? const {};
    return SurgicalHistoryField(
      value: value,
      readOnly: widget.state.fieldDisabled(widget.field),
      onChanged: (next) => setState(() => widget.state._values[widget.field.formKey] = next),
    );
  }
}

class _FamilyHistoryFieldWidget extends StatefulWidget {
  const _FamilyHistoryFieldWidget({required this.field, required this.state});
  final CaseSheetField field;
  final DynamicSectionFormState state;

  @override
  State<_FamilyHistoryFieldWidget> createState() => _FamilyHistoryFieldWidgetState();
}

class _FamilyHistoryFieldWidgetState extends State<_FamilyHistoryFieldWidget> {
  @override
  Widget build(BuildContext context) {
    final value = widget.state._values[widget.field.formKey] as Map<String, dynamic>? ?? const {};
    return FamilyHistoryField(
      value: value,
      readOnly: widget.state.fieldDisabled(widget.field),
      onChanged: (next) => setState(() => widget.state._values[widget.field.formKey] = next),
    );
  }
}

class _SocialHistoryFieldWidget extends StatefulWidget {
  const _SocialHistoryFieldWidget({required this.field, required this.state});
  final CaseSheetField field;
  final DynamicSectionFormState state;

  @override
  State<_SocialHistoryFieldWidget> createState() => _SocialHistoryFieldWidgetState();
}

class _SocialHistoryFieldWidgetState extends State<_SocialHistoryFieldWidget> {
  @override
  Widget build(BuildContext context) {
    final value = widget.state._values[widget.field.formKey] as Map<String, dynamic>? ?? const {};
    return SocialHistoryField(
      value: value,
      readOnly: widget.state.fieldDisabled(widget.field),
      onChanged: (next) => setState(() => widget.state._values[widget.field.formKey] = next),
    );
  }
}

class _DentalChartFieldWidget extends StatefulWidget {
  const _DentalChartFieldWidget({required this.field, required this.state});
  final CaseSheetField field;
  final DynamicSectionFormState state;

  @override
  State<_DentalChartFieldWidget> createState() => _DentalChartFieldWidgetState();
}

class _DentalChartFieldWidgetState extends State<_DentalChartFieldWidget> {
  @override
  Widget build(BuildContext context) {
    final value = widget.state._values[widget.field.formKey] as List<dynamic>? ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(field: widget.field),
        // Not `IgnorePointer` — see `ToothOdontogramField.readOnly`'s doc
        // comment for why that broke the arch rows' horizontal scroll for
        // a read-only viewer (2026-08-29 fix).
        ToothOdontogramField(
          value: value,
          readOnly: widget.state.fieldDisabled(widget.field),
          onChanged: (next) => setState(() => widget.state._values[widget.field.formKey] = next),
        ),
      ],
    );
  }
}

class _EndodonticsFieldWidget extends StatefulWidget {
  const _EndodonticsFieldWidget({required this.field, required this.state});
  final CaseSheetField field;
  final DynamicSectionFormState state;

  @override
  State<_EndodonticsFieldWidget> createState() => _EndodonticsFieldWidgetState();
}

class _EndodonticsFieldWidgetState extends State<_EndodonticsFieldWidget> {
  @override
  Widget build(BuildContext context) {
    final value = widget.state._values[widget.field.formKey] as Map<String, dynamic>? ?? const {};
    // No `_FieldLabel` here, unlike the other field widgets — the card's
    // own header row ("سجل علاج عصب الأسنان" + the enable toggle) already
    // serves as the label, and showing both would just duplicate it.
    // Not `IgnorePointer` — see `EndodonticsField.readOnly`'s doc comment
    // for why that broke `EndodonticsCanalTable`'s horizontal scroll for a
    // read-only viewer (2026-08-29 fix, same bug as the dental odontogram).
    return EndodonticsField(
      value: value,
      readOnly: widget.state.fieldDisabled(widget.field),
      onChanged: (next) => setState(() => widget.state._values[widget.field.formKey] = next),
    );
  }
}

/// Every field type this generic form doesn't render an editable control
/// for yet (Oral Medicine's composites, Orthodontics' grid/repeaters,
/// `lookup`, `file`, …) — shown so the field
/// is at least visible and its raw value inspectable, never silently
/// hidden, but never touched by `buildSubmitPayload()` either (see the
/// class doc on `DynamicSectionForm`).
class _UnsupportedField extends StatelessWidget {
  const _UnsupportedField({required this.field, required this.state});
  final CaseSheetField field;
  final DynamicSectionFormState state;

  @override
  Widget build(BuildContext context) {
    dynamic raw;
    final group = field.group;
    if (group != null) {
      raw = state._groupOriginals[group]?[field.key];
    } else {
      raw = state.widget.record[field.key];
    }
    final preview = raw == null || (raw is String && raw.isEmpty) ? state.t['caseSheetForm.noDataPlaceholder']! : raw.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(field: field),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(4)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(trf(state.t['caseSheetForm.notSupportedYetTemplate']!, {'type': field.type}), style: const TextStyle(color: Colors.orange, fontSize: 12)),
              const SizedBox(height: 4),
              Text(preview, maxLines: 3, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }
}

/// Grades (and number/decimal fields) take digits only: Arabic-Indic and
/// Persian digits become Western ones, `٫`/`,` become `.`, and anything
/// else is dropped — mirrors resources/js/numericGrade.js on the web.
class NumericGradeFormatter extends TextInputFormatter {
  const NumericGradeFormatter({this.decimal = true});

  final bool decimal;

  static String clean(String input, {bool decimal = true}) {
    final buf = StringBuffer();
    var seenDot = false;
    for (final r in input.runes) {
      if (r >= 0x0660 && r <= 0x0669) {
        buf.writeCharCode(0x30 + r - 0x0660);
      } else if (r >= 0x06F0 && r <= 0x06F9) {
        buf.writeCharCode(0x30 + r - 0x06F0);
      } else if (r >= 0x30 && r <= 0x39) {
        buf.writeCharCode(r);
      } else if (decimal && !seenDot && (r == 0x2E || r == 0x066B || r == 0x2C)) {
        buf.write('.');
        seenDot = true;
      }
    }
    return buf.toString();
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = clean(newValue.text, decimal: decimal);
    if (text == newValue.text) return newValue;
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
