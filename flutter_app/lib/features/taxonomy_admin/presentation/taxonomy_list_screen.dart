import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lookup_repository.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/cascading_dropdown.dart';
import '../data/taxonomy_repository.dart';
import '../domain/taxonomy_item.dart';
import 'taxonomy_providers.dart';

/// One screen reused for all three kinds — see `TaxonomyKind`'s doc
/// comment for why a shared implementation makes sense here (unlike
/// Patients/Appointments/Payments, which have meaningfully different
/// shapes and got their own concrete screens). Create/edit happens in a
/// dialog rather than a separate route: each item is just a name plus up
/// to two optional parent dropdowns, too little content to justify a
/// full-screen form and a new pair of routes.
///
/// Search + cascading filters are client-side — `Api\LookupController`'s
/// three `index` endpoints return their whole (small, flat) table, no
/// `search`/pagination params exist or are needed at this scale.
class TaxonomyListScreen extends ConsumerStatefulWidget {
  const TaxonomyListScreen({super.key, required this.kind});
  final TaxonomyKind kind;

  @override
  ConsumerState<TaxonomyListScreen> createState() => _TaxonomyListScreenState();
}

class _TaxonomyListScreenState extends ConsumerState<TaxonomyListScreen> {
  final _searchController = TextEditingController();
  String _search = '';
  int? _educationTypeId;
  int? _stageId;

  TaxonomyKind get kind => widget.kind;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openForm({TaxonomyItem? item}) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _TaxonomyFormDialog(kind: kind, item: item),
    );
  }

  Future<void> _delete(TaxonomyItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حذف ${kind.singularTitle}'),
        content: Text('هل أنت متأكد من حذف "${item.name}"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(taxonomyRepositoryProvider).delete(kind, item.id);
      ref.invalidate(taxonomyListProvider(kind));
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : 'تعذر الحذف.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(taxonomyListProvider(kind));
    final educationTypesAsync =
        kind.hasEducationType ? ref.watch(taxonomyListProvider(TaxonomyKind.educationType)) : null;
    final stagesAsync = kind.hasStage ? ref.watch(taxonomyListProvider(TaxonomyKind.stage)) : null;

    return Scaffold(
      appBar: AppBar(title: Text(kind.title)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'ابحث بالاسم',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _search = v.trim()),
                ),
                if (kind.hasEducationType) ...[
                  const SizedBox(height: 8),
                  CascadingDropdown(
                    label: 'نوع التعليم',
                    itemsAsync: (educationTypesAsync ?? const AsyncValue.data(<TaxonomyItem>[]))
                        .whenData((items) => [for (final e in items) LookupItem(id: e.id, name: e.name)]),
                    value: _educationTypeId,
                    onChanged: (v) => setState(() {
                      _educationTypeId = v;
                      _stageId = null;
                    }),
                  ),
                ],
                if (kind.hasStage) ...[
                  const SizedBox(height: 8),
                  CascadingDropdown(
                    key: ValueKey('stage-$_educationTypeId'),
                    label: 'المرحلة',
                    itemsAsync: (stagesAsync ?? const AsyncValue.data(<TaxonomyItem>[])).whenData(
                      (items) => [
                        for (final s in items)
                          if (_educationTypeId == null || s.educationTypeId == _educationTypeId)
                            LookupItem(id: s.id, name: s.name),
                      ],
                    ),
                    value: _stageId,
                    enabled: _educationTypeId != null,
                    onChanged: (v) => setState(() => _stageId = v),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: itemsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Center(
                child: Text(error is ApiException ? error.userMessage : 'تعذر التحميل.'),
              ),
              data: (allItems) {
                final items = allItems.where((item) {
                  if (_search.isNotEmpty && !item.name.contains(_search)) return false;
                  if (_educationTypeId != null && item.educationTypeId != _educationTypeId) return false;
                  if (_stageId != null && item.stageId != _stageId) return false;
                  return true;
                }).toList();
                final hasFilter = _search.isNotEmpty || _educationTypeId != null || _stageId != null;
                if (items.isEmpty) {
                  return Center(child: Text(hasFilter ? 'لا توجد بيانات مطابقة.' : 'لا توجد بيانات بعد.'));
                }
                final educationTypeNames = {
                  for (final e in educationTypesAsync?.valueOrNull ?? <TaxonomyItem>[]) e.id: e.name,
                };
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(taxonomyListProvider(kind)),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final item = items[i];
                      final subtitle = kind.hasEducationType && item.educationTypeId != null
                          ? educationTypeNames[item.educationTypeId]
                          : null;
                      return Card(
                        child: ListTile(
                          title: Text(item.name),
                          subtitle: subtitle != null ? Text(subtitle) : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _openForm(item: item),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _delete(item),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TaxonomyFormDialog extends ConsumerStatefulWidget {
  const _TaxonomyFormDialog({required this.kind, this.item});
  final TaxonomyKind kind;
  final TaxonomyItem? item;

  @override
  ConsumerState<_TaxonomyFormDialog> createState() => _TaxonomyFormDialogState();
}

class _TaxonomyFormDialogState extends ConsumerState<_TaxonomyFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.item?.name ?? '');
  int? _educationTypeId;
  int? _stageId;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _educationTypeId = widget.item?.educationTypeId;
    _stageId = widget.item?.stageId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    setState(() => _submitting = true);

    final payload = {
      'name': _nameController.text.trim(),
      if (widget.kind.hasEducationType) 'education_type_id': _educationTypeId,
      if (widget.kind.hasStage) 'stage_id': _stageId,
    };

    try {
      final repo = ref.read(taxonomyRepositoryProvider);
      if (widget.item == null) {
        await repo.create(widget.kind, payload);
      } else {
        await repo.update(widget.kind, widget.item!.id, payload);
      }
      ref.invalidate(taxonomyListProvider(widget.kind));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : 'تعذر الحفظ.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final educationTypesAsync =
        widget.kind.hasEducationType ? ref.watch(taxonomyListProvider(TaxonomyKind.educationType)) : null;
    final stagesAsync = widget.kind.hasStage ? ref.watch(taxonomyListProvider(TaxonomyKind.stage)) : null;

    return AlertDialog(
      title: Text(widget.item == null ? '${widget.kind.singularTitle} جديد' : 'تعديل ${widget.kind.singularTitle}'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'الاسم', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null,
            ),
            if (widget.kind.hasEducationType) ...[
              const SizedBox(height: 16),
              educationTypesAsync!.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const Text('تعذر تحميل نوع التعليم.'),
                data: (types) => DropdownButtonFormField<int>(
                  initialValue: types.any((t) => t.id == _educationTypeId) ? _educationTypeId : null,
                  decoration: const InputDecoration(labelText: 'نوع التعليم', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('— بدون —')),
                    for (final t in types) DropdownMenuItem(value: t.id, child: Text(t.name)),
                  ],
                  onChanged: (v) => setState(() {
                    _educationTypeId = v;
                    // Real bug, found live: this used to leave whatever
                    // stage was already picked in place even though it
                    // might belong to a totally different education type
                    // now — reset it so the cascade below can't show a
                    // stale mismatched selection.
                    _stageId = null;
                  }),
                ),
              ),
            ],
            if (widget.kind.hasStage) ...[
              const SizedBox(height: 16),
              // Real bug, found live: this dropdown used to list every
              // stage regardless of the education type picked above —
              // the user's own example of what "فلترة مشابهة للمهام"
              // should fix. Narrowed exactly like task_form_screen.dart's
              // stage cascade; "— بدون —" (no stage) stays available
              // regardless, since a department's stage is optional here.
              stagesAsync!.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const Text('تعذر تحميل المرحلة.'),
                data: (allStages) {
                  final stages = _educationTypeId == null
                      ? allStages
                      : allStages.where((s) => s.educationTypeId == _educationTypeId).toList();
                  return DropdownButtonFormField<int>(
                    key: ValueKey('stage-$_educationTypeId'),
                    initialValue: stages.any((s) => s.id == _stageId) ? _stageId : null,
                    decoration: const InputDecoration(labelText: 'المرحلة', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('— بدون —')),
                      for (final s in stages) DropdownMenuItem(value: s.id, child: Text(s.name)),
                    ],
                    onChanged: (v) => setState(() => _stageId = v),
                  );
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('حفظ'),
        ),
      ],
    );
  }
}
