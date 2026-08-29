import 'package:flutter/material.dart';

import 'endodontics_canal_table.dart';

/// Port of `resources/js/Components/EndodonticsSection.vue` +
/// `EndodonticsCanalTable.vue` — the `endodontics_data` field on the
/// Operative case sheet (`type: 'endodontics'` in `App\Support\
/// OperativeForm::sections()`). Every JSON key below matches the web
/// component's own `endodontics_data` shape exactly (`tooth_no`,
/// `canal_count`, `diagnosis[]`, `first_visit[]`,
/// `first_visit_data.{canal}`, `second_visit_data.{canal}`,
/// `technique[]`, `third_visit_data.{...}`, `signature`) — read from that
/// source, not guessed.
///
/// **Deliberately not ported**, matching the web component's own scope:
/// the per-visit image-upload galleries and the canvas-based signature
/// pad (a plain text field stands in for it here too, same as web).
///
/// **One deliberate behavior change from the web component**: there, the
/// enable toggle is a *computed* derived purely from
/// `Object.keys(modelValue).length > 0` — reading `EndodonticsSection.
/// vue`'s own setter shows that turning the toggle on while the record is
/// still `{}` re-emits `{}` (nothing in the setter adds a key), so the
/// getter recomputes `false` immediately and the toggle would visually
/// snap back off before a user can enter anything. This widget keeps
/// "enabled" as genuine local state instead of deriving it from map
/// emptiness on every rebuild, so turning it on for a brand-new record
/// actually stays on.
class EndodonticsField extends StatefulWidget {
  const EndodonticsField({super.key, required this.value, required this.onChanged, this.readOnly = false});

  final Map<String, dynamic> value;
  final ValueChanged<Map<String, dynamic>> onChanged;

  /// Disables every edit control in this section (the enable switch,
  /// checkboxes, choice/filter chips, text fields) — not implemented by
  /// wrapping this widget in `IgnorePointer` at the call site, which broke
  /// `EndodonticsCanalTable`'s horizontal scroll too (same bug found in
  /// `ToothOdontogramField`, see its `readOnly` doc comment — 2026-08-29).
  final bool readOnly;

  @override
  State<EndodonticsField> createState() => _EndodonticsFieldState();
}

const _diagnoses = [
  ('pulpitis', 'التهاب اللب (Pulpitis)'),
  ('acute', 'حاد (Acute)'),
  ('chronic', 'مزمن (Chronic)'),
  ('traumatic', 'رضّي (Traumatic)'),
  ('peri-apical periodontitis', 'التهاب اللثة حول الذروة'),
];

const _firstVisitSteps = [
  ('access_opening', 'فتح الوصول'),
  ('pulp_extirpation', 'استئصال اللب'),
  ('working_length_estimation', 'تقدير طول العمل'),
];

const _techniques = [
  ('conventional', 'تقليدي'),
  ('step_back', 'Step Back'),
  ('crown_down', 'Crown Down'),
  ('combination', 'مزيج'),
  ('hand', 'يدوي'),
  ('rotary', 'دوّار (Rotary)'),
];

const _canalCounts = [
  ('one', 'واحدة'),
  ('two', 'اثنتان'),
  ('three', 'ثلاث'),
  ('four', 'أربع'),
];

class _EndodonticsFieldState extends State<EndodonticsField> {
  late bool _enabled = widget.value.isNotEmpty;
  late final _toothNoController = TextEditingController(text: widget.value['tooth_no'] as String? ?? '');
  late final _masterConeNotesController =
      TextEditingController(text: _thirdVisit['master_cone_notes'] as String? ?? '');
  late final _obturationNotesController =
      TextEditingController(text: _thirdVisit['obturation_notes'] as String? ?? '');

  @override
  void dispose() {
    _toothNoController.dispose();
    _masterConeNotesController.dispose();
    _obturationNotesController.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _thirdVisit => (widget.value['third_visit_data'] as Map<String, dynamic>?) ?? {};

  void _set(String key, dynamic value) => widget.onChanged({...widget.value, key: value});

  void _setThirdVisit(String key, dynamic value) => _set('third_visit_data', {..._thirdVisit, key: value});

  void _toggleListItem(String key, String option) {
    final list = (widget.value[key] as List<dynamic>?)?.cast<String>() ?? <String>[];
    _set(key, list.contains(option) ? (list..remove(option)) : [...list, option]);
  }

  bool _isChecked(String key, String option) =>
      ((widget.value[key] as List<dynamic>?)?.cast<String>() ?? const <String>[]).contains(option);

  void _toggleEnabled(bool value) {
    setState(() => _enabled = value);
    if (!value) widget.onChanged({});
  }

  Widget _checkboxGroup(String key, List<(String, String)> options) {
    return Wrap(
      spacing: 4,
      children: [
        for (final (value, label) in options)
          FilterChip(
            label: Text(label, style: const TextStyle(fontSize: 12)),
            selected: _isChecked(key, value),
            onSelected: widget.readOnly ? null : (_) => setState(() => _toggleListItem(key, value)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.medical_services_outlined, size: 18),
                const SizedBox(width: 6),
                const Expanded(child: Text('سجل علاج عصب الأسنان (Endodontics)', style: TextStyle(fontWeight: FontWeight.w600))),
                Switch(value: _enabled, onChanged: widget.readOnly ? null : _toggleEnabled),
              ],
            ),
            if (_enabled) ...[
              const Divider(),
              TextFormField(
                controller: _toothNoController,
                enabled: !widget.readOnly,
                decoration: const InputDecoration(labelText: 'رقم السن', hintText: 'مثال: 46', isDense: true, border: OutlineInputBorder()),
                onChanged: (v) => _set('tooth_no', v),
              ),
              const SizedBox(height: 12),
              const Text('عدد القنوات', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  for (final (value, label) in _canalCounts)
                    ChoiceChip(
                      label: Text(label, style: const TextStyle(fontSize: 12)),
                      selected: widget.value['canal_count'] == value,
                      onSelected: widget.readOnly ? null : (_) => setState(() => _set('canal_count', value)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('التشخيص', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              _checkboxGroup('diagnosis', _diagnoses),

              const Divider(height: 32),
              Row(
                children: const [Icon(Icons.event_available_outlined, size: 16), SizedBox(width: 4), Text('الزيارة الأولى', style: TextStyle(fontWeight: FontWeight.w600))],
              ),
              const SizedBox(height: 8),
              _checkboxGroup('first_visit', _firstVisitSteps),
              const SizedBox(height: 8),
              EndodonticsCanalTable(
                value: (widget.value['first_visit_data'] as Map<String, dynamic>?) ?? {},
                columns: const [
                  ('wl_xray', 'صورة الطول'),
                  ('initial_length', 'الطول الأولي'),
                  ('initial_size', 'المقاس الأولي'),
                  ('final_wl', 'الطول النهائي'),
                ],
                onChanged: (next) => _set('first_visit_data', next),
                readOnly: widget.readOnly,
              ),

              const Divider(height: 32),
              Row(
                children: const [Icon(Icons.event_available_outlined, size: 16), SizedBox(width: 4), Text('الزيارة الثانية — التحضير الآلي', style: TextStyle(fontWeight: FontWeight.w600))],
              ),
              const SizedBox(height: 8),
              EndodonticsCanalTable(
                value: (widget.value['second_visit_data'] as Map<String, dynamic>?) ?? {},
                columns: const [
                  ('wl', 'طول العمل'),
                  ('size', 'المقاس'),
                  ('rp', 'R.P.'),
                ],
                onChanged: (next) => _set('second_visit_data', next),
                readOnly: widget.readOnly,
              ),
              const SizedBox(height: 8),
              const Text('تقنية التحضير', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              _checkboxGroup('technique', _techniques),

              const Divider(height: 32),
              Row(
                children: const [Icon(Icons.event_available_outlined, size: 16), SizedBox(width: 4), Text('الزيارة الثالثة — الحشو النهائي', style: TextStyle(fontWeight: FontWeight.w600))],
              ),
              const SizedBox(height: 8),
              _ThirdVisitCheckRow(
                label: 'فحص المخروط الرئيسي',
                clinical: _thirdVisit['master_cone_clinical'] as bool? ?? false,
                radiographical: _thirdVisit['master_cone_radiographical'] as bool? ?? false,
                notesController: _masterConeNotesController,
                readOnly: widget.readOnly,
                onClinicalChanged: (v) => setState(() => _setThirdVisit('master_cone_clinical', v)),
                onRadiographicalChanged: (v) => setState(() => _setThirdVisit('master_cone_radiographical', v)),
                onNotesChanged: (v) => _setThirdVisit('master_cone_notes', v),
              ),
              const SizedBox(height: 8),
              _ThirdVisitCheckRow(
                label: 'فحص الحشو النهائي',
                clinical: _thirdVisit['obturation_clinical'] as bool? ?? false,
                radiographical: _thirdVisit['obturation_radiographical'] as bool? ?? false,
                notesController: _obturationNotesController,
                readOnly: widget.readOnly,
                onClinicalChanged: (v) => setState(() => _setThirdVisit('obturation_clinical', v)),
                onRadiographicalChanged: (v) => setState(() => _setThirdVisit('obturation_radiographical', v)),
                onNotesChanged: (v) => _setThirdVisit('obturation_notes', v),
              ),

              const Divider(height: 32),
              TextFormField(
                initialValue: widget.value['signature'] as String? ?? '',
                enabled: !widget.readOnly,
                decoration: const InputDecoration(labelText: 'توقيع المشرف', isDense: true, border: OutlineInputBorder()),
                onChanged: (v) => _set('signature', v),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ThirdVisitCheckRow extends StatelessWidget {
  const _ThirdVisitCheckRow({
    required this.label,
    required this.clinical,
    required this.radiographical,
    required this.notesController,
    required this.onClinicalChanged,
    required this.onRadiographicalChanged,
    required this.onNotesChanged,
    this.readOnly = false,
  });

  final String label;
  final bool clinical;
  final bool radiographical;
  final TextEditingController notesController;
  final ValueChanged<bool> onClinicalChanged;
  final ValueChanged<bool> onRadiographicalChanged;
  final ValueChanged<String> onNotesChanged;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChip(
              label: const Text('سريري', style: TextStyle(fontSize: 12)),
              selected: clinical,
              onSelected: readOnly ? null : onClinicalChanged,
            ),
            const SizedBox(width: 4),
            FilterChip(
              label: const Text('شعاعي', style: TextStyle(fontSize: 12)),
              selected: radiographical,
              onSelected: readOnly ? null : onRadiographicalChanged,
            ),
          ],
        ),
        TextFormField(
          controller: notesController,
          enabled: !readOnly,
          decoration: const InputDecoration(hintText: 'ملاحظات...', isDense: true, border: OutlineInputBorder()),
          onChanged: onNotesChanged,
        ),
      ],
    );
  }
}
