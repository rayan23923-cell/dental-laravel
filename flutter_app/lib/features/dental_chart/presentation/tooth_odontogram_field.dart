import 'package:flutter/material.dart';

import '../domain/odontogram_vocabulary.dart';
import '../domain/tooth_entry.dart';
import 'tooth_flower_painter.dart';

/// Ports `Components/ToothOdontogram.vue`'s full editor: two horizontally
/// scrollable arch rows of 16 tooth buttons each, tapping one opens a sheet
/// with a large live preview plus tooth/surface/root/treatment status
/// editing and notes. Only teeth with a non-default entry are kept in
/// [value], matching the original's sparse storage.
class ToothOdontogramField extends StatefulWidget {
  const ToothOdontogramField({super.key, required this.value, required this.onChanged, this.readOnly = false});

  final List<dynamic> value;
  final ValueChanged<List<dynamic>> onChanged;

  /// Disables only the tap-to-edit interaction (opening a tooth's editor
  /// sheet) — deliberately *not* implemented by wrapping this widget in an
  /// `IgnorePointer` at the call site, which was the bug: `IgnorePointer`
  /// kills the arch rows' horizontal `SingleChildScrollView` drag gesture
  /// too, not just tap, so a supervisor/admin previewing a read-only case
  /// sheet couldn't scroll the chart at all (found live, 2026-08-29). This
  /// flag reaches only [_toothButton]'s `onTap`, leaving scrolling free.
  final bool readOnly;

  @override
  State<ToothOdontogramField> createState() => _ToothOdontogramFieldState();
}

class _ToothOdontogramFieldState extends State<ToothOdontogramField> {
  late Map<String, ToothEntry> _entries;

  @override
  void initState() {
    super.initState();
    _entries = _decode(widget.value);
  }

  @override
  void didUpdateWidget(covariant ToothOdontogramField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.value, widget.value)) {
      _entries = _decode(widget.value);
    }
  }

  Map<String, ToothEntry> _decode(List<dynamic> raw) {
    final map = <String, ToothEntry>{};
    for (final item in raw) {
      if (item is Map) {
        final entry = ToothEntry.fromJson(Map<String, dynamic>.from(item));
        map[entry.number] = entry;
      }
    }
    return map;
  }

  void _commit() => widget.onChanged(_entries.values.map((e) => e.toJson()).toList());

  ToothEntry _entryFor(int number) =>
      _entries[number.toString()] ??
      ToothEntry(
        number: number.toString(),
        position: ToothEntry.positionOf(number),
        notes: '',
        status: 'planned',
        toothStatus: 'present',
        polygons: {for (final id in kSurfaceIds) id: const ToothSurface(name: '', status: 'healthy')},
      );

  bool _isDefault(ToothEntry entry) =>
      entry.toothStatus == 'present' &&
      entry.notes.trim().isEmpty &&
      entry.polygons.values.every((s) => s.status == 'healthy' || s.status.isEmpty);

  void _updateEntry(ToothEntry entry) {
    setState(() {
      if (_isDefault(entry)) {
        _entries.remove(entry.number);
      } else {
        _entries[entry.number] = entry;
      }
    });
    _commit();
  }

  Color _fillFor(ToothEntry entry, String surfaceId) =>
      kToothLevelFill[entry.toothStatus] ??
      colorForStatus(kSurfaceStatuses, entry.polygons[surfaceId]?.status ?? 'healthy');

  void _openEditor(int number) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ToothEditorSheet(entry: _entryFor(number), onChanged: _updateEntry),
    );
  }

  Widget _toothButton(int number) {
    final entry = _entryFor(number);
    final touched = _entries.containsKey(number.toString());
    final borderColor = touched ? Theme.of(context).colorScheme.primary : const Color(0xFFDBDBDB);
    return GestureDetector(
      onTap: widget.readOnly ? null : () => _openEditor(number),
      child: Container(
        width: 46,
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                border: Border.all(color: borderColor, width: touched ? 1.6 : 1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: CustomPaint(
                painter: ToothFlowerPainter(
                  fillFor: (id) => _fillFor(entry, id),
                  toothLevelFill: kToothLevelFill[entry.toothStatus],
                  opacity: kToothLevelOpacity[entry.toothStatus] ?? 1.0,
                  extracted: entry.toothStatus == 'extracted',
                  retainedRoot: entry.toothStatus == 'retained_root',
                  crown: entry.toothStatus == 'crown',
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(number.toString(), style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }

  // FDI arch order is a fixed anatomical left-to-right reading (patient's
  // right side first) that must not flip with the app's Arabic (RTL)
  // locale — without this, the ambient Directionality.rtl silently
  // reverses this Row's child order, showing 28→18 instead of the
  // intended 18→28. Found via the periodontal chart port hitting the
  // identical bug with real, verified data (a tap on the first cell of a
  // tooth landed in the array's last position) — see
  // flutter_app/README.md.
  Widget _archRow(List<int> numbers) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(children: numbers.map(_toothButton).toList()),
        ),
      );

  Widget _legend(BuildContext context) => Wrap(
        spacing: 10,
        runSpacing: 4,
        children: kToothStatuses
            .map(
              (s) => Chip(
                avatar: Icon(s.icon, size: 14, color: s.color),
                label: Text(s.label, style: const TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            )
            .toList(),
      );

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelLarge;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Upper Arch', style: labelStyle),
        const SizedBox(height: 4),
        _archRow(kUpperArch),
        const Divider(height: 24),
        Text('Lower Arch', style: labelStyle),
        const SizedBox(height: 4),
        _archRow(kLowerArch),
        const SizedBox(height: 12),
        _legend(context),
      ],
    );
  }
}

class _ToothEditorSheet extends StatefulWidget {
  const _ToothEditorSheet({required this.entry, required this.onChanged});

  final ToothEntry entry;
  final ValueChanged<ToothEntry> onChanged;

  @override
  State<_ToothEditorSheet> createState() => _ToothEditorSheetState();
}

class _ToothEditorSheetState extends State<_ToothEditorSheet> {
  late ToothEntry _entry;
  String? _selectedSurface;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    _notesController = TextEditingController(text: _entry.notes);
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _apply(ToothEntry next) {
    setState(() => _entry = next);
    widget.onChanged(next);
  }

  void _setToothStatus(String status) {
    _selectedSurface = null;
    _apply(_entry.copyWith(toothStatus: status));
  }

  void _setSurfaceStatus(String surfaceId, String status) {
    final polygons = Map<String, ToothSurface>.from(_entry.polygons);
    polygons[surfaceId] = ToothSurface(name: polygons[surfaceId]?.name ?? '', status: status);
    _apply(_entry.copyWith(polygons: polygons));
  }

  Color _fillFor(String surfaceId) =>
      kToothLevelFill[_entry.toothStatus] ??
      colorForStatus(kSurfaceStatuses, _entry.polygons[surfaceId]?.status ?? 'healthy');

  @override
  Widget build(BuildContext context) {
    final isNonVital = _entry.toothStatus == 'non_vital';
    final rows = isNonVital ? kRootIds : kSurfaceIds;
    final pool = isNonVital ? kRootStatuses : kSurfaceStatuses;
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Center(child: Text('Tooth #${_entry.number}', style: theme.textTheme.titleMedium)),
            const SizedBox(height: 12),
            Center(
              child: GestureDetector(
                onTapDown: (details) {
                  if (isNonVital) return;
                  final surface = ToothFlowerPainter.hitTestSurface(details.localPosition, const Size(140, 140));
                  if (surface != null) setState(() => _selectedSurface = surface);
                },
                child: SizedBox(
                  width: 140,
                  height: 140,
                  child: CustomPaint(
                    painter: ToothFlowerPainter(
                      fillFor: _fillFor,
                      toothLevelFill: kToothLevelFill[_entry.toothStatus],
                      opacity: kToothLevelOpacity[_entry.toothStatus] ?? 1.0,
                      extracted: _entry.toothStatus == 'extracted',
                      retainedRoot: _entry.toothStatus == 'retained_root',
                      crown: _entry.toothStatus == 'crown',
                      selectedSurface: _selectedSurface,
                      strokeWidth: 2,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('General Tooth Status', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kToothStatuses
                  .map(
                    (s) => ChoiceChip(
                      label: Text(s.label),
                      avatar: Icon(s.icon, size: 16, color: s.color),
                      selected: _entry.toothStatus == s.value,
                      onSelected: (_) => _setToothStatus(s.value),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 20),
            Text(isNonVital ? 'Root Status' : 'Surface Status', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            ...rows.map((surfaceId) {
              final current = _entry.polygons[surfaceId]?.status ?? 'healthy';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 88,
                      child: Text(surfaceLabel(surfaceId), style: const TextStyle(fontSize: 12)),
                    ),
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: pool
                            .map(
                              (opt) => ChoiceChip(
                                label: Text(opt.label, style: const TextStyle(fontSize: 11)),
                                selected: current == opt.value,
                                selectedColor: opt.color.withValues(alpha: 0.3),
                                visualDensity: VisualDensity.compact,
                                onSelected: (_) => _setSurfaceStatus(surfaceId, opt.value),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 20),
            Text('Treatment Status', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: kTreatmentStatuses
                  .map(
                    (t) => ChoiceChip(
                      label: Text(t.$2),
                      selected: _entry.status == t.$1,
                      onSelected: (_) => _apply(_entry.copyWith(status: t.$1)),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes', border: OutlineInputBorder()),
              onChanged: (v) => _apply(_entry.copyWith(notes: v)),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
