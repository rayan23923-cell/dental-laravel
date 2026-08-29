import 'package:flutter/material.dart';

/// Social History — port of `Components/SocialHistorySection.vue`
/// (oral_medicine.php): marital status (radio), occupation (text),
/// tobacco use (radio) + other tobacco forms (checkboxes), packs/day,
/// quit-when, years, alcohol (radio), caffeine (checkboxes), exercise
/// (radio). Option values and the two checkbox lists (`tobacco_other`,
/// `caffeine`) match the web component's own — confirmed against the
/// original's markup and real imported data there, not re-derived here.
class SocialHistoryField extends StatefulWidget {
  const SocialHistoryField({super.key, required this.value, required this.onChanged, this.readOnly = false});

  final Map<String, dynamic> value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool readOnly;

  @override
  State<SocialHistoryField> createState() => _SocialHistoryFieldState();
}

class _SocialHistoryFieldState extends State<SocialHistoryField> {
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

  List<String> _listValue(String key) => List<String>.from(widget.value[key] as List? ?? const []);

  void _toggleListItem(String key, String item) {
    final list = _listValue(key);
    _set(key, list.contains(item) ? (list..remove(item)) : (list..add(item)));
  }

  Widget _radioRow(String key, List<(String, String)> options, {String? fallback}) {
    final current = (widget.value[key] as String?) ?? fallback;
    return RadioGroup<String>(
      groupValue: current,
      onChanged: (v) {
        if (!widget.readOnly) _set(key, v);
      },
      child: Wrap(
        spacing: 12,
        children: [
          for (final (val, label) in options)
            InkWell(
              onTap: widget.readOnly ? null : () => _set(key, val),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [Radio<String>(value: val), Text(label)],
              ),
            ),
        ],
      ),
    );
  }

  Widget _checkboxRow(String key, List<String> options) {
    return Wrap(
      spacing: 4,
      children: [
        for (final opt in options)
          FilterChip(
            label: Text(opt),
            selected: _listValue(key).contains(opt),
            onSelected: widget.readOnly ? null : (_) => _toggleListItem(key, opt),
          ),
      ],
    );
  }

  Widget _textField(String key, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        TextFormField(
          controller: _controllerFor(key, widget.value[key] as String? ?? ''),
          enabled: !widget.readOnly,
          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
          onChanged: (v) => _set(key, v),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Marital Status', style: Theme.of(context).textTheme.labelSmall),
        _radioRow('marital_status', const [('single', 'Single'), ('married', 'Married'), ('divorced', 'Divorced')]),
        const SizedBox(height: 12),
        _textField('occupation', "Patient's Occupation & Employer"),
        const SizedBox(height: 16),
        Text('Tobacco Use (Cigarettes)', style: Theme.of(context).textTheme.labelSmall),
        _radioRow('tobacco_cigarettes', const [('never', 'Never Smoked'), ('current', 'Current Smoker'), ('quit', 'Quit')]),
        const SizedBox(height: 10),
        Text('Other tobacco', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        _checkboxRow('tobacco_other', const ['pipe', 'cigar', 'snuff', 'chew']),
        const SizedBox(height: 16),
        _textField('packs_per_day', 'No. of packs per day'),
        const SizedBox(height: 12),
        _textField('quit_when', 'When did you quit?'),
        const SizedBox(height: 12),
        _textField('years', 'No. of years'),
        const SizedBox(height: 16),
        Text('Alcohol Use', style: Theme.of(context).textTheme.labelSmall),
        _radioRow('alcohol', const [('no', 'No'), ('yes', 'Yes')], fallback: 'no'),
        const SizedBox(height: 10),
        Text('Caffeine Intake', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        _checkboxRow('caffeine', const ['none', 'coffee', 'tea', 'soda']),
        const SizedBox(height: 16),
        Text('Regular workout exercise', style: Theme.of(context).textTheme.labelSmall),
        _radioRow('exercise', const [('yes', 'Yes'), ('no', 'No')]),
      ],
    );
  }
}
