import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/widgets/qr_dialog.dart';
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
  const CaseSheetFormScreen({
    super.key,
    required this.resource,
    required this.recordId,
    this.taskInstanceId,
    this.taskId,
  });
  final String resource;
  final int? recordId;

  /// Carries the case this sheet belongs to, end to end (2026-08-27):
  /// present when arriving via the "نموذج سريري" action on a case row —
  /// `_create()` below sends it as `task_instances_id` (the field
  /// `CaseSheetController::open()`'s web equivalent has always keyed a
  /// sheet by), and its presence gates the "رمز QR" button so the exact
  /// same case's QR is reachable from here too, not just the task-instance
  /// screen. Null for the older, still-supported standalone "browse my
  /// records" flow, where a sheet floats free of any specific case.
  final int? taskInstanceId;

  /// The optional pre-instance draft's linkage (2026-08-28) — mutually
  /// exclusive with [taskInstanceId]: set when arriving from a
  /// not-yet-started slot's "نموذج سريري" action instead, via
  /// `CaseSheetController::openForTask()`. Sent as `task_id` on create; no
  /// "رمز QR" action here, since there's no task-instance QR to show yet.
  final int? taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schemaAsync = ref.watch(caseSheetFormSchemaProvider(resource));
    final isCreate = recordId == null;
    final recordAsync =
        isCreate ? const AsyncValue<Map<String, dynamic>>.data({}) : ref.watch(caseSheetRecordProvider((resource, recordId!)));

    return Scaffold(
      appBar: AppBar(
        title: Text(schemaAsync.valueOrNull?.title ?? '...'),
        actions: [
          if (taskInstanceId != null)
            IconButton(
              icon: const Icon(Icons.qr_code_2),
              tooltip: 'رمز الحالة',
              onPressed: () => showQrDialog(
                context,
                imagePath: '/task-instances/$taskInstanceId/qr',
                title: 'رمز الحالة',
                caption: 'يُمسح هذا الرمز لإعادة فتح هذه الحالة مباشرة.',
              ),
            ),
        ],
      ),
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
        if (taskInstanceId != null) 'task_instances_id': taskInstanceId,
        if (taskInstanceId == null && taskId != null) 'task_id': taskId,
      };

      try {
        final created = await ref.read(caseSheetRecordRepositoryProvider).create(resource, fullPayload);
        ref.invalidate(caseSheetRecordListProvider(resource));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إنشاء السجل بنجاح.')));
          // Carries taskInstanceId forward so the "رمز QR" button above
          // still shows on the resulting edit screen — otherwise this
          // case's linkage would be visible only until the very next
          // navigation.
          final query = taskInstanceId != null
              ? '?task_instances_id=$taskInstanceId'
              : (taskId != null ? '?task_id=$taskId' : '');
          context.pushReplacement('/case-sheets/$resource/${created['id']}$query');
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
