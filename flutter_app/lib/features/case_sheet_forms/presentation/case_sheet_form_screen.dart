import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/domain/auth_account.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/auth_state.dart';
import '../data/case_sheet_record_repository.dart';
import '../domain/case_sheet_form_schema.dart';
import 'case_sheet_form_providers.dart';
import 'dynamic_section_form.dart';

/// Fetches a resource's layout schema and (when editing) one of its real
/// records, then renders `DynamicSectionForm` bound to both.
///
/// `recordId == null` means **create**: every one of these 8 REST
/// `store()` endpoints hard-requires `doctor_id`, a field with no
/// `sections()` entry at all — filled in here from the logged-in doctor,
/// never shown as a picker (this screen is only reachable from a doctor's
/// own nav, see `HomeScreen`). A handful of resources need one more
/// resource-specific default beyond that (`caseSheetCreateDefaults()`,
/// e.g. `dental-charts`' `chart_type`). `periodontal-charts` is excluded
/// from create entirely — see `kCaseSheetCreatableResources`'s doc for why.
///
/// Editing needs neither — every one of these controllers' `update()`
/// validates with `sometimes`, so a payload that only carries the
/// `sections()` fields (exactly what `DynamicSectionForm` sends) is
/// always a valid partial update.
class CaseSheetFormScreen extends ConsumerWidget {
  const CaseSheetFormScreen({super.key, required this.resource, required this.recordId});
  final String resource;
  final int? recordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schemaAsync = ref.watch(caseSheetFormSchemaProvider(resource));
    final isCreate = recordId == null;
    final recordAsync =
        isCreate ? const AsyncValue<Map<String, dynamic>>.data({}) : ref.watch(caseSheetRecordProvider((resource, recordId!)));

    return Scaffold(
      appBar: AppBar(title: Text(schemaAsync.valueOrNull?.title ?? '...')),
      body: switch ((schemaAsync, recordAsync)) {
        (AsyncError(:final error), _) || (_, AsyncError(:final error)) => Center(
            child: Text(error is ApiException ? error.userMessage : 'تعذر تحميل النموذج.'),
          ),
        (AsyncData(value: final schema), AsyncData(value: final record)) => SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: DynamicSectionForm(
              schema: schema,
              record: record,
              readonly: false,
              onSubmit: (payload) => isCreate
                  ? _create(context, ref, schema)(payload)
                  : _update(context, ref, recordId!)(payload),
            ),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Future<void> Function(Map<String, dynamic>) _update(BuildContext context, WidgetRef ref, int id) {
    return (payload) async {
      try {
        await ref.read(caseSheetRecordRepositoryProvider).update(resource, id, payload);
        ref.invalidate(caseSheetRecordProvider((resource, id)));
        ref.invalidate(caseSheetRecordListProvider(resource));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحفظ بنجاح.')));
        }
      } catch (e) {
        if (context.mounted) {
          final message = e is ApiException ? e.userMessage : 'تعذر الحفظ.';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        }
      }
    };
  }

  Future<void> Function(Map<String, dynamic>) _create(BuildContext context, WidgetRef ref, CaseSheetFormSchema schema) {
    return (payload) async {
      final authState = ref.read(authControllerProvider).valueOrNull;
      final doctor = authState is Authenticated ? authState.account : null;
      if (doctor is! DoctorAccount) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر تحديد الطبيب الحالي.')));
        return;
      }

      final fullPayload = {
        ...payload,
        ...caseSheetCreateDefaults(resource),
        'doctor_id': doctor.id,
      };

      try {
        final created = await ref.read(caseSheetRecordRepositoryProvider).create(resource, fullPayload);
        ref.invalidate(caseSheetRecordListProvider(resource));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إنشاء السجل بنجاح.')));
          context.pushReplacement('/case-sheets/$resource/${created['id']}');
        }
      } catch (e) {
        if (context.mounted) {
          final message = e is ApiException ? e.userMessage : 'تعذر إنشاء السجل.';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        }
      }
    };
  }
}
