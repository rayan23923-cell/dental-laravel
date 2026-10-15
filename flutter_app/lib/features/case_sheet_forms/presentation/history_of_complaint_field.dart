import 'package:flutter/material.dart';
import '../../../core/widgets/numeric_input.dart';

/// "History of the Complaint" — port of `Components/HistoryOfComplaintSection.vue`
/// + `Components/SymptomsChecklist.vue` (oral_medicine.php's 28-item
/// `$symptoms` checklist plus the six open-ended follow-up questions and a
/// 0–10 pain scale), all posted under the single `history_of_complaint`
/// JSON-blob column.
///
/// [value] keys match the web components' `modelValue` shape exactly:
/// `symptoms` (string[] of checked symptom keys), `symptom_details`
/// (`{symptomKey: {right, left, other}}` — `right`/`left` populated only
/// for a symptom with `hasSides`, `other` only for the special `other`
/// item), the six question keys in [_questions], and `pain_scale`.
class HistoryOfComplaintField extends StatefulWidget {
  const HistoryOfComplaintField({super.key, required this.value, required this.onChanged, this.readOnly = false});

  final Map<String, dynamic> value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool readOnly;

  @override
  State<HistoryOfComplaintField> createState() => _HistoryOfComplaintFieldState();
}

// Key, label, hasSides — verbatim from Components/SymptomsChecklist.vue.
const _symptoms = [
  ('headache', 'Headache', false), ('migraines', 'Migraines', true),
  ('facial_pain', 'Facial pain', true), ('neck_pain', 'Neck pain', false),
  ('jaw_pain', 'Jaw pain', true), ('jaw_clicking', 'Jaw clicking', true),
  ('nocturnal_teeth_grinding', 'Nocturnal teeth grinding', false),
  ('frequent_biting_cheek', 'Frequent biting of cheek', true),
  ('pain_when_chewing', 'Pain when chewing', true),
  ('fatigue_facial_muscles', 'Fatigue of facial muscles', true),
  ('limited_mouth_opening', 'Limited mouth opening', false),
  ('jaw_locking', 'Jaw locking', false), ('dislocation_jaw', 'Dislocation of jaw', false),
  ('ringing_ears', 'Ringing in the ears', true), ('dizziness', 'Dizziness', false),
  ('morning_head_pain', 'Morning head pain', false), ('frequent_snoring', 'Frequent Snoring', false),
  ('dry_mouth', 'Dry mouth', false), ('burning_tongue', 'Burning tongue', false),
  ('pain_swallowing', 'Pain on swallowing', false), ('sinusitis', 'Sinusitis', false),
  ('tooth_pain', 'Tooth Pain', false), ('past_broken_teeth', 'Past history of broken teeth', false),
  ('facial_asymmetry_swelling', 'Facial asymmetry or swelling', false), ('numbness', 'Numbness', false),
  ('eye_pain', 'Eye pain', false), ('throat_pain', 'Throat pain', false), ('other', 'Other', false),
];

// Key, label — verbatim from Components/HistoryOfComplaintSection.vue's QUESTIONS.
const _questions = [
  ('when_first_occurred', 'When did the pain or condition first occur?'),
  ('believed_cause', 'What do you believe is the cause of the pain or condition?'),
  ('accident', 'Did you have any accident?'),
  ('makes_worse', 'Is there anything that makes your pain or discomfort worse?'),
  ('relieves', 'Is there anything that relieves your pain or discomfort?'),
  ('other_info', 'What other information is important regarding the pain or condition?'),
];

class _HistoryOfComplaintFieldState extends State<HistoryOfComplaintField> {
  final Map<String, TextEditingController> _controllers = {};

  TextEditingController _controllerFor(String key, String initial) =>
      _controllers.putIfAbsent(key, () => TextEditingController(text: initial));

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> get _symptomsValue => List<String>.from(widget.value['symptoms'] as List? ?? const []);
  Map<String, dynamic> get _detailsValue => Map<String, dynamic>.from(widget.value['symptom_details'] as Map? ?? const {});

  bool _isChecked(String key) => _symptomsValue.contains(key);

  void _toggle(String key) {
    final list = _symptomsValue;
    widget.onChanged({...widget.value, 'symptoms': _isChecked(key) ? (list..remove(key)) : (list..add(key))});
  }

  Map<String, dynamic> _detailsFor(String key) =>
      Map<String, dynamic>.from(_detailsValue[key] as Map? ?? const {'right': '', 'left': '', 'other': ''});

  void _setDetail(String key, String part, String value) {
    final details = _detailsValue;
    details[key] = {..._detailsFor(key), part: value};
    widget.onChanged({...widget.value, 'symptom_details': details});
  }

  void _set(String key, dynamic value) => widget.onChanged({...widget.value, key: value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Do you have history of the followings associated with your CC.; please mark the applied ones:',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 8),
        for (final (key, label, hasSides) in _symptoms)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: widget.readOnly ? null : () => _toggle(key),
                  child: Row(
                    children: [
                      Checkbox(value: _isChecked(key), onChanged: widget.readOnly ? null : (_) => _toggle(key)),
                      Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                ),
                if (_isChecked(key) && hasSides)
                  Padding(
                    padding: const EdgeInsets.only(left: 40, right: 8, bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _controllerFor('${key}_right', _detailsFor(key)['right'] as String? ?? ''),
                            enabled: !widget.readOnly,
                            style: const TextStyle(fontSize: 12),
                            decoration: const InputDecoration(isDense: true, hintText: 'R', border: OutlineInputBorder()),
                            onChanged: (v) => _setDetail(key, 'right', v),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextFormField(
                            controller: _controllerFor('${key}_left', _detailsFor(key)['left'] as String? ?? ''),
                            enabled: !widget.readOnly,
                            style: const TextStyle(fontSize: 12),
                            decoration: const InputDecoration(isDense: true, hintText: 'L', border: OutlineInputBorder()),
                            onChanged: (v) => _setDetail(key, 'left', v),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_isChecked(key) && key == 'other')
                  Padding(
                    padding: const EdgeInsets.only(left: 40, right: 8, bottom: 8),
                    child: TextFormField(
                      controller: _controllerFor('${key}_other', _detailsFor(key)['other'] as String? ?? ''),
                      enabled: !widget.readOnly,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(isDense: true, hintText: 'Please specify...', border: OutlineInputBorder()),
                      onChanged: (v) => _setDetail(key, 'other', v),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        const Divider(),
        const SizedBox(height: 4),
        for (final (key, label) in _questions)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _controllerFor(key, widget.value[key] as String? ?? ''),
                  enabled: !widget.readOnly,
                  maxLines: 2,
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                  onChanged: (v) => _set(key, v),
                ),
              ],
            ),
          ),
        Text('Pain scale (0–10, 0=No pain, 10=Worst pain imaginable)', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        SizedBox(
          width: 160,
          child: TextFormField(
            controller: _controllerFor('pain_scale', widget.value['pain_scale']?.toString() ?? ''),
            enabled: !widget.readOnly,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: decimalOnly,
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
            onChanged: (v) => _set('pain_scale', v),
          ),
        ),
      ],
    );
  }
}
