import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import 'case_sheet_form_providers.dart';

/// "النماذج السريرية" — entry point listing the 8 case-sheet types
/// (`GET /case-sheet-forms`), each leading to that resource's record list.
class CaseSheetTypesScreen extends ConsumerWidget {
  const CaseSheetTypesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resourcesAsync = ref.watch(caseSheetResourceListProvider);
    final t = ref.watch(translationsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t['caseSheetForm.typesTitle']!)),
      body: resourcesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text(error is ApiException ? error.userMessage : t['caseSheetForm.loadFailed']!),
        ),
        data: (resources) => ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: resources.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final (resource, title) = resources[i];
            return Card(
              child: ListTile(
                title: Text(title),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => context.push('/case-sheets/$resource'),
              ),
            );
          },
        ),
      ),
    );
  }
}
