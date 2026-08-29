import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../dental_chart/presentation/tooth_odontogram_field.dart';
import '../../endodontics/presentation/endodontics_field.dart';
import '../../perio_chart/presentation/perio_chart_groups_field.dart';
import '../domain/case_sheet_field.dart';
import '../domain/case_sheet_form_schema.dart';

/// Renders any of the 8 case-sheet resources from its
/// `CaseSheetFormSchema` — one generic widget instead of 12 bespoke
/// screens, mirroring `resources/js/Pages/Specialty/SectionedForm.vue`
/// on the web side (see flutter_app/README.md §4).
///
/// Supports: text, textarea, number, decimal, date, time, select, radio,
/// checkboxes, boolean, `teeth` (as a plain comma-list text field — the
/// original's visual FDI-cross picker isn't ported yet, same
/// "incrementally after" scope the README already calls out),
/// `dental_chart` (the full odontogram, see `ToothOdontogramField`), and
/// `endodontics` (the Operative sheet's root-canal treatment record, see
/// `EndodonticsField`). A resource's `chartGroups`/`chartField`
/// (periodontal-charts only, today — the BOP/PPD/CAL per-tooth tables)
/// are rendered separately, after every `sections()` card, via
/// `PerioChartGroupsField` — they're not `sections()` fields at all, so
/// they sit outside the field-type switch below entirely. Every other
/// unhandled type (Oral Medicine's six JSON-blob composites,
/// Orthodontics' teeth-squares-grid/quadrant-repeater) renders as a
/// read-only placeholder instead of an editable control — and,
/// critically, is never touched by `buildSubmitPayload()`, so saving never
/// silently drops data this form can't edit yet. For a *grouped* field
/// (e.g. one subkey inside Orthodontics' `examination_data` blob) this
/// means the group is reassembled from a copy of its original decoded
/// object with only the supported subkeys overwritten — an unsupported
/// sibling subkey inside the same JSON blob survives a save untouched
/// rather than being wiped because this form didn't render a control for
/// it.
class DynamicSectionForm extends StatefulWidget {
  const DynamicSectionForm({
    super.key,
    required this.schema,
    required this.record,
    required this.readonly,
    required this.onSubmit,
    this.supervisorEditableFields = const [],
  });

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
  }

  bool _isTextControlled(String type) =>
      const {'text', 'textarea', 'number', 'decimal', 'teeth'}.contains(type);

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
      final value = _values[field.formKey];

      if (field.group != null) {
        groupBuckets[field.group!]![field.key] = value;
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

    return payload;
  }

  /// A field stays locked under `readonly` unless it's one of this
  /// viewer's own supervisor-editable fields (empty for a doctor, so this
  /// is a no-op for them). Grouped subkeys aren't part of any resource's
  /// supervisor-field list today, so `field.key` (not `formKey`) is the
  /// right comparison — mirrors `SectionedForm.vue`'s `fieldDisabled()`.
  bool fieldDisabled(CaseSheetField field) =>
      widget.readonly && !widget.supervisorEditableFields.contains(field.key);

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

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final section in widget.schema.sections) _SectionCard(section: section, state: this),
          if (widget.schema.chartGroups.isNotEmpty)
            PerioChartGroupsField(
              groups: widget.schema.chartGroups,
              value: _chartValue,
              readOnly: widget.readonly,
              onChanged: (next) => setState(() => _chartValue = next),
            ),
          if (canSubmit) ...[
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('حفظ'),
            ),
          ],
        ],
      ),
    );
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
      case 'dental_chart':
        return _DentalChartFieldWidget(field: field, state: state);
      case 'endodontics':
        return _EndodonticsFieldWidget(field: field, state: state);
      default: // text, number, decimal, teeth
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
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            isDense: true,
            helperText: field.help,
            hintText: field.type == 'teeth' ? 'مثال: UR8, UL1' : null,
          ),
          validator: field.required ? (v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null : null,
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
            const DropdownMenuItem(value: null, child: Text('— اختر —')),
            for (final o in widget.field.options) DropdownMenuItem(value: o.value, child: Text(o.label)),
          ],
          onChanged: widget.state.fieldDisabled(widget.field)
              ? null
              : (v) => setState(() => widget.state._values[widget.field.formKey] = v ?? ''),
          validator: widget.field.required ? (v) => (v == null || v.isEmpty) ? 'هذا الحقل مطلوب' : null : null,
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
            child: Text(value.isEmpty ? '— اختر تاريخًا —' : value),
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
            child: Text(value.isEmpty ? '— اختر وقتًا —' : value),
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
    final preview = raw == null || (raw is String && raw.isEmpty) ? '(لا توجد بيانات)' : raw.toString();

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
              Text('غير مدعوم في التطبيق بعد (${field.type})', style: const TextStyle(color: Colors.orange, fontSize: 12)),
              const SizedBox(height: 4),
              Text(preview, maxLines: 3, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }
}
