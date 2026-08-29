import 'package:flutter/material.dart';

/// Quadrant tooth picker — port of `resources/js/Components/QuadrantTeeth.vue`,
/// itself a port of the `fdi-cross` selector used across the original
/// app's case sheets (complete_denture.php, prosthodontics.php,
/// surgery.php, and operative.php's non-vital/missing/crown-bridge teeth
/// fields — see `App\Support\OperativeForm`'s `type: 'teeth'` fields).
/// Teeth are identified by quadrant code + number (UR8, UL1, LR6 …),
/// stored as the same comma-separated string the web component and the
/// original both use — not a JSON array, so a record saved here loads
/// identically in either app.
///
/// Added 2026-08-29, by request — until now this app rendered every
/// `type: 'teeth'` field as a plain comma-list text field (the user had
/// to type "UR8, UL1" by hand), while web already had this real picker.
class QuadrantTeethField extends StatelessWidget {
  const QuadrantTeethField({
    super.key,
    required this.value,
    required this.onChanged,
    this.readOnly = false,
  });

  /// The stored comma-separated string, e.g. "UR8, UL1".
  final String value;
  final ValueChanged<String> onChanged;

  /// Per-button `onTap: null`, not `IgnorePointer` — that wrapping broke
  /// this widget's own horizontal scroll for a read-only case-sheet
  /// preview elsewhere in this app (see `ToothOdontogramField.readOnly`'s
  /// doc comment for the exact bug this avoids repeating).
  final bool readOnly;

  static const Map<String, List<int>> _quadrants = {
    'UR': [8, 7, 6, 5, 4, 3, 2, 1],
    'UL': [1, 2, 3, 4, 5, 6, 7, 8],
    'LR': [8, 7, 6, 5, 4, 3, 2, 1],
    'LL': [1, 2, 3, 4, 5, 6, 7, 8],
  };

  static const _rows = [['UR', 'UL'], ['LR', 'LL']];

  List<String> get _selected =>
      value.split(',').map((c) => c.trim()).where((c) => c.isNotEmpty).toList();

  void _toggle(String code) {
    final current = _selected;
    final next = current.contains(code) ? (current..remove(code)) : [...current, code];
    onChanged(next.join(', '));
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: InputDecorator(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  hintText: 'مثال: UR8, UL1',
                ),
                child: Text(value, style: const TextStyle(fontSize: 13)),
              ),
            ),
            if (!readOnly && value.isNotEmpty)
              TextButton(onPressed: () => onChanged(''), child: const Text('مسح')),
          ],
        ),
        const SizedBox(height: 8),
        // Same horizontal-scroll shape as `QuadrantTeeth.vue`'s own fix
        // (see that file's doc comment): the row must be allowed its
        // natural, un-shrunk width so it genuinely overflows and this
        // `SingleChildScrollView` has something to scroll.
        Container(
          decoration: BoxDecoration(border: Border.all(color: theme.dividerColor), borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.all(6),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            // Quadrant reading order is a fixed anatomical left-to-right
            // layout (patient's right side first) that must not flip
            // under the app's Arabic (RTL) locale — same reasoning
            // already established for `ToothOdontogramField._archRow()`.
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final row in _rows)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final q in row)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              border: (q == 'UR' || q == 'LR')
                                  ? Border(right: BorderSide(color: theme.dividerColor))
                                  : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final n in _quadrants[q]!)
                                  _ToothButton(
                                    label: '$n',
                                    selected: selected.contains('$q$n'),
                                    onTap: readOnly ? null : () => _toggle('$q$n'),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ToothButton extends StatelessWidget {
  const _ToothButton({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.all(1.5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? primary : Colors.white,
            border: Border.all(color: selected ? primary : Colors.grey.shade400),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 11, color: selected ? Colors.white : Colors.black87),
          ),
        ),
      ),
    );
  }
}
