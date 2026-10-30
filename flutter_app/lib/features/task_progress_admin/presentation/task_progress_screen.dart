import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// `intl` exports its own `TextDirection`-colliding symbol — same
// collision already fixed in `ticket_widget.dart`.
import 'package:intl/intl.dart' hide TextDirection;
import 'package:printing/printing.dart';

import '../../case_sheet_forms/presentation/task_steps_list.dart';
import '../../../core/platform/platform_support.dart';
import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/nfc/nfc_uid_reader.dart';
import '../../../core/pdf/pdf_letterhead.dart';
import '../../../core/widgets/academic_year_banner.dart';
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
import '../../task_start_requests/presentation/task_start_request_providers.dart';
import '../../task_start_requests/presentation/task_start_requests_view.dart';
import '../../form_settings/data/form_settings_repository.dart';
import '../../auth/domain/auth_account.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/auth_state.dart';
import '../data/task_progress_repository.dart';
import '../domain/task_progress_group.dart';
import 'task_progress_pdf.dart';
import 'task_progress_providers.dart';
import '../../../core/widgets/numeric_input.dart';
import '../../../core/widgets/tg_spinner.dart';

/// "تقدم المهام" — the full day → education type/stage → group →
/// department (tabs) → doctor (expandable) → per-slot task-card matrix,
/// matching the web's `TaskProgress/Index.vue` exactly (see
/// `App\Services\TaskProgressFilters`/`TaskProgressGroupSummary`, which
/// both this screen's API calls and that Vue page's own controller now
/// share). Supersedes the earlier NFC-only screen — NFC is folded in here
/// as the doctor search box's alternate input (tap to scan instead of
/// typing a name), the same supporting role the web's QR-scan modal plays
/// inside this same page, not a separate screen.
class TaskProgressScreen extends ConsumerStatefulWidget {
  const TaskProgressScreen({super.key, this.initialTab = 'progress'});

  /// 'requests' when opened from a start-request notification (2026-10-15).
  final String initialTab;

  @override
  ConsumerState<TaskProgressScreen> createState() => _TaskProgressScreenState();
}

class _TaskProgressScreenState extends ConsumerState<TaskProgressScreen>
    with SingleTickerProviderStateMixin {
  String? _day;
  int? _educationTypeId;
  int? _stageId;
  int? _groupId;

  TabController? _tabController;
  int _departmentCount = -1;

  final _searchController = TextEditingController();
  bool _scanningNfc = false;
  int? _expandedDoctorId;

  /// 'progress' (the matrix below) or 'requests' — doctors' start
  /// requests (2026-10-14), same as the web's "الطلبات" tab.
  late String _mainTab = widget.initialTab;

  /// Refreshes the start requests (list and badge) so new ones show up
  /// without leaving the screen.
  Timer? _requestsTimer;

  @override
  void initState() {
    super.initState();
    _requestsTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) ref.invalidate(taskStartRequestBoardProvider);
    });
  }

  @override
  void dispose() {
    _requestsTimer?.cancel();
    _searchController.dispose();
    _tabController?.dispose();
    super.dispose();
  }

  void _ensureTabController(int departmentCount) {
    if (_departmentCount == departmentCount) return;
    _departmentCount = departmentCount;
    _tabController?.dispose();
    _tabController = departmentCount > 0
        ? TabController(length: departmentCount, vsync: this)
        : null;
  }

  /// One shared builder for all three of `task_progress_print.php`'s
  /// original print scopes (whole group / one department / one doctor) —
  /// `departmentId`/`doctorId` left null means "whole group", matching
  /// `buildTaskProgressPdf`'s own null-means-unscoped contract.
  Future<void> _printProgress(TaskProgressGroupDetail detail, {int? departmentId, int? doctorId}) async {
    try {
      // .future — see doctor_list_screen.dart's `_printRoster` for why
      // `.valueOrNull` alone can race the provider's first-ever fetch.
      final settings = await ref.read(clinicSettingsProvider.future);
      final logo = await loadLetterheadLogo(ref, settings);
      final bytes = await buildTaskProgressPdf(
        detail: detail,
        settings: settings,
        logo: logo,
        departmentId: departmentId,
        doctorId: doctorId,
      );
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'تقدم المهام.pdf');
    } catch (e) {
      if (mounted) {
        final t = ref.read(translationsProvider);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(trf(t['groupsAdmin.printFailed']!, {'error': e}))));
      }
    }
  }

  Future<void> _scanNfc(TaskProgressGroupDetail detail) async {
    setState(() => _scanningNfc = true);
    try {
      final uid = await NfcUidReader.readUid();
      final result = await ref
          .read(taskProgressRepositoryProvider)
          .nfcScan(uid);

      // Every department shares the same doctor list (see
      // TaskProgressGroupSummary — only their per-department task cards
      // differ), so membership only needs checking once.
      final doctors = detail.departments.isNotEmpty
          ? detail.departments.first.doctors
          : const <TaskProgressDoctorRow>[];
      TaskProgressDoctorRow? match;
      for (final d in doctors) {
        if (d.id == result.doctor.id) {
          match = d;
          break;
        }
      }

      if (!mounted) return;
      final t = ref.read(translationsProvider);
      if (match == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t['taskProgressAdmin.doctorNotInGroup']!),
          ),
        );
        return;
      }

      setState(() {
        _searchController.text = match!.name;
        _expandedDoctorId = match.id;
      });

      if (result.hasPendingTask) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              trf(t['taskProgressAdmin.pendingTaskHint']!, {'name': match.name, 'title': result.task!.title}),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final t = ref.read(translationsProvider);
        final message = e is ApiException
            ? e.userMessage
            : t['doctorsAdmin.nfcScanFailed']!;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _scanningNfc = false);
    }
  }

  /// Requires scanning the patient's registration ticket QR before a task
  /// can be started (2026-08-26, infectious-disease screening gate) —
  /// identifies which patient this instance is for, and gives an
  /// immediate client-side refusal if that patient's screening isn't
  /// `clear` yet, before even prompting for notes. The server enforces
  /// this independently either way (`PatientScreeningGate` inside
  /// `TaskStarter::start()`) — this early check is purely to save the
  /// clerk a wasted round trip.
  Future<void> _startTask(
    int doctorId,
    int taskId,
    TaskProgressGroupOption groupOption, {
    int stepsCount = 0,
    String title = '',
  }) async {
    // No patient QR (2026-10-12, by request): the doctor and task picked
    // here (or the case QR) are enough to start it.
    final t = ref.read(translationsProvider);
    final notes = await _promptNotes(title: t['taskProgressAdmin.startTask']!);
    if (notes == null) return;
    try {
      final result = await ref.read(taskProgressRepositoryProvider).start(
            doctorId: doctorId,
            taskId: taskId,
            notes: notes,
          );
      _reloadGroup();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t['taskProgressAdmin.startedSuccess']!)));
      }
      // The task's steps right away, to sign those done at this first
      // session (2026-10-18, by request).
      if (mounted && stepsCount > 0) {
        await showTaskStepsSheet(context, taskInstanceId: result.instanceId, title: title);
        _reloadGroup();
      }
      if (mounted) await _printReceipt(result, groupOption);
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
  /// only available at the moment `_startTask` first runs. Builds a
  /// `TaskStartResult` from data already on screen (`doctor`/`card`) —
  /// no extra round trip beyond the QR image itself, which `_printReceipt`
  /// already fetches fresh.
  Future<void> _reprintReceipt(
    TaskProgressDoctorRow doctor,
    String departmentName,
    TaskSlotCard card,
    TaskProgressGroupOption groupOption,
  ) {
    if (card.instanceId == null) return Future.value();
    return _printReceipt(
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
  Future<void> _printReceipt(
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
  Future<void> _cancelStart(TaskSlotCard card) async {
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
      _reloadGroup();
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

  Future<void> _completeTask(TaskSlotCard card) async {
    final t = ref.read(translationsProvider);
    final result = await _promptGradeNotes(
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
      _reloadGroup();
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

  Future<void> _editInstance(TaskSlotCard card) async {
    final t = ref.read(translationsProvider);
    final result = await _promptGradeNotes(
      title: t['taskProgressAdmin.editLabel']!,
      initialGrade: card.grade,
      initialNotes: card.notes,
    );
    if (result == null) return;
    try {
      await ref
          .read(taskProgressRepositoryProvider)
          .updateInstance(card.instanceId!, grade: result.$1, notes: result.$2);
      _reloadGroup();
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
  Future<void> _openCaseSheetPreview(TaskSlotCard card) async {
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

  /// Which matrix is open: the tapped group, or — while groups are turned
  /// off in clinic settings — the chosen stage's doctors, with no day or
  /// group step (2026-10-13, same as the web).
  TaskProgressDetailKey? get _detailKey {
    if (ref.read(groupsEnabledProvider)) {
      return _groupId == null ? null : (groupId: _groupId, stageId: null);
    }
    return _stageId == null ? null : (groupId: null, stageId: _stageId);
  }

  void _reloadGroup() {
    final key = _detailKey;
    if (key != null) ref.invalidate(taskProgressGroupProvider(key));
  }

  /// Real bug found and fixed: this used to return only the dialog's
  /// confirm/cancel `bool`, discarding whatever was actually typed into
  /// `controller` — notes typed here never reached the server. Now
  /// returns the typed text itself (`null` on cancel, matching
  /// `_promptGradeNotes()`'s own null-means-cancel convention below).
  Future<String?> _promptNotes({required String title}) {
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

  Future<(double?, String?)?> _promptGradeNotes({
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

  @override
  Widget build(BuildContext context) {
    final filtersAsync = ref.watch(
      taskProgressFiltersProvider((
        day: _day,
        educationTypeId: _educationTypeId,
        stageId: _stageId,
      )),
    );
    final t = ref.watch(translationsProvider);
    final groupsEnabled = ref.watch(groupsEnabledProvider);
    final detailKey = _detailKey;

    return Scaffold(
      appBar: AppBar(
        title: Text(t['taskProgressAdmin.title']!),
        actions: [
          // Scans a printed task receipt's QR (see
          // `TaskInstanceTicketWidget`) and jumps straight to that task
          // instance's detail screen — reuses the existing
          // `QrScanMode.taskInstance` flow (`qr_scan_screen.dart`,
          // `POST /task-instances/scan`) already wired up for doctors on
          // the home screen; this just adds a second entry point so staff
          // don't have to drill through day → type → stage → group →
          // department → doctor to find a task someone hands them a
          // printed receipt for.
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: t['taskProgressAdmin.scanTaskCodeTooltip'],
            onPressed: () => context.push('/scan'),
          ),
          // "إعدادات النماذج" and the supervisor's code (2026-10-22, by request).
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: t['formSettings.open'],
            onPressed: () => context.push('/admin/form-settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          const AcademicYearBanner(),
          _MainTabs(current: _mainTab, onChanged: (v) => setState(() => _mainTab = v)),
          if (_mainTab == 'requests')
            const Expanded(child: TaskStartRequestsView())
          else ...[
          // Hidden once inside a group's detail — its own back arrow
          // already returns here, and keeping three dropdowns permanently
          // on screen competed for space with the doctor list badly enough
          // to overflow when the search box's keyboard opened (found live).
          if (detailKey == null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: filtersAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => Text(t['taskProgressAdmin.loadFiltersFailed']!),
                data: (filters) => _FilterRow(
                  filters: filters,
                  // The day filter was removed (2026-10-13, by request).
                  showDay: false,
                  day: _day,
                  educationTypeId: _educationTypeId,
                  stageId: _stageId,
                  onDayChanged: (v) => setState(() {
                    _day = v;
                    _groupId = null;
                  }),
                  onEducationTypeChanged: (v) => setState(() {
                    _educationTypeId = v;
                    _stageId = null;
                    _groupId = null;
                  }),
                  onStageChanged: (v) => setState(() {
                    _stageId = v;
                    _groupId = null;
                  }),
                ),
              ),
            ),
          Expanded(
            child: detailKey == null
                ? filtersAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (filters) => !groupsEnabled
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                t['taskProgressAdmin.chooseStageHint']!,
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ),
                          )
                        : _stageId == null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                t['taskProgressAdmin.chooseStageHint']!,
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ),
                          )
                        : filters.groups.isEmpty
                        ? Center(child: Text(t['taskProgressAdmin.noMatchingGroups']!))
                        : ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: filters.groups.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final g = filters.groups[i];
                              return Card(
                                child: ListTile(
                                  title: Text(g.name),
                                  subtitle: Text(
                                    [
                                      if (g.stageName != null) g.stageName!,
                                      if (g.educationTypeName != null)
                                        g.educationTypeName!,
                                    ].join(' · '),
                                  ),
                                  trailing: const Icon(Icons.chevron_left),
                                  onTap: () => setState(() {
                                    _groupId = g.id;
                                    _searchController.clear();
                                  }),
                                ),
                              );
                            },
                          ),
                  )
                : _buildGroupDetail(detailKey),
          ),
          ],
        ],
      ),
    );
  }

  Widget _buildGroupDetail(TaskProgressDetailKey key) {
    final groupAsync = ref.watch(taskProgressGroupProvider(key));
    final t = ref.watch(translationsProvider);

    return groupAsync.when(
      loading: () => const Center(child: TgSpinner()),
      error: (error, _) => Center(
        child: Text(
          error is ApiException ? error.userMessage : t['taskProgressAdmin.loadFailed']!,
        ),
      ),
      data: (detail) {
        _ensureTabController(detail.departments.length);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    tooltip: t['taskProgressAdmin.backToGroupsList'],
                    onPressed: () => setState(() {
                      _groupId = null;
                      if (key.stageId != null) _stageId = null;
                    }),
                  ),
                  Expanded(
                    child: Text(
                      detail.groupOption.name,
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.print_outlined),
                    tooltip: t['taskProgressAdmin.printWholeGroupTooltip'],
                    onPressed: () => _printProgress(detail),
                  ),
                ],
              ),
            ),
            if (detail.departments.isEmpty)
              Expanded(
                child: Center(
                  child: Text(t['taskProgressAdmin.noDepartmentsForGroupStage']!),
                ),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      tabs: [for (final d in detail.departments) Tab(text: d.name)],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.print_outlined),
                    tooltip: t['taskProgressAdmin.printDepartmentOnlyTooltip'],
                    onPressed: () => _printProgress(
                      detail,
                      departmentId: detail.departments[_tabController!.index].id,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: t['taskProgressAdmin.searchDoctorHint'],
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: _scanningNfc
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: Padding(
                                padding: EdgeInsets.all(4),
                                child: TgSpinner(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : const Icon(Icons.nfc),
                      tooltip: t['taskProgressAdmin.scanDoctorCardTooltip'],
                      onPressed: _scanningNfc ? null : () => _scanNfc(detail),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    for (final d in detail.departments)
                      _DepartmentDoctorList(
                        department: d,
                        groupOption: detail.groupOption,
                        screen: this,
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// "تقدم المهام" | "الطلبات" pills; the requests pill carries a red badge
/// with the number waiting for approval.
class _MainTabs extends ConsumerWidget {
  const _MainTabs({required this.current, required this.onChanged});
  final String current;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final pending = ref.watch(taskStartRequestBoardProvider).valueOrNull?.pending.length ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          ChoiceChip(
            avatar: const Icon(Icons.monitor_heart_outlined, size: 18),
            label: Text(t['taskRequests.progressTab']!),
            selected: current == 'progress',
            onSelected: (_) => onChanged('progress'),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            avatar: const Icon(Icons.inbox_outlined, size: 18),
            label: Badge(
              isLabelVisible: pending > 0,
              label: Text(pending > 99 ? '99+' : '$pending'),
              offset: const Offset(14, -8),
              child: Text(t['taskRequests.requestsTab']!),
            ),
            selected: current == 'requests',
            onSelected: (_) => onChanged('requests'),
          ),
        ],
      ),
    );
  }
}

class _FilterRow extends ConsumerWidget {
  const _FilterRow({
    required this.filters,
    this.showDay = true,
    required this.day,
    required this.educationTypeId,
    required this.stageId,
    required this.onDayChanged,
    required this.onEducationTypeChanged,
    required this.onStageChanged,
  });

  final TaskProgressFilters filters;

  /// False while groups are turned off: the day only picks groups.
  final bool showDay;
  final String? day;
  final int? educationTypeId;
  final int? stageId;
  final ValueChanged<String?> onDayChanged;
  final ValueChanged<int?> onEducationTypeChanged;
  final ValueChanged<int?> onStageChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    return Column(
      children: [
        if (showDay) ...[
        DropdownButtonFormField<String>(
          initialValue: filters.days.contains(day) ? day : null,
          decoration: InputDecoration(
            labelText: t['taskProgressAdmin.dayLabel'],
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final d in filters.days)
              DropdownMenuItem(value: d, child: Text(d)),
          ],
          onChanged: onDayChanged,
        ),
        const SizedBox(height: 8),
        ],
        DropdownButtonFormField<int>(
          initialValue:
              filters.educationTypes.any((et) => et.id == educationTypeId)
              ? educationTypeId
              : null,
          decoration: InputDecoration(
            labelText: t['taskProgressAdmin.educationTypeOptionalLabel'],
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final et in filters.educationTypes)
              DropdownMenuItem(value: et.id, child: Text(et.name)),
          ],
          onChanged: onEducationTypeChanged,
        ),
        const SizedBox(height: 8),
        // `key` tied to `educationTypeId` — same fix as the appointment
        // form's day→service picker: `DropdownButtonFormField.initialValue`
        // is only read once at first build, so changing education type
        // (which resets `stageId` to null and swaps `filters.stages` to a
        // different list) would otherwise leave this dropdown showing the
        // previous stage selection, which may not even exist in the new
        // items list — a real crash risk, not just a stale display. The
        // key forces a fresh `FormFieldState` whenever education type
        // changes, keeping the dropdown in sync with `stageId`.
        DropdownButtonFormField<int>(
          key: ValueKey('stage-field-$educationTypeId'),
          initialValue: filters.stages.any((s) => s.id == stageId)
              ? stageId
              : null,
          decoration: InputDecoration(
            labelText: t['taskProgressAdmin.stageOptionalLabel'],
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final s in filters.stages)
              DropdownMenuItem(value: s.id, child: Text(s.name)),
          ],
          onChanged: educationTypeId == null ? null : onStageChanged,
        ),
      ],
    );
  }
}

class _DepartmentDoctorList extends ConsumerWidget {
  const _DepartmentDoctorList({
    required this.department,
    required this.groupOption,
    required this.screen,
  });

  final TaskProgressDepartment department;
  final TaskProgressGroupOption groupOption;
  final _TaskProgressScreenState screen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final query = screen._searchController.text.trim();
    final doctors = query.isEmpty
        ? department.doctors
        : department.doctors
              .where(
                (d) =>
                    d.name.contains(query) ||
                    d.username.toLowerCase().contains(query.toLowerCase()),
              )
              .toList();

    if (doctors.isEmpty) {
      return Center(child: Text(t['taskProgressAdmin.noMatchingDoctors']!));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: doctors.length,
      itemBuilder: (context, i) {
        final doctor = doctors[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            initiallyExpanded: doctor.id == screen._expandedDoctorId,
            title: Row(
              children: [
                Expanded(child: Text(doctor.name)),
                IconButton(
                  icon: const Icon(Icons.print_outlined, size: 20),
                  visualDensity: VisualDensity.compact,
                  tooltip: t['taskProgressAdmin.printDoctorTasksTooltip'],
                  onPressed: () => screen._printProgress(
                    TaskProgressGroupDetail(groupOption: groupOption, departments: [department]),
                    doctorId: doctor.id,
                  ),
                ),
              ],
            ),
            subtitle: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                trf(t['taskProgressAdmin.doctorSubtitle']!, {'username': doctor.username, 'completed': doctor.completed, 'required': doctor.required}),
              ),
            ),
            children: [
              for (final card in doctor.tasks)
                _TaskSlotTile(
                  doctor: doctor,
                  departmentName: department.name,
                  groupOption: groupOption,
                  card: card,
                  screen: screen,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TaskSlotTile extends ConsumerWidget {
  const _TaskSlotTile({
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
  final _TaskProgressScreenState screen;

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
                  onPressed: () => screen._startTask(
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
                  onPressed: () => screen._completeTask(card),
                  style: card.allSigned
                      ? TextButton.styleFrom(backgroundColor: Colors.green.shade50, foregroundColor: Colors.green.shade800)
                      : null,
                  child: Text(t['taskProgressAdmin.markComplete']!),
                ),
              if (card.status == 'assigned' && card.instanceId != null && canCancel)
                TextButton(
                  onPressed: () => screen._cancelStart(card),
                  style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                  child: Text(t['taskProgressAdmin.cancelStart']!),
                ),
              if (card.instanceId != null &&
                  (card.status == 'assigned' || card.status == 'completed'))
                TextButton(
                  onPressed: () => screen._editInstance(card),
                  child: Text(t['taskProgressAdmin.editLabel']!),
                ),
              // The case's steps, signed one after another (2026-10-18).
              if (card.instanceId != null && card.stepsCount > 0 && card.status != 'pending')
                TextButton.icon(
                  onPressed: () async {
                    await showTaskStepsSheet(context, taskInstanceId: card.instanceId!, title: '${card.taskTitle} - ${doctor.name}');
                    screen._reloadGroup();
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
                    screen._reloadGroup();
                  },
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: Text(trf(t['paperPhotos.button']!, {'n': card.attachmentsCount})),
                ),
              // "معاينة الكيس شيت" — staff/admin's view of the doctor's
              // own case sheet (readonly, except the resource's supervisor
              // notes/signature fields — see _openCaseSheetPreview above).
              if (card.instanceId != null)
                TextButton(
                  onPressed: () => screen._openCaseSheetPreview(card),
                  child: Text(t['taskProgressAdmin.previewCaseSheet']!),
                ),
              // Reprintable any time after starting — not just at the
              // moment `_startTask` first runs (a lost/damaged receipt, or
              // wanting an extra copy).
              if (card.instanceId != null)
                TextButton(
                  onPressed: () => screen._reprintReceipt(doctor, departmentName, card, groupOption),
                  child: Text(t['taskProgressAdmin.printReceiptButton']!),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
