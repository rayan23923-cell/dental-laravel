import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/chat_list_tile.dart';
import '../data/case_sheet_types_admin_repository.dart';
import '../domain/case_sheet_type_admin.dart';
import 'case_sheet_types_admin_providers.dart';

/// Create/edit happens in a dialog, not a full-screen route: the form is
/// only 4 fields (5 on create) — same "too little content for a separate
/// route" call already made for taxonomy admin.
class CaseSheetTypeListScreen extends ConsumerWidget {
  const CaseSheetTypeListScreen({super.key});

  Future<void> _openForm(BuildContext context, WidgetRef ref, {CaseSheetTypeAdmin? item}) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CaseSheetTypeFormDialog(item: item),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(caseSheetTypeListProvider);
    final t = ref.watch(translationsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t['caseSheetTypesAdmin.title']!)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(context, ref),
        tooltip: t['caseSheetTypesAdmin.newTitle'],
        child: const Icon(Icons.add),
      ),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text(error is ApiException ? error.userMessage : t['caseSheetTypesAdmin.loadFailed']!),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(child: Text(t['caseSheetTypesAdmin.emptyList']!));
          }
          // Chat-list style (2026-10-13, by request).
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(caseSheetTypeListProvider),
            child: ListView.separated(
              padding: const EdgeInsets.only(top: 8, bottom: 88),
              itemCount: items.length,
              separatorBuilder: (_, __) => chatDivider,
              itemBuilder: (context, i) {
                final item = items[i];
                return ChatListTile(
                  title: item.nameAr,
                  subtitle: item.nameEn,
                  icon: Icons.description,
                  color: item.isActive ? chatToneFor(item.id) : Colors.grey,
                  chips: [
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: ChatChip(label: item.typeCode, icon: Icons.tag),
                    ),
                    ChatChip(
                      label: '${item.tasksCount} ${t['caseSheetTypesAdmin.tasksSuffix']}',
                      icon: Icons.assignment,
                      color: Colors.indigo,
                    ),
                    if (!item.isActive)
                      ChatChip(label: t['caseSheetTypesAdmin.inactiveChip']!, icon: Icons.block, color: Colors.red),
                  ],
                  onTap: () => _openForm(context, ref, item: item),
                  actions: [
                    ChatAction(
                      icon: Icons.edit_outlined,
                      tooltip: t['caseSheetTypesAdmin.editTitle']!,
                      onPressed: () => _openForm(context, ref, item: item),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _CaseSheetTypeFormDialog extends ConsumerStatefulWidget {
  const _CaseSheetTypeFormDialog({this.item});
  final CaseSheetTypeAdmin? item;

  @override
  ConsumerState<_CaseSheetTypeFormDialog> createState() => _CaseSheetTypeFormDialogState();
}

class _CaseSheetTypeFormDialogState extends ConsumerState<_CaseSheetTypeFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _codeController = TextEditingController(text: widget.item?.typeCode ?? '');
  late final _nameArController = TextEditingController(text: widget.item?.nameAr ?? '');
  late final _nameEnController = TextEditingController(text: widget.item?.nameEn ?? '');
  late final _descriptionController = TextEditingController(text: widget.item?.description ?? '');
  late bool _isActive = widget.item?.isActive ?? true;
  bool _submitting = false;

  bool get _isCreate => widget.item == null;

  @override
  void dispose() {
    _codeController.dispose();
    _nameArController.dispose();
    _nameEnController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    setState(() => _submitting = true);

    final payload = {
      if (_isCreate) 'type_code': _codeController.text.trim(),
      'name_ar': _nameArController.text.trim(),
      'name_en': _nameEnController.text.trim(),
      'description': _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
      'is_active': _isActive,
    };

    try {
      final repo = ref.read(caseSheetTypesAdminRepositoryProvider);
      if (_isCreate) {
        await repo.create(payload);
      } else {
        await repo.update(widget.item!.id, payload);
      }
      ref.invalidate(caseSheetTypeListProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        final t = ref.read(translationsProvider);
        final message = e is ApiException ? e.userMessage : t['caseSheetTypesAdmin.saveFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    return AlertDialog(
      title: Text(_isCreate ? t['caseSheetTypesAdmin.newTitle']! : t['caseSheetTypesAdmin.editTitle']!),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isCreate)
                TextFormField(
                  controller: _codeController,
                  decoration: InputDecoration(
                    labelText: t['caseSheetTypesAdmin.codeLabel'],
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return t['caseSheetTypesAdmin.requiredField'];
                    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(v.trim())) return t['caseSheetTypesAdmin.invalidFormat'];
                    return null;
                  },
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(trf(t['caseSheetTypesAdmin.codeNotEditable']!, {'code': widget.item!.typeCode}),
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameArController,
                decoration: InputDecoration(labelText: t['caseSheetTypesAdmin.nameArLabel'], border: const OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? t['caseSheetTypesAdmin.requiredField'] : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameEnController,
                decoration: InputDecoration(labelText: t['caseSheetTypesAdmin.nameEnLabel'], border: const OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? t['caseSheetTypesAdmin.requiredField'] : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(labelText: t['caseSheetTypesAdmin.descriptionLabel'], border: const OutlineInputBorder()),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _isActive,
                title: Text(t['caseSheetTypesAdmin.activeLabel']!),
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (v) => setState(() => _isActive = v ?? true),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t['caseSheetTypesAdmin.cancel']!)),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(t['caseSheetTypesAdmin.save']!),
        ),
      ],
    );
  }
}
