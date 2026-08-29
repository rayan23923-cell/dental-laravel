import 'package:flutter/material.dart';

/// "Yes/No + details if yes" checklist — port of `Components/ValueDetailsChecklist.vue`
/// (the Past Medical History grid in oral_medicine.php, `pmh_checklist`
/// field type). Each item stores `{value: 'yes'|'no', details: string}`;
/// the details field only shows once "Yes" is picked, matching the
/// original's own show/hide behaviour. Generic over [items] (rather than
/// PMH-specific) since the web component already is — a resource's own
/// `sections()` field carries the category list via its raw `options`
/// (`[{key, label}]`, *not* the `{value, label}` shape `CaseSheetField.options`
/// assumes elsewhere, hence the caller passing pre-extracted records here
/// instead of reusing that getter).
class ValueDetailsChecklistField extends StatefulWidget {
  const ValueDetailsChecklistField({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.readOnly = false,
  });

  final Map<String, dynamic> value;
  final List<(String key, String label)> items;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool readOnly;

  @override
  State<ValueDetailsChecklistField> createState() => _ValueDetailsChecklistFieldState();
}

class _ValueDetailsChecklistFieldState extends State<ValueDetailsChecklistField> {
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

  Map<String, dynamic> _itemOf(String key) =>
      Map<String, dynamic>.from(widget.value[key] as Map? ?? const {'value': 'no', 'details': ''});

  void _setValue(String key, String value) => widget.onChanged({...widget.value, key: {..._itemOf(key), 'value': value}});

  void _setDetails(String key, String details) =>
      widget.onChanged({...widget.value, key: {..._itemOf(key), 'details': details}});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (key, label) in widget.items)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
                    RadioGroup<String>(
                      groupValue: _itemOf(key)['value'] as String? ?? 'no',
                      onChanged: (v) {
                        if (!widget.readOnly && v != null) _setValue(key, v);
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
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
                if ((_itemOf(key)['value'] as String? ?? 'no') == 'yes')
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: TextFormField(
                      controller: _controllerFor(key, _itemOf(key)['details'] as String? ?? ''),
                      enabled: !widget.readOnly,
                      decoration: const InputDecoration(isDense: true, hintText: 'Please specify...', border: OutlineInputBorder()),
                      onChanged: (v) => _setDetails(key, v),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
