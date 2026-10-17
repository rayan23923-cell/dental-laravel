import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/pdf/pdf_letterhead.dart';
import '../../../core/widgets/qr_dialog.dart';
import '../../auth/domain/auth_account.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/auth_state.dart';
import '../../clinic_settings/presentation/clinic_settings_providers.dart';
import '../../patient_registration/domain/registration_payment_state.dart';
import '../data/case_sheet_offline_store.dart';
import '../data/case_sheet_record_repository.dart';
import '../domain/case_sheet_form_schema.dart';
import '../domain/case_sheet_patient_field_map.dart';
import '../domain/case_sheet_sync_status.dart';
import 'case_sheet_form_providers.dart';
import 'case_sheet_print_pdf.dart';
import 'dynamic_section_form.dart';
import 'sync_status_badge.dart';
import 'task_work_panel.dart';

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
  CaseSheetFormScreen({
    super.key,
    required this.resource,
    required this.recordId,
    this.taskInstanceId,
    this.taskId,
    this.readonly = false,
    this.supervisorEditableFields = const [],
  });
  final String resource;
  final int? recordId;

  /// Reaches into the mounted `DynamicSectionForm` for "مسح رمز المريض"
  /// (2026-08-28) — see [_scanPatient] below. Not `const`-constructible any
  /// more because of this field (no caller const-constructs this widget
  /// today; `resource`/`recordId` always come from route state).
  final GlobalKey<DynamicSectionFormState> _formStateKey = GlobalKey<DynamicSectionFormState>();

  /// Staff supervisor-preview state (2026-08-28) — set only when arriving
  /// via the "معاينة الكيس شيت" action on `task_progress_screen.dart`
  /// (resolved there from `Api\CaseSheetController::open()`'s `readonly`/
  /// `supervisor_editable_fields`, then round-tripped through the route's
  /// query string — see `app_router.dart`). Always false/`[]` for a
  /// doctor's own create/edit flow.
  final bool readonly;
  final List<String> supervisorEditableFields;

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
    final t = ref.watch(translationsProvider);
    final isCreate = recordId == null;
    // A blank create seeds from the task instance's own already-linked
    // patient when there is one (see caseSheetPatientPrefillProvider's own
    // doc comment) — falls back to a plain empty map when there's no task
    // instance at all (the standalone "browse my records" create flow,
    // where "مسح رمز المريض" stays the only way to fill patient identity).
    final recordAsync = isCreate
        ? (taskInstanceId != null
            ? ref.watch(caseSheetPatientPrefillProvider(taskInstanceId!))
            : const AsyncValue<Map<String, dynamic>>.data({}))
        : ref.watch(caseSheetRecordProvider((resource, recordId!)));

    return Scaffold(
      appBar: AppBar(
        title: Text(schemaAsync.valueOrNull?.title ?? '...'),
        actions: [
          if (!isCreate) ...[
            SyncStatusBadge(resource: resource, id: recordId!),
            const SizedBox(width: 8),
          ],
          // "طباعة" (2026-08-30) — mirrors the web's SectionedForm.vue
          // print link: only once a record actually exists (`!isCreate`,
          // matching its own `isEdit`) and only for the 8 resources
          // `App\Support\CaseSheetPrint::SHEETS` has a print layout for.
          if (!isCreate && kCaseSheetPrintableResources.contains(resource))
            IconButton(
              icon: const Icon(Icons.print_outlined),
              tooltip: t['caseSheetForm.printTooltip'],
              onPressed: () => _print(context, ref),
            ),
          if (taskInstanceId != null)
            IconButton(
              icon: const Icon(Icons.qr_code_2),
              tooltip: t['caseSheetForm.caseCodeTooltip'],
              onPressed: () => showQrDialog(
                context,
                imagePath: '/task-instances/$taskInstanceId/qr',
                title: t['caseSheetForm.caseCodeTooltip']!,
                caption: t['caseSheetForm.caseCodeCaption']!,
              ),
            ),
          // "مسح رمز المريض" (2026-08-28) — autofills the patient-identity
          // fields reception already captured at registration, from the
          // same ticket QR used elsewhere. Hidden when readonly (a staff
          // supervisor preview never types patient identity) or when this
          // resource has no known mapping — see kCaseSheetPatientFieldMap.
          if (!readonly && kCaseSheetPatientFieldMap.containsKey(resource))
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: t['caseSheetForm.scanPatientTooltip'],
              onPressed: () => _scanPatient(context),
            ),
        ],
      ),
      body: switch ((schemaAsync, recordAsync)) {
        (AsyncError(:final error), _) || (_, AsyncError(:final error)) => Center(
            child: Text(error is ApiException ? error.userMessage : t['caseSheetForm.loadFormFailedMsg']!),
          ),
        (AsyncData(value: final schema), AsyncData(value: final record)) => SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The sheet's doctor (2026-10-15, as the web's linkedDoctor):
                // the API's `linked_doctor`, so staff see whose sheet it is.
                if (record['linked_doctor'] case {'name': final String doctorName})
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(Icons.person, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Text('${t['caseSheetForm.doctorLabel']!}: ', style: const TextStyle(color: Colors.grey)),
                        Expanded(
                          child: Text(doctorName, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                // The linked task's points, the same ones task progress
                // records (2026-10-17, web SectionedForm.vue's TaskWorkPanel):
                // the case from the route, or the one the saved sheet is
                // linked to.
                if (_linkedInstanceId(record) case final id?) TaskWorkPanel(key: ValueKey(id), taskInstanceId: id),
                DynamicSectionForm(
                  key: _formStateKey,
                  resource: resource,
                  schema: schema,
                  record: record,
                  readonly: readonly,
                  supervisorEditableFields: supervisorEditableFields,
                  t: t,
                  onStageField: isCreate
                      ? null
                      : (key, value) => ref.read(caseSheetRecordRepositoryProvider).saveStageField(resource, recordId!, key, value),
                  onSubmit: (payload) => isCreate
                      ? _create(context, ref, schema)(payload)
                      : _update(context, ref, recordId!)(payload),
                ),
              ],
            ),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  int? _linkedInstanceId(Map<String, dynamic> record) =>
      taskInstanceId ?? int.tryParse(record['task_instances_id']?.toString() ?? '');

  Future<void> Function(Map<String, dynamic>) _update(BuildContext context, WidgetRef ref, int id) {
    return (payload) async {
      final t = ref.read(translationsProvider);
      try {
        await ref.read(caseSheetRecordRepositoryProvider).update(resource, id, payload);
        ref.invalidate(caseSheetRecordProvider((resource, id)));
        ref.invalidate(caseSheetRecordListProvider(resource));
        ref.invalidate(caseSheetPendingStatusProvider((resource, id)));
        if (context.mounted) {
          // A `NetworkException` never reaches this catch block — the
          // repository's `update()` queues it locally and returns
          // normally instead (see its own doc comment) — so a queued-vs-
          // synced save both land in this same success path, and the
          // pending-status provider (just invalidated above) is what
          // actually tells them apart for the message shown here.
          final queued = await ref.read(caseSheetPendingStatusProvider((resource, id)).future) is CaseSheetSyncPending;
          final message = queued ? t['caseSheetForm.savedLocallyMsg']! : t['caseSheetForm.savedSuccessMsg']!;
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
          }
        }
      } catch (e) {
        if (context.mounted) {
          final message = e is ApiException ? e.userMessage : t['caseSheetForm.saveFailedMsg']!;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        }
      }
    };
  }

  Future<void> Function(Map<String, dynamic>) _create(BuildContext context, WidgetRef ref, CaseSheetFormSchema schema) {
    return (payload) async {
      final t = ref.read(translationsProvider);
      final authState = ref.read(authControllerProvider).valueOrNull;
      final doctor = authState is Authenticated ? authState.account : null;
      if (doctor is! DoctorAccount) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['caseSheetForm.cannotDetermineDoctorMsg']!)));
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
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['caseSheetForm.recordCreatedMsg']!)));
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
          final message = e is ApiException ? e.userMessage : t['caseSheetForm.createFailedMsg']!;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        }
      }
    };
  }

  /// Fetches `Api\CaseSheetPrintController::show()`'s document JSON and
  /// hands it to `buildCaseSheetPrintPdf`, matching the web's
  /// `CaseSheetPrintRenderer`-driven printout — same source data, same
  /// layout, native print/share sheet instead of a browser tab. The
  /// task-instance QR (when this sheet belongs to one) is fetched the same
  /// way the "رمز الحالة" button above already does, so the printed PDF
  /// carries the same back-link the web sheet's own QR has.
  Future<void> _print(BuildContext context, WidgetRef ref) async {
    if (recordId == null) return;

    try {
      final doc = await ref.read(caseSheetRecordRepositoryProvider).fetchPrintDocument(resource, recordId!);
      final settings = await ref.read(clinicSettingsProvider.future);
      final logo = await loadLetterheadLogo(ref, settings);

      pw.ImageProvider? qr;
      if (taskInstanceId != null) {
        try {
          final bytes = await ref.read(apiClientProvider).getBytes('/task-instances/$taskInstanceId/qr');
          qr = pw.MemoryImage(Uint8List.fromList(bytes));
        } catch (_) {
          // Same "never block the printout over a QR failure" rule the web
          // controller's own qrDataUri() follows.
        }
      }

      final bytes = await buildCaseSheetPrintPdf(doc: doc, settings: settings, logo: logo, qr: qr);
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: '${schemaTitle(ref)}.pdf');
    } catch (e) {
      if (context.mounted) {
        final t = ref.read(translationsProvider);
        final message = e is ApiException ? e.userMessage : t['caseSheetForm.printFailedMsg']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  String schemaTitle(WidgetRef ref) =>
      ref.read(caseSheetFormSchemaProvider(resource)).valueOrNull?.title ?? resource;

  /// "مسح رمز المريض" (2026-08-28) — resolves the scanned registration QR
  /// (same round-trip `/records/patient-registrations/scan-for-task` etc.
  /// already use), then fills in whichever of this resource's mapped
  /// fields exist, one `setFieldIfBlank` call per field — never
  /// overwriting something already typed, per the user's own framing.
  Future<void> _scanPatient(BuildContext context) async {
    final state = await context.push<RegistrationPaymentState>('/case-sheets/scan-patient');
    if (state == null) return;

    final map = kCaseSheetPatientFieldMap[resource];
    final formState = _formStateKey.currentState;
    if (map == null || formState == null) return;

    final r = state.registration;

    // Advanced Periodontal Chart splits the patient's name into two
    // fields — see kCaseSheetPatientFieldMap's own doc comment on this
    // resource's entry for why it's handled here instead of via `map.name`.
    if (resource == 'advanced-periodontal-charts') {
      if (r.name.isNotEmpty) {
        final parts = r.name.trim().split(RegExp(r'\s+'));
        formState.setFieldIfBlank('patient_first_name', parts.first);
        if (parts.length > 1) {
          formState.setFieldIfBlank('patient_last_name', parts.sublist(1).join(' '));
        }
      }
    } else if (map.name != null && r.name.isNotEmpty) {
      formState.setFieldIfBlank(map.name!, r.name);
    }

    if (map.phone != null && r.phone.isNotEmpty) formState.setFieldIfBlank(map.phone!, r.phone);
    if (map.age != null && r.age != null) formState.setFieldIfBlank(map.age!, r.age!.toString());
    if (map.sex != null && r.sex != null) formState.setFieldIfBlank(map.sex!, r.sex!);
    if (map.address != null && r.address != null) formState.setFieldIfBlank(map.address!, r.address!);
    if (map.occupation != null && r.occupation != null) formState.setFieldIfBlank(map.occupation!, r.occupation!);
  }
}
