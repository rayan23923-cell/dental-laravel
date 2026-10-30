import 'package:flutter/material.dart';

/// "Number of Teeth" marking grid — port of `Components/TeethSquaresGrid.vue`
/// (orthodontics.php's `number-of-teeth-table`): 4 rows (Unerupted /
/// Erupted / Erupted / Unerupted) × 16 columns (header 8→1 then 1→8,
/// quadrant-style), each cell tappable, opening a picker offering Primary
/// teeth A–E, Permanent teeth 1–8, the "/" (Extracted) special mark, or
/// Clear.
///
/// [value] is `{ [square_id]: mark }`, `square_id = '${row_type}_${col}'`
/// exactly as the web component and the original both key it, so a chart
/// filled in either app parses in the other.
class TeethSquaresGridField extends StatelessWidget {
  const TeethSquaresGridField({super.key, required this.value, required this.onChanged, this.readOnly = false});

  final Map<String, dynamic> value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool readOnly;

  static const _rowLabels = ['Unerupted', 'Erupted', 'Erupted', 'Unerupted'];
  static const _rowTypes = ['unerupted1', 'erupted1', 'erupted2', 'unerupted2'];
  static const _headerNumbers = [8, 7, 6, 5, 4, 3, 2, 1, 1, 2, 3, 4, 5, 6, 7, 8];
  static const _primary = ['A', 'B', 'C', 'D', 'E'];
  static const _permanent = [1, 2, 3, 4, 5, 6, 7, 8];

  Future<void> _openPicker(BuildContext context, String squareId) async {
    if (readOnly) return;

    final selection = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Select Tooth Number', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 12),
              Text('Primary Teeth (A-E)', style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final letter in _primary)
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context, letter),
                      child: Text(letter),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Permanent Teeth (1-8)', style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final n in _permanent)
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context, '$n'),
                      child: Text('$n'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Special Options', style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 6),
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () => Navigator.pop(context, '/'),
                child: const Text('/ Extracted'),
              ),
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () => Navigator.pop(context, ''),
                child: const Text('Clear'),
              ),
            ],
          ),
        ),
      ),
    );

    if (selection == null) return;
    final next = Map<String, dynamic>.from(value);
    if (selection.isEmpty) {
      next.remove(squareId);
    } else {
      next[squareId] = selection;
    }
    onChanged(next);
  }

  Widget _cell(BuildContext context, String text, {double width = 34, bool header = false, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: width,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: header ? Colors.grey.shade100 : Colors.white,
          border: Border.all(color: Colors.grey.shade400, width: 0.5),
        ),
        child: Text(
          text,
          style: TextStyle(fontSize: 11, fontWeight: header ? FontWeight.bold : FontWeight.normal),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade700), borderRadius: BorderRadius.circular(6)),
      padding: const EdgeInsets.all(2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        // Header reads 8→1 then 1→8, a fixed anatomical layout that must
        // not flip under the app's Arabic (RTL) locale — same reasoning
        // as `QuadrantTeethField`.
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _cell(context, '', width: 90, header: true),
                  for (final n in _headerNumbers) _cell(context, '$n', header: true),
                ],
              ),
              for (var row = 0; row < _rowLabels.length; row++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _cell(context, _rowLabels[row], width: 90, header: true),
                    for (var col = 0; col < 16; col++)
                      _cell(
                        context,
                        value['${_rowTypes[row]}_$col']?.toString() ?? '',
                        onTap: () => _openPicker(context, '${_rowTypes[row]}_$col'),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
