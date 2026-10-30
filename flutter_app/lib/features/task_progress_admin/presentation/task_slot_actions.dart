import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// `intl` exports its own `TextDirection`-colliding symbol — same
// collision already fixed in `ticket_widget.dart`.
import 'package:intl/intl.dart' hide TextDirection;

import '../../case_sheet_forms/presentation/task_steps_list.dart';
import '../../../core/platform/platform_support.dart';
import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../case_sheet_forms/data/case_sheet_record_repository.dart';
import '../../clinic_settings/domain/clinic_settings.dart';
import '../../clinic_settings/presentation/clinic_settings_providers.dart';
import '../../paper_photos/presentation/paper_photos_sheet.dart';
import '../../printing/data/pos_printer_service.dart';
import '../../printing/presentation/printer_error_snackbar.dart';
import '../../printing/presentation/printer_settings_providers.dart';
import '../../printing/presentation/task_instance_ticket_widget.dart';
import '../../printing/presentation/ticket_print_animation.dart';
import '../../printing/presentation/ticket_renderer.dart';
import '../../form_settings/data/form_settings_repository.dart';
import '../../auth/domain/auth_account.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/auth_state.dart';
import '../data/task_progress_repository.dart';
import '../domain/task_progress_group.dart';
import '../../../core/widgets/numeric_input.dart';

/// A task slot's actions (start, complete, cancel, edit, steps, photos,
/// case sheet, receipt) — moved out of `task_progress_screen.dart`
/// (2026-10-30) so the "enter the case code" screen offers exactly the
/// same actions on the one case a supervisor typed the code of.
mixin TaskSlotActions<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  /// Refreshes whatever list the slot cards came from after an action.
  void reloadSlots();

  /// The case the last start made, read by [reloadSlots] (a task started
  /// from its code then shows as that case).
  int? startedInstanceId;

  /// Requires scanning the patient's registration ticket QR before a task
  /// can be started (2026-08-26, infectious-disease screening gate) —
  /// identifies which patient this instance is for, and gives an
  /// immediate client-side refusal if that patient's screening isn't
  /// `clear` yet, before even prompting for notes. The server enforces
  /// this independently either way (`PatientScreeningGate` inside
  /// `TaskStarter::start()`) — this early check is purely to save the
  /// clerk a wasted round trip.
  Future<void> startTask(
    int doctorId,
    int taskId,
    TaskProgressGroupOption groupOption, {
    int stepsCount = 0,
    String title = '',
  }) async {
    // No patient QR (2026-10-12, by request): the doctor and task picked
    // here (or the case QR) are enough to start it.
    final t = ref.read(translationsProvider);
    final notes = await promptNotes(title: t['taskProgressAdmin.startTask']!);
    if (notes == null) return;
    try {
      final result = await ref.read(taskProgressRepositoryProvider).start(
            doctorId: doctorId,
            taskId: taskId,
            notes: notes,
          );
      startedInstanceId = result.instanceId;
      reloadSlots();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t['taskProgressAdmin.startedSuccess']!)));
      }
      // The task's steps right away, to sign those done at this first
      // session (2026-10-18, by request).
      if (mounted && stepsCount > 0) {
        await showTaskStepsSheet(context, taskInstanceId: result.instanceId, title: title);
        reloadSlots();
      }
      if (mounted) await printReceipt(result, groupOption);
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : t['taskProgressAdmin.startFailed']!;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  /// Prints the same receipt layout for a task slot that was already
  /// started earlier — the printed copy is meant to be re-issuable any
  /// time (a lost/damaged receipt, or just wanting another copy), not
  /// only available at the moment `startTask` first runs. Builds a
  /// `TaskStartResult` from data already on screen (`doctor`/`card`) —
  /// no extra round trip beyond the QR image itself, which `printReceipt`
  /// already fetches fresh.
  Future<void> reprintReceipt(
    TaskProgressDoctorRow doctor,
    String departmentName,
    TaskSlotCard card,
    TaskProgressGroupOption groupOption,
  ) {
    if (card.instanceId == null) return Future.value();
    return printReceipt(
      TaskStartResult(
        instanceId: card.instanceId!,
        status: card.status,
        notes: card.notes,
        assignedDate: card.assignedDate,
        doctorName: doctor.name,
        taskTitle: card.taskTitle,
        departmentName: departmentName,
        startedByName: card.startedByName,
      ),
      groupOption,
    );
  }

  /// Best-effort: the task is already started server-side by the time
  /// this runs, so a print failure must never surface as the start
  /// having failed — same reasoning already established for the
  /// patient-registration ticket (`patient_registration_form_screen.dart::_submit()`).
  Future<void> printReceipt(
    TaskStartResult result,
    TaskProgressGroupOption groupOption,
  ) async {
    if (!canPrintTickets) return;
    try {
      Uint8List? qrBytes;
      try {
        final bytes = await ref.read(apiClientProvider).getBytes(
          '/task-instances/${result.instanceId}/qr',
          query: {'size': 500},
        );
        qrBytes = Uint8List.fromList(bytes);
      } catch (_) {
        qrBytes = null;
      }

      Uint8List? logoBytes;
      ClinicSettings? settings;
      try {
        settings = await ref.read(clinicSettingsProvider.future);
        final logoUrl = settings?.ticketLogoUrl;
        if (logoUrl != null) {
          final bytes = await ref.read(apiClientProvider).getBytes(logoUrl);
          logoBytes = Uint8List.fromList(bytes);
        }
      } catch (_) {
        logoBytes = null;
      }

      if (!mounted) return;
      await precacheTicketImages(context, [qrBytes, logoBytes]);
      if (!mounted) return;
      final printerSettings = await ref.read(printerSettingsProvider.future);
      if (!mounted) return;

      final startedAt = result.assignedDate != null
          ? DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(result.assignedDate!).toLocal())
          : DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

      final pngBytes = await renderWidgetToPng(
        context,
        TaskInstanceTicketWidget(
          doctorName: result.doctorName,
          taskTitle: result.taskTitle,
          departmentName: result.departmentName,
          educationTypeName: groupOption.educationTypeName,
          stageName: groupOption.stageName,
          // A stage's doctors (groups off) carry the stage's name, not a group's.
          groupName: groupOption.id == null ? null : groupOption.name,
          notes: result.notes,
          startedAt: startedAt,
          startedByName: result.startedByName,
          qrBytes: qrBytes,
          logoBytes: logoBytes,
          headerTitle: settings?.universityName ?? settings?.clinicName,
          headerSubtitle: settings?.collegeName,
          widthDots: printerSettings.dotsPerLine,
        ),
      );
      if (!mounted) return;
      await showTicketPrintAnimation<void>(
        context: context,
        ticketPngBytes: pngBytes,
        task: () => ref.read(posPrinterServiceProvider).printTicket(pngBytes),
      );
    } catch (e) {
      if (mounted) {
        final t = ref.read(translationsProvider);
        showPrinterErrorSnackBar(context, t['taskProgressAdmin.printReceiptFailed']!, error: e);
      }
    }
  }

  /// "إلغاء بدء المهمة" (2026-10-23, by request), after a confirmation.
  Future<void> cancelStart(TaskSlotCard card) async {
    final t = ref.read(translationsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t['taskProgressAdmin.cancelStart']!),
        content: Text(trf(t['taskProgressAdmin.cancelStartConfirm']!, {'task': card.taskTitle})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t['taskProgressAdmin.cancelStartKeep']!)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t['taskProgressAdmin.cancelStart']!),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(taskProgressRepositoryProvider).cancelStart(card.instanceId!);
      reloadSlots();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['taskProgressAdmin.cancelStartDone']!)));
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : t['taskProgressAdmin.completeFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  Future<void> completeTask(TaskSlotCard card) async {
    final t = ref.read(translationsProvider);
    final result = await promptGradeNotes(
      title: t['taskProgressAdmin.markComplete']!,
      initialGrade: card.grade,
      initialNotes: card.notes,
    );
    if (result == null) return;
    try {
      await ref
          .read(taskProgressRepositoryProvider)
          .completeInstance(
            card.instanceId!,
            grade: result.$1,
            notes: result.$2,
          );
      reloadSlots();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t['taskProgressAdmin.completedSuccess']!)),
        );
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException
            ? e.userMessage
            : t['taskProgressAdmin.completeFailed']!;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  Future<void> editInstance(TaskSlotCard card) async {
    final t = ref.read(translationsProvider);
    final result = await promptGradeNotes(
      title: t['taskProgressAdmin.editLabel']!,
      initialGrade: card.grade,
      initialNotes: card.notes,
    );
    if (result == null) return;
    try {
      await ref
          .read(taskProgressRepositoryProvider)
          .updateInstance(card.instanceId!, grade: result.$1, notes: result.$2);
      reloadSlots();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t['taskProgressAdmin.savedSuccess']!)));
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : t['taskProgressAdmin.saveFailed']!;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  /// "معاينة الكيس شيت" (2026-08-28) — nothing in this staff/admin screen
  /// could open a case sheet at all before this; `openFor()` resolves
  /// which of the 8 resources this case's task uses, whether a record
  /// already exists, and (staff-only) this viewer's `readonly`/
  /// `supervisor_editable_fields` — see `Api\CaseSheetController::open()`.
  /// A supervisor previews an *existing* filled sheet only: if the doctor
  /// hasn't started filling one in yet, there's nothing to preview or
  /// annotate (staff can't create a record, only edit the 2 supervisor
  /// fields on one that exists), so this shows a message instead of
  /// navigating to a blank create screen.
  Future<void> openCaseSheetPreview(TaskSlotCard card) async {
    try {
      final result = await ref.read(caseSheetRecordRepositoryProvider).openFor(card.instanceId!);
      if (!mounted) return;
      final t = ref.read(translationsProvider);
      if (result.recordId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t['taskProgressAdmin.formNotStartedYet']!)),
        );
        return;
      }
      final fields = result.supervisorEditableFields.join(',');
      context.push(
        '/case-sheets/${result.resource}/${result.recordId}'
        '?task_instances_id=${card.instanceId}'
        '&readonly=${result.readonly ? 1 : 0}'
        '${fields.isEmpty ? '' : '&supervisor_fields=$fields'}',
      );
    } catch (e) {
      if (mounted) {
        final t = ref.read(translationsProvider);
        final message = e is ApiException ? e.userMessage : t['taskProgressAdmin.openFormFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  /// Real bug found and fixed: this used to return only the dialog's
  /// confirm/cancel `bool`, discarding whatever was actually typed into
  /// `controller` — notes typed here never reached the server. Now
  /// returns the typed text itself (`null` on cancel, matching
  /// `promptGradeNotes()`'s own null-means-cancel convention below).
  Future<String?> promptNotes({required String title}) {
    final controller = TextEditingController();
    final t = ref.read(translationsProvider);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: t['taskProgressAdmin.notesOptionalLabel'],
            border: const OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(t['taskProgressAdmin.cancel']!),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(t['taskProgressAdmin.confirmButton']!),
          ),
        ],
      ),
    );
  }

  Future<(double?, String?)?> promptGradeNotes({
    required String title,
    double? initialGrade,
    String? initialNotes,
  }) {
    final gradeController = TextEditingController(
      text: initialGrade?.toString() ?? '',
    );
    final notesController = TextEditingController(text: initialNotes ?? '');
    final t = ref.read(translationsProvider);
    // Grade entry switched off for the whole system (2026-10-22): notes only.
    final gradesOn = (ref.read(taskSwitchesProvider).valueOrNull ?? const FormSettings()).on('grade_entry_enabled');
    return showDialog<(double?, String?)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (gradesOn) ...[
            TextField(
              controller: gradeController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: decimalOnly,
              decoration: InputDecoration(
                labelText: t['taskProgressAdmin.gradeOptionalLabel'],
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ],
            TextField(
              controller: notesController,
              decoration: InputDecoration(
                labelText: t['taskProgressAdmin.notesOptionalLabel'],
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(t['taskProgressAdmin.cancel']!),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop((
              !gradesOn || gradeController.text.trim().isEmpty
                  ? null
                  : double.tryParse(gradeController.text.trim()),
              notesController.text.trim().isEmpty
                  ? null
                  : notesController.text.trim(),
            )),
            child: Text(t['taskProgressAdmin.save']!),
          ),
        ],
      ),
    );
  }
}

class TaskSlotTile extends ConsumerWidget {
  const TaskSlotTile({
    super.key,
    required this.doctor,
    required this.departmentName,
    required this.groupOption,
    required this.card,
    required this.screen,
  });

  final TaskProgressDoctorRow doctor;
  final String departmentName;
  final TaskProgressGroupOption groupOption;
  final TaskSlotCard card;
  final TaskSlotActions screen;

  Color _statusColor(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return switch (card.status) {
      'completed' => Colors.green,
      'assigned' => colors.primary,
      'pending' => Colors.orange,
      _ => colors.outline,
    };
  }

  String _statusLabel(Map<String, String> t) => switch (card.status) {
    'completed' => t['taskProgressAdmin.statusCompleted']!,
    'assigned' => t['taskProgressAdmin.statusInProgress']!,
    'pending' => t['taskProgressAdmin.statusPending']!,
    _ => t['taskProgressAdmin.statusNotStarted']!,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Start and complete switched off for the whole system (2026-10-22).
    final switches = ref.watch(taskSwitchesProvider).valueOrNull ?? const FormSettings();
    final t = ref.watch(translationsProvider);
    final authState = ref.watch(authControllerProvider).valueOrNull;
    final account = authState is Authenticated ? authState.account : null;
    // "إلغاء بدء المهمة" (2026-10-23): the switch and the user's permission.
    final canCancel = switches.on('task_cancel_enabled') && account is StaffAccount && account.can('task_progress', 'cancel');
    return ListTile(
      title: Text('${card.taskTitle} (${card.slot})'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _statusColor(context).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _statusLabel(t),
                  style: TextStyle(
                    color: _statusColor(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              if (card.grade != null) ...[
                const SizedBox(width: 8),
                Text('${t['taskProgressAdmin.gradeColonLabel']} ${card.grade}'),
              ],
              // "كل التواقيع جاهزة" (2026-08-30) — mirrors the web's
              // matching badge (TaskProgress/Index.vue) — see
              // TaskSlotCard.allSigned's doc comment. Never auto-completes
              // anything, just a hint next to the complete button below.
              if (card.allSigned && card.status == 'assigned') ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    t['taskProgressAdmin.allSignedBadge']!,
                    style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
          if (card.notes != null && card.notes!.isNotEmpty)
            Text(card.notes!, style: Theme.of(context).textTheme.bodySmall),
          // A Wrap here (full tile width) rather than as ListTile's
          // `trailing` — with up to four action buttons (start/complete/
          // edit/print), an unconstrained trailing Wrap squeezed the title
          // column down to almost nothing, wrapping "class 1 (1)" one
          // character per line. Found live on-device, not assumed.
          Wrap(
            spacing: 4,
            children: [
              if (card.status == 'unassigned' && switches.on('task_start_enabled'))
                TextButton(
                  onPressed: () => screen.startTask(
                    doctor.id,
                    card.taskId,
                    groupOption,
                    stepsCount: card.stepsCount,
                    title: '${card.taskTitle} - ${doctor.name}',
                  ),
                  child: Text(t['taskProgressAdmin.startTask']!),
                ),
              if (card.status == 'assigned' && switches.on('task_finish_enabled'))
                TextButton(
                  onPressed: () => screen.completeTask(card),
                  style: card.allSigned
                      ? TextButton.styleFrom(backgroundColor: Colors.green.shade50, foregroundColor: Colors.green.shade800)
                      : null,
                  child: Text(t['taskProgressAdmin.markComplete']!),
                ),
              if (card.status == 'assigned' && card.instanceId != null && canCancel)
                TextButton(
                  onPressed: () => screen.cancelStart(card),
                  style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                  child: Text(t['taskProgressAdmin.cancelStart']!),
                ),
              if (card.instanceId != null &&
                  (card.status == 'assigned' || card.status == 'completed'))
                TextButton(
                  onPressed: () => screen.editInstance(card),
                  child: Text(t['taskProgressAdmin.editLabel']!),
                ),
              // The case's steps, signed one after another (2026-10-18).
              if (card.instanceId != null && card.stepsCount > 0 && card.status != 'pending')
                TextButton.icon(
                  onPressed: () async {
                    await showTaskStepsSheet(context, taskInstanceId: card.instanceId!, title: '${card.taskTitle} - ${doctor.name}');
                    screen.reloadSlots();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: card.stepsSigned >= card.stepsCount ? Colors.green.shade800 : Colors.orange.shade800,
                  ),
                  icon: const Icon(Icons.checklist, size: 18),
                  label: Text(trf(t['taskSteps.button']!, {
                    'done': card.stepsSigned.clamp(0, card.stepsCount),
                    'total': card.stepsCount,
                  })),
                ),
              // Photos of the paper case sheet (2026-10-13), as on the web.
              if (card.instanceId != null)
                TextButton.icon(
                  onPressed: () async {
                    await showPaperPhotosSheet(
                      context,
                      instanceId: card.instanceId!,
                      title: '${card.taskTitle} - ${doctor.name}',
                    );
                    screen.reloadSlots();
                  },
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: Text(trf(t['paperPhotos.button']!, {'n': card.attachmentsCount})),
                ),
              // "معاينة الكيس شيت" — staff/admin's view of the doctor's
              // own case sheet (readonly, except the resource's supervisor
              // notes/signature fields — see openCaseSheetPreview above).
              if (card.instanceId != null)
                TextButton(
                  onPressed: () => screen.openCaseSheetPreview(card),
                  child: Text(t['taskProgressAdmin.previewCaseSheet']!),
                ),
              // Reprintable any time after starting — not just at the
              // moment `startTask` first runs (a lost/damaged receipt, or
              // wanting an extra copy).
              if (card.instanceId != null)
                TextButton(
                  onPressed: () => screen.reprintReceipt(doctor, departmentName, card, groupOption),
                  child: Text(t['taskProgressAdmin.printReceiptButton']!),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
