import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/lookup_repository.dart';

/// Extracted from `tasks_admin/presentation/task_list_screen.dart`'s
/// original private `_CascadingDropdown<T>` once a 3rd–5th consumer needed
/// the exact same widget (doctors/groups/taxonomy admin screens) — the same
/// "extract once duplication would otherwise triple" threshold this
/// codebase already uses elsewhere (see `lookup_repository.dart`'s own doc
/// comment). Callers narrow [itemsAsync] themselves (e.g. `stagesAsync.whenData((items) =>
/// items.where((s) => s.educationTypeId == parentId).toList())`) and pass a
/// `key: ValueKey('stage-$parentId')` so the widget fully resets when the
/// parent selection changes — `DropdownMenu.initialSelection` only applies
/// on first build otherwise.
class CascadingDropdown extends StatelessWidget {
  const CascadingDropdown({
    super.key,
    required this.label,
    required this.itemsAsync,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final AsyncValue<List<LookupItem>> itemsAsync;
  final int? value;
  final bool enabled;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = itemsAsync.valueOrNull ?? const <LookupItem>[];
    final validValue = items.any((i) => i.id == value) ? value : null;

    return DropdownMenu<int>(
      enabled: enabled,
      enableFilter: true,
      requestFocusOnTap: true,
      expandedInsets: EdgeInsets.zero,
      label: Text(label),
      initialSelection: validValue,
      dropdownMenuEntries: [for (final i in items) DropdownMenuEntry(value: i.id, label: i.name)],
      onSelected: onChanged,
    );
  }
}
