import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Picks a grade with a tap (2026-10-22, by request: "سكرول ارقام او اي
/// طريقة اسهل"): a big readout with −/+, a scroll wheel of every value in
/// half steps, and quick chips for the whole numbers (or percentages for a
/// large max), "full marks" and "+ half".
class GradePicker extends StatefulWidget {
  const GradePicker({super.key, required this.max, required this.value, required this.onChanged, this.step = 0.5, required this.labels});

  final double max;
  final double? value;
  final ValueChanged<double?> onChanged;
  final double step;

  /// 'outOf' (with {max}), 'full', 'half', 'clear'.
  final Map<String, String> labels;

  @override
  State<GradePicker> createState() => _GradePickerState();
}

class _GradePickerState extends State<GradePicker> {
  late final FixedExtentScrollController _wheel;

  List<double> get _values => [for (var v = 0.0; v <= widget.max + 1e-9; v += widget.step) double.parse(v.toStringAsFixed(2))];

  int _indexOf(double v) => (v / widget.step).round().clamp(0, _values.length - 1);

  @override
  void initState() {
    super.initState();
    _wheel = FixedExtentScrollController(initialItem: _indexOf(widget.value ?? 0));
  }

  @override
  void dispose() {
    _wheel.dispose();
    super.dispose();
  }

  void _set(double? v, {bool moveWheel = true}) {
    final next = v == null ? null : _values[_indexOf(v.clamp(0, widget.max))];
    widget.onChanged(next);
    if (moveWheel && next != null && _wheel.hasClients) {
      _wheel.animateToItem(_indexOf(next), duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    }
    HapticFeedback.selectionClick();
  }

  String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  Color _tone(ColorScheme scheme) {
    final r = (widget.value ?? 0) / widget.max;
    if (widget.value == null) return scheme.outline;
    if (r >= 0.85) return Colors.green.shade700;
    if (r >= 0.6) return scheme.primary;
    if (r >= 0.4) return Colors.orange.shade800;
    return scheme.error;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = widget.value;
    final hasHalf = value != null && value % 1 != 0;
    final quick = widget.max <= 20
        ? [for (var i = 0; i <= widget.max.floor(); i++) i.toDouble()]
        : [for (final p in const [100, 90, 80, 70, 60, 50]) (widget.max * p / 100 / widget.step).round() * widget.step];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(colors: [scheme.primaryContainer.withValues(alpha: 0.6), scheme.surface]),
            border: Border.all(color: scheme.primaryContainer),
          ),
          child: Row(
            children: [
              IconButton.filledTonal(onPressed: () => _set((value ?? 0) - widget.step), icon: const Icon(Icons.remove)),
              Expanded(
                child: SizedBox(
                  height: 120,
                  child: ListWheelScrollView.useDelegate(
                    controller: _wheel,
                    itemExtent: 48,
                    diameterRatio: 1.4,
                    perspective: 0.004,
                    physics: const FixedExtentScrollPhysics(),
                    onSelectedItemChanged: (i) => _set(_values[i], moveWheel: false),
                    childDelegate: ListWheelChildBuilderDelegate(
                      childCount: _values.length,
                      builder: (context, i) {
                        final selected = value != null && _indexOf(value) == i;
                        return Center(
                          child: Text(
                            _fmt(_values[i]),
                            style: TextStyle(
                              fontSize: selected ? 40 : 24,
                              fontWeight: selected ? FontWeight.bold : FontWeight.w400,
                              color: selected ? _tone(scheme) : scheme.onSurfaceVariant.withValues(alpha: 0.6),
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              IconButton.filled(onPressed: () => _set((value ?? -widget.step) + widget.step), icon: const Icon(Icons.add)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            (widget.labels['outOf'] ?? '{max}').replaceAll('{max}', _fmt(widget.max)),
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ),
        const SizedBox(height: 10),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              for (final q in quick)
                ChoiceChip(
                  label: Text(_fmt(q)),
                  selected: value != null && value.floor() == q.floor() && (widget.max <= 20 || value == q),
                  onSelected: (_) => _set(widget.max <= 20 && hasHalf && q + 0.5 <= widget.max ? q + 0.5 : q),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          alignment: WrapAlignment.center,
          children: [
            if (widget.step <= 0.5)
              FilterChip(
                label: Text(widget.labels['half'] ?? '+ ½'),
                selected: hasHalf,
                onSelected: (_) => _set(value == null ? 0.5 : (hasHalf ? value.floorToDouble() : value.floorToDouble() + 0.5)),
              ),
            ActionChip(
              avatar: const Icon(Icons.star, size: 18),
              label: Text('${widget.labels['full'] ?? 'Full'} (${_fmt(widget.max)})'),
              onPressed: () => _set(widget.max),
            ),
            ActionChip(label: Text(widget.labels['clear'] ?? 'Clear'), onPressed: () => widget.onChanged(null)),
          ],
        ),
      ],
    );
  }
}


/// Opens [GradePicker] in a bottom sheet (2026-10-22): returns the picked
/// grade, or null when dismissed.
Future<double?> showGradePickerSheet(
  BuildContext context, {
  required double max,
  double? initial,
  required String title,
  required String confirm,
  required Map<String, String> labels,
}) {
  return showModalBottomSheet<double>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      double? value = initial;
      return StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              GradePicker(max: max, value: value, labels: labels, onChanged: (v) => setState(() => value = v)),
              const SizedBox(height: 12),
              FilledButton(onPressed: value == null ? null : () => Navigator.pop(context, value), child: Text(confirm)),
            ],
          ),
        ),
      );
    },
  );
}
