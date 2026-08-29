import 'package:flutter/material.dart';

/// Port of `resources/js/Components/EndodonticsCanalTable.vue` — the
/// per-canal working-length/size table used twice in the Endodontics
/// section (First Visit's W.L. Estimation table, Second Visit's
/// Instrumentation table): same 10 canals, different columns. Canal ids
/// and labels copied verbatim from the Vue component (itself copied from
/// `operative.php`'s own `$canals` array).
class EndodonticsCanalTable extends StatelessWidget {
  const EndodonticsCanalTable({
    super.key,
    required this.value,
    required this.columns,
    required this.onChanged,
    this.readOnly = false,
  });

  final Map<String, dynamic> value;

  /// Each column: `(key, label)`. `key` is the per-canal data field name
  /// (e.g. `wl_xray`, `wl`) — matches the web component's own per-visit
  /// naming exactly.
  final List<(String, String)> columns;
  final ValueChanged<Map<String, dynamic>> onChanged;

  /// Disables only the checkbox/text-field edits — not implemented by
  /// wrapping this widget in `IgnorePointer` at the call site, which broke
  /// this table's horizontal `SingleChildScrollView` drag gesture too
  /// (same bug found in `ToothOdontogramField`, see its `readOnly` doc
  /// comment — 2026-08-29).
  final bool readOnly;

  static const _canals = [
    ('B', 'B.'), ('P', 'P.'), ('OR', 'OR'),
    ('L', 'L.'), ('M', 'M.'), ('D', 'D.'),
    ('DB', 'D.B.'), ('DL', 'D.L.'),
    ('MB', 'M.B.'), ('ML', 'M.L.'),
  ];

  Map<String, dynamic> _rowOf(String canalId) => (value[canalId] as Map<String, dynamic>?) ?? {};

  void _setField(String canalId, String field, dynamic fieldValue) {
    final next = Map<String, dynamic>.from(value);
    next[canalId] = {..._rowOf(canalId), field: fieldValue};
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        border: TableBorder.all(color: Theme.of(context).colorScheme.outlineVariant),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: {
          0: const FixedColumnWidth(64),
          for (var i = 0; i < columns.length; i++) i + 1: const FixedColumnWidth(72),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest),
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Text('القناة', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              for (final (_, label) in columns)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          for (final (canalId, canalLabel) in _canals)
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: _rowOf(canalId)['checked'] as bool? ?? false,
                        onChanged: readOnly ? null : (v) => _setField(canalId, 'checked', v ?? false),
                        visualDensity: VisualDensity.compact,
                      ),
                      Text(canalLabel, style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
                for (final (colKey, _) in columns)
                  Padding(
                    padding: const EdgeInsets.all(2),
                    child: TextFormField(
                      initialValue: _rowOf(canalId)[colKey] as String? ?? '',
                      enabled: !readOnly,
                      style: const TextStyle(fontSize: 11),
                      decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6)),
                      onChanged: (v) => _setField(canalId, colKey, v),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
