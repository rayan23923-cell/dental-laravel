import 'package:flutter/material.dart';
import '../../../core/theme/muted_colors.dart';

/// Family History — port of `Components/FamilyHistorySection.vue`
/// (oral_medicine.php's `$family_history_items`): eight plain free-text
/// fields, one per hereditary condition — no value/details toggle here,
/// unlike Past Medical History.
class FamilyHistoryField extends StatefulWidget {
  const FamilyHistoryField({super.key, required this.value, required this.onChanged, this.readOnly = false});

  final Map<String, dynamic> value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool readOnly;

  @override
  State<FamilyHistoryField> createState() => _FamilyHistoryFieldState();
}

const _familyItems = [
  ('obesity', 'Obesity'), ('sleep_apnea', 'Sleep apnea'), ('snoring', 'Snoring'),
  ('depression', 'Depression'), ('cancer', 'Cancer'), ('cardiovascular', 'Cardiovascular Diseases'),
  ('diabetes_hormonal', 'Diabetes and Hormonal Diseases'),
  ('other_hereditary', 'Other Hereditary or family related Diseases'),
];

class _FamilyHistoryFieldState extends State<FamilyHistoryField> {
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Has any member of your family had disorders such as:', style: TextStyle(fontSize: 12, color: context.mutedText)),
        const SizedBox(height: 8),
        for (final (key, label) in _familyItems)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _controllerFor(key, widget.value[key] as String? ?? ''),
                  enabled: !widget.readOnly,
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                  onChanged: (v) => widget.onChanged({...widget.value, key: v}),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
