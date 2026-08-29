import 'package:flutter/material.dart';

import 'head_diagrams_board.dart';

/// Extraoral/Intraoral Examination — port of `Components/ExtraoralIntraoralExam.vue`
/// (itself a port of `oral_medicine.php`): a 7-muscle tenderness grid
/// (right/left text per muscle), four more right/left pairs (TMJ
/// clicking, preauricular pain, swelling, deviation on opening), plus max
/// mouth opening, facial defects and oral mucosa condition as free text,
/// and the four head pain-location diagrams (`head_diagrams`) — see
/// `HeadDiagramsBoard` for the click-to-mark mechanics.
///
/// [value] keys match the web component's `modelValue` shape exactly:
/// `muscles` (object of `{right, left}` per muscle key below),
/// `tmj_clicking`/`preauricular_pain`/`swelling`/`deviation_opening`
/// (each `{right, left}`), `max_mouth_opening`/`facial_defects`/
/// `oral_mucosa_condition` (strings), `head_diagrams` (see
/// `HeadDiagramsBoard`).
class ExtraoralIntraoralExamField extends StatefulWidget {
  const ExtraoralIntraoralExamField({super.key, required this.value, required this.onChanged, this.readOnly = false});

  final Map<String, dynamic> value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool readOnly;

  @override
  State<ExtraoralIntraoralExamField> createState() => _ExtraoralIntraoralExamFieldState();
}

const _muscles = [
  ('masseter', 'Masseter'),
  ('temporalis', 'Temporalis'),
  ('m_pterygoid', 'M. Pterygoid'),
  ('l_pterygoid', 'L. Pterygoid'),
  ('suprahyoids', 'Suprahyoids'),
  ('sternocleidomastoid', 'Sternocleidomastoid'),
  ('occipital', 'Occipital M.'),
];

const _pairedFields = [
  ('tmj_clicking', 'TMJ Clicking or crepitation'),
  ('preauricular_pain', 'Preauricular pain'),
  ('swelling', 'Swelling or asymmetry of the face'),
  ('deviation_opening', 'Deviation on opening'),
];

class _ExtraoralIntraoralExamFieldState extends State<ExtraoralIntraoralExamField> {
  // One controller per text input, keyed the same way the JSON is keyed
  // (`muscle_<key>_<side>` for the grid, `<key>_<side>` for the paired
  // fields, the bare key for the three plain-text fields below) — a Map
  // rather than ~22 named fields, since every one of these is identical
  // in shape and only the storage key differs.
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

  Map<String, dynamic> get _muscleValues => Map<String, dynamic>.from(widget.value['muscles'] as Map? ?? {});

  String _muscleValue(String key, String side) =>
      (( _muscleValues[key] as Map?)?[side] as String?) ?? '';

  void _setMuscle(String key, String side, String value) {
    final muscles = _muscleValues;
    muscles[key] = {...(muscles[key] as Map? ?? {}), side: value};
    widget.onChanged({...widget.value, 'muscles': muscles});
  }

  String _pairedValue(String key, String side) => ((widget.value[key] as Map?)?[side] as String?) ?? '';

  void _setPaired(String key, String side, String value) {
    widget.onChanged({
      ...widget.value,
      key: {...(widget.value[key] as Map? ?? {}), side: value},
    });
  }

  void _set(String key, dynamic value) => widget.onChanged({...widget.value, key: value});

  Widget _pairedRow(String label, String rightValue, String leftValue, ValueChanged<String> onRight, ValueChanged<String> onLeft, String rightKey, String leftKey) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(label, style: const TextStyle(fontSize: 12))),
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: _controllerFor(rightKey, rightValue),
              enabled: !widget.readOnly,
              style: const TextStyle(fontSize: 11),
              decoration: const InputDecoration(isDense: true, hintText: 'R', contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6)),
              onChanged: onRight,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: _controllerFor(leftKey, leftValue),
              enabled: !widget.readOnly,
              style: const TextStyle(fontSize: 11),
              decoration: const InputDecoration(isDense: true, hintText: 'L', contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6)),
              onChanged: onLeft,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final headDiagrams = Map<String, dynamic>.from(widget.value['head_diagrams'] as Map? ?? {});

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Muscle tenderness', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        for (final (key, label) in _muscles)
          _pairedRow(
            label,
            _muscleValue(key, 'right'),
            _muscleValue(key, 'left'),
            (v) => _setMuscle(key, 'right', v),
            (v) => _setMuscle(key, 'left', v),
            'muscle_${key}_right',
            'muscle_${key}_left',
          ),
        const SizedBox(height: 12),
        for (final (key, label) in _pairedFields)
          _pairedRow(
            label,
            _pairedValue(key, 'right'),
            _pairedValue(key, 'left'),
            (v) => _setPaired(key, 'right', v),
            (v) => _setPaired(key, 'left', v),
            '${key}_right',
            '${key}_left',
          ),
        const SizedBox(height: 12),
        Text('Maximum mouth opening (or interincisal distance), cm', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        SizedBox(
          width: 160,
          child: TextFormField(
            controller: _controllerFor('max_mouth_opening', widget.value['max_mouth_opening'] as String? ?? ''),
            enabled: !widget.readOnly,
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
            onChanged: (v) => _set('max_mouth_opening', v),
          ),
        ),
        const SizedBox(height: 12),
        Text('Facial Defects or congenital abnormalities', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        TextFormField(
          controller: _controllerFor('facial_defects', widget.value['facial_defects'] as String? ?? ''),
          enabled: !widget.readOnly,
          maxLines: 2,
          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
          onChanged: (v) => _set('facial_defects', v),
        ),
        const SizedBox(height: 12),
        Text('Condition of the oral mucosa (ulcer, traumatic, white or red lesions…)', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        TextFormField(
          controller: _controllerFor('oral_mucosa_condition', widget.value['oral_mucosa_condition'] as String? ?? ''),
          enabled: !widget.readOnly,
          maxLines: 2,
          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
          onChanged: (v) => _set('oral_mucosa_condition', v),
        ),
        const SizedBox(height: 16),
        Text('Head pain-location diagrams', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        HeadDiagramsBoard(
          value: headDiagrams,
          readOnly: widget.readOnly,
          onChanged: (next) => _set('head_diagrams', next),
        ),
      ],
    );
  }
}
