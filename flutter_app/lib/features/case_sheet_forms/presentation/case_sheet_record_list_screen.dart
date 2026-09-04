import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../domain/case_sheet_form_schema.dart';
import 'case_sheet_form_providers.dart';
import 'sync_status_badge.dart';

/// A resource's own records (`GET /{resource}` — already scoped to the
/// authenticated doctor server-side, see e.g. `Api\SurgeryController::
/// index()`), each opening `CaseSheetFormScreen` to edit.
class CaseSheetRecordListScreen extends ConsumerWidget {
  const CaseSheetRecordListScreen({super.key, required this.resource});
  final String resource;

  String _label(Map<String, dynamic> record, Map<String, String> t) {
    final name = record['patient_name'] ?? record['case_no'];
    if (name is String && name.isNotEmpty) return name;
    return trf(t['caseSheetForm.recordFallbackTemplate']!, {'id': '${record['id']}'});
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(caseSheetRecordListProvider(resource));
    final schemaAsync = ref.watch(caseSheetFormSchemaProvider(resource));
    final t = ref.watch(translationsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(schemaAsync.valueOrNull?.title ?? resource)),
      floatingActionButton: kCaseSheetCreatableResources.contains(resource)
          ? FloatingActionButton(
              onPressed: () => context.push('/case-sheets/$resource/new'),
              child: const Icon(Icons.add),
            )
          : null,
      body: recordsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text(error is ApiException ? error.userMessage : t['caseSheetForm.loadFailed']!),
        ),
        data: (page) {
          if (page.items.isEmpty) {
            return Center(child: Text(t['caseSheetForm.recordsEmptyList']!));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(caseSheetRecordListProvider(resource)),
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: page.items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final record = page.items[i];
                return Card(
                  child: ListTile(
                    title: Text(_label(record, t)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SyncStatusBadge(resource: resource, id: record['id'] as int),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_left),
                      ],
                    ),
                    onTap: () => context.push('/case-sheets/$resource/${record['id']}'),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
