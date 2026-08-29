import 'package:flutter/material.dart';

import 'quadrant_teeth_field.dart';

/// Repeating "info + quadrant tooth picker" rows — port of
/// `Components/QuadrantRepeater.vue`, orthodontics.php's two repeaters
/// that share this exact shape: "Stages of treatment" (`treatment_stages`)
/// and "Appliance type & Design" (`appliance_designs`). Both store
/// `{ [index]: { info: string, quadrants: string } }`, 1-based indices —
/// reuses [QuadrantTeethField] for each row's tooth picker rather than a
/// second implementation of the same fdi-cross selector.
class QuadrantRepeaterField extends StatefulWidget {
  const QuadrantRepeaterField({
    super.key,
    required this.value,
    required this.onChanged,
    this.readOnly = false,
    this.itemLabel = 'Item',
    this.infoLabel = 'Information',
  });

  final Map<String, dynamic> value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool readOnly;
  final String itemLabel;
  final String infoLabel;

  @override
  State<QuadrantRepeaterField> createState() => _QuadrantRepeaterFieldState();
}

class _QuadrantRepeaterFieldState extends State<QuadrantRepeaterField> {
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

  // Rows are keyed 1..N with no gaps, same as the original's counters.
  List<int> get _indices {
    final keys = widget.value.keys.map(int.tryParse).whereType<int>().where((n) => n > 0).toList()..sort();
    return keys.isEmpty ? [1] : keys;
  }

  Map<String, dynamic> _rowValue(int i) => Map<String, dynamic>.from(widget.value['$i'] as Map? ?? const {'info': '', 'quadrants': ''});

  void _setInfo(int i, String info) => widget.onChanged({...widget.value, '$i': {..._rowValue(i), 'info': info}});

  void _setQuadrants(int i, String quadrants) =>
      widget.onChanged({...widget.value, '$i': {..._rowValue(i), 'quadrants': quadrants}});

  void _addRow() {
    final next = Map<String, dynamic>.from(widget.value);
    final nextIndex = (_indices.isNotEmpty ? _indices.reduce((a, b) => a > b ? a : b) : 0) + 1;
    next['$nextIndex'] = {'info': '', 'quadrants': ''};
    widget.onChanged(next);
  }

  // Renumbers the remaining rows to stay contiguous (1..N, no gaps) after
  // a removal — matches the original's own renumberTreatmentStages()/
  // renumberApplianceDesigns() (orthodontics.php), which physically
  // renames every field's id/name/data-attributes on removal for the
  // same reason. Mirrors `QuadrantRepeater.vue`'s identical fix
  // (2026-08-29, found while confirming "dynamic teeth numbering"
  // parity with dentalclinic) — without it, removing a middle row left
  // a gap that was harmless for the stored data but showed every
  // remaining row past the gap under its *old* "Stage N" label.
  void _removeRow(int i) {
    final remaining = _indices.where((k) => k != i).toList();
    final next = <String, dynamic>{};
    for (var idx = 0; idx < remaining.length; idx++) {
      next['${idx + 1}'] = widget.value['${remaining[idx]}'];
    }

    // Unlike Vue's fully-reactive `:value` binding, this widget's
    // TextEditingControllers are keyed by position (`info_$i`) and
    // persist independently of `widget.value` once created — after
    // renumbering, a given key may now belong to a *different* row's
    // data, which would otherwise show that key's stale cached text
    // instead of the row's real (shifted) value. Disposing them all and
    // letting `_controllerFor` recreate fresh ones from `next` on the
    // following build is simpler and safer than trying to shift each
    // controller's `.text` to match its row's new index individually.
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();

    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final indices = _indices;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final i in indices)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.grey.shade50, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${widget.itemLabel} $i', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    if (!widget.readOnly && indices.length > 1)
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: Colors.red, padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                        onPressed: () => _removeRow(i),
                        child: const Text('Remove', style: TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(widget.infoLabel, style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _controllerFor('info_$i', _rowValue(i)['info'] as String? ?? ''),
                  enabled: !widget.readOnly,
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                  onChanged: (v) => _setInfo(i, v),
                ),
                const SizedBox(height: 10),
                Text('Teeth Selection', style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 4),
                QuadrantTeethField(
                  value: _rowValue(i)['quadrants'] as String? ?? '',
                  readOnly: widget.readOnly,
                  onChanged: (v) => _setQuadrants(i, v),
                ),
              ],
            ),
          ),
        if (!widget.readOnly)
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.green.shade700),
            onPressed: _addRow,
            child: Text('+ Add ${widget.itemLabel}'),
          ),
      ],
    );
  }
}
