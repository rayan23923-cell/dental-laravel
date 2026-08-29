import 'package:flutter/material.dart';

/// "History of Surgical Operations or Treatments" — port of
/// `Components/SurgicalHistorySection.vue`. `extra_oral`/`intra_oral` are
/// plain "yes"/"no" strings (not the value+details pattern PMH uses,
/// confirmed against real imported data — see that component's own
/// comment), radio-selected; the rest are free text.
class SurgicalHistoryField extends StatefulWidget {
  const SurgicalHistoryField({super.key, required this.value, required this.onChanged, this.readOnly = false});

  final Map<String, dynamic> value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool readOnly;

  @override
  State<SurgicalHistoryField> createState() => _SurgicalHistoryFieldState();
}

const _surgicalYesNo = [
  ('extra_oral', 'Do you have history of Extra-oral operations'),
  ('intra_oral', 'Do you have history of Intra-oral operations'),
];

const _surgicalText = [
  ('treatment_relevant', 'Do you have treatment relevant to the chief complaint?'),
  ('operations', 'What are the operations?'),
  ('when', 'When were they?'),
];

class _SurgicalHistoryFieldState extends State<SurgicalHistoryField> {
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

  void _set(String key, dynamic value) => widget.onChanged({...widget.value, key: value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (key, label) in _surgicalYesNo)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                RadioGroup<String>(
                  groupValue: (widget.value[key] as String?) ?? 'no',
                  onChanged: (v) {
                    if (!widget.readOnly) _set(key, v);
                  },
                  child: Row(
                    children: const [
                      Radio<String>(value: 'no'),
                      Text('No'),
                      Radio<String>(value: 'yes'),
                      Text('Yes'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        for (final (key, label) in _surgicalText)
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
      ],
    );
  }
}
