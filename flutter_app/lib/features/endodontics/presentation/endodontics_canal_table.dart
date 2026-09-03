import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/config/app_config.dart';
import '../data/endodontics_xray_repository.dart';

/// Port of `resources/js/Components/EndodonticsCanalTable.vue` — the
/// per-canal working-length/size table used twice in the Endodontics
/// section (First Visit's W.L. Estimation table, Second Visit's
/// Instrumentation table): same 10 canals, different columns. Canal ids
/// and labels copied verbatim from the Vue component (itself copied from
/// `operative.php`'s own `$canals` array).
///
/// One column can be `isImage: true` (First Visit's `wl_xray`, 2026-09-03 —
/// "صورة الطول تكون عبر رفع صور للاشعة وليس حقل ادخال نصي") instead of the
/// default plain text field — a real uploaded X-ray, matching the web
/// component's own image-column treatment. The stored cell value is still
/// just a string either way, only now it's the path
/// `EndodonticsXrayRepository.upload()` hands back instead of typed text.
class EndodonticsCanalTable extends StatelessWidget {
  const EndodonticsCanalTable({
    super.key,
    required this.value,
    required this.columns,
    required this.onChanged,
    this.readOnly = false,
  });

  final Map<String, dynamic> value;

  /// Each column: `(key, label, isImage)`. `key` is the per-canal data
  /// field name (e.g. `wl_xray`, `wl`) — matches the web component's own
  /// per-visit naming exactly.
  final List<(String, String, bool)> columns;
  final ValueChanged<Map<String, dynamic>> onChanged;

  /// Disables only the checkbox/text-field/upload edits — not implemented
  /// by wrapping this widget in `IgnorePointer` at the call site, which
  /// broke this table's horizontal `SingleChildScrollView` drag gesture too
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
                child: Text('Canal', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              for (final (_, label, _) in columns)
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
                for (final (colKey, _, isImage) in columns)
                  Padding(
                    padding: const EdgeInsets.all(2),
                    child: isImage
                        ? _XrayCell(
                            path: _rowOf(canalId)[colKey] as String?,
                            readOnly: readOnly,
                            onUploaded: (path) => _setField(canalId, colKey, path),
                          )
                        : TextFormField(
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

class _XrayCell extends ConsumerStatefulWidget {
  const _XrayCell({required this.path, required this.readOnly, required this.onUploaded});

  final String? path;
  final bool readOnly;
  final ValueChanged<String> onUploaded;

  @override
  ConsumerState<_XrayCell> createState() => _XrayCellState();
}

class _XrayCellState extends ConsumerState<_XrayCell> {
  bool _uploading = false;

  Future<void> _pick() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (image == null) return;

    setState(() => _uploading = true);
    try {
      final path = await ref.read(endodonticsXrayRepositoryProvider).upload(image);
      widget.onUploaded(path);
    } catch (_) {
      // A failed upload leaves the cell unchanged — the doctor sees no new
      // thumbnail and can just try again, no separate error UI to build
      // for what's a rare network hiccup.
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.readOnly || _uploading;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.path != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.network(AppConfig.storageUrl(widget.path!), width: 24, height: 24, fit: BoxFit.cover),
          ),
        const SizedBox(width: 2),
        InkWell(
          onTap: disabled ? null : _pick,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: _uploading
                ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5))
                : Icon(Icons.add_a_photo_outlined, size: 14, color: Theme.of(context).colorScheme.outline),
          ),
        ),
      ],
    );
  }
}
