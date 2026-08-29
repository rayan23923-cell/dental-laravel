import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// `intl` exports its own `TextDirection`-colliding symbol — same
// collision already fixed in `ticket_widget.dart`.
import 'package:intl/intl.dart' hide TextDirection;
import 'package:printing/printing.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/nfc/nfc_uid_reader.dart';
import '../../../core/pdf/pdf_letterhead.dart';
import '../../../core/widgets/academic_year_banner.dart';
import '../../case_sheet_forms/data/case_sheet_record_repository.dart';
import '../../clinic_settings/domain/clinic_settings.dart';
import '../../clinic_settings/presentation/clinic_settings_providers.dart';
import '../../patient_registration/domain/registration_payment_state.dart';
import '../../printing/data/pos_printer_service.dart';
import '../../printing/presentation/printer_error_snackbar.dart';
import '../../printing/presentation/printer_settings_providers.dart';
import '../../printing/presentation/task_instance_ticket_widget.dart';
import '../../printing/presentation/ticket_print_animation.dart';
import '../../printing/presentation/ticket_renderer.dart';
import '../data/task_progress_repository.dart';
import '../domain/task_progress_group.dart';
import 'task_progress_pdf.dart';
import 'task_progress_providers.dart';

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
  const TaskProgressScreen({super.key});

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

  @override
  void dispose() {
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إنشاء ملف PDF: $e')));
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
      if (match == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('الطبيب غير موجود ضمن المجموعة المعروضة حالياً.'),
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
              '${match.name}: مهمة معلقة "${result.task!.title}" — افتح صفه لبدئها.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException
            ? e.userMessage
            : 'تعذر التعرف على البطاقة.';
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
    TaskProgressGroupOption groupOption,
  ) async {
    final patientState =
        await context.push<RegistrationPaymentState>('/records/patient-registrations/scan-for-task');
    if (patientState == null || !mounted) return;

    if (!patientState.registration.isScreeningClear) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('لا يمكن بدء المهمة — يجب تأكيد سلامة هذا المريض من الأمراض المعدية أولًا.'),
      ));
      return;
    }

    final notes = await _promptNotes(title: 'بدء المهمة');
    if (notes == null) return;
    try {
      final result = await ref.read(taskProgressRepositoryProvider).start(
            doctorId: doctorId,
            taskId: taskId,
            patientRegistrationId: patientState.registration.id,
            notes: notes,
          );
      _reloadGroup();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم بدء المهمة.')));
      }
      if (mounted) await _printReceipt(result, groupOption);
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : 'تعذر بدء المهمة.';
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
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
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
          groupName: groupOption.name,
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
        showPrinterErrorSnackBar(context, 'تعذرت طباعة الإيصال.', error: e);
      }
    }
  }

  Future<void> _completeTask(TaskSlotCard card) async {
    final result = await _promptGradeNotes(
      title: 'تأشير كمكتملة',
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
          const SnackBar(content: Text('تم تأشير المهمة كمكتملة.')),
        );
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException
            ? e.userMessage
            : 'تعذر إتمام العملية.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  Future<void> _editInstance(TaskSlotCard card) async {
    final result = await _promptGradeNotes(
      title: 'تعديل',
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
        ).showSnackBar(const SnackBar(content: Text('تم الحفظ.')));
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : 'تعذر الحفظ.';
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
      if (result.recordId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لم يبدأ الطبيب تعبئة النموذج بعد.')),
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
        final message = e is ApiException ? e.userMessage : 'تعذر فتح النموذج.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  void _reloadGroup() {
    if (_groupId != null) ref.invalidate(taskProgressGroupProvider(_groupId!));
  }

  /// Real bug found and fixed: this used to return only the dialog's
  /// confirm/cancel `bool`, discarding whatever was actually typed into
  /// `controller` — notes typed here never reached the server. Now
  /// returns the typed text itself (`null` on cancel, matching
  /// `_promptGradeNotes()`'s own null-means-cancel convention below).
  Future<String?> _promptNotes({required String title}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'ملاحظات (اختياري)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('تأكيد'),
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
    return showDialog<(double?, String?)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: gradeController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'الدرجة (اختياري)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(
                labelText: 'ملاحظات (اختياري)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop((
              gradeController.text.trim().isEmpty
                  ? null
                  : double.tryParse(gradeController.text.trim()),
              notesController.text.trim().isEmpty
                  ? null
                  : notesController.text.trim(),
            )),
            child: const Text('حفظ'),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('تقدم المهام'),
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
            tooltip: 'مسح رمز مهمة',
            onPressed: () => context.push('/scan'),
          ),
        ],
      ),
      body: Column(
        children: [
          const AcademicYearBanner(),
          // Hidden once inside a group's detail — its own back arrow
          // already returns here, and keeping three dropdowns permanently
          // on screen competed for space with the doctor list badly enough
          // to overflow when the search box's keyboard opened (found live).
          if (_groupId == null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: filtersAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const Text('تعذر تحميل الفلاتر.'),
                data: (filters) => _FilterRow(
                  filters: filters,
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
            child: _groupId == null
                ? filtersAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (filters) => _day == null
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'اختر اليوم لعرض المجموعات.',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          )
                        : filters.groups.isEmpty
                        ? const Center(child: Text('لا توجد مجموعات مطابقة.'))
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
                : _buildGroupDetail(_groupId!),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupDetail(int groupId) {
    final groupAsync = ref.watch(taskProgressGroupProvider(groupId));

    return groupAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Text(
          error is ApiException ? error.userMessage : 'تعذر التحميل.',
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
                    tooltip: 'رجوع لقائمة المجموعات',
                    onPressed: () => setState(() => _groupId = null),
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
                    tooltip: 'طباعة تقدم المجموعة كاملة (PDF)',
                    onPressed: () => _printProgress(detail),
                  ),
                ],
              ),
            ),
            if (detail.departments.isEmpty)
              const Expanded(
                child: Center(
                  child: Text('لا توجد أقسام لمرحلة هذه المجموعة.'),
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
                    tooltip: 'طباعة هذا القسم فقط (PDF)',
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
                    hintText: 'ابحث عن طبيب بالاسم أو اسم المستخدم...',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: _scanningNfc
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: Padding(
                                padding: EdgeInsets.all(4),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : const Icon(Icons.nfc),
                      tooltip: 'مسح بطاقة الطبيب (NFC)',
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

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.filters,
    required this.day,
    required this.educationTypeId,
    required this.stageId,
    required this.onDayChanged,
    required this.onEducationTypeChanged,
    required this.onStageChanged,
  });

  final TaskProgressFilters filters;
  final String? day;
  final int? educationTypeId;
  final int? stageId;
  final ValueChanged<String?> onDayChanged;
  final ValueChanged<int?> onEducationTypeChanged;
  final ValueChanged<int?> onStageChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DropdownButtonFormField<String>(
          initialValue: filters.days.contains(day) ? day : null,
          decoration: const InputDecoration(
            labelText: 'اليوم',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final d in filters.days)
              DropdownMenuItem(value: d, child: Text(d)),
          ],
          onChanged: onDayChanged,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue:
              filters.educationTypes.any((t) => t.id == educationTypeId)
              ? educationTypeId
              : null,
          decoration: const InputDecoration(
            labelText: 'نوع الدراسة (اختياري)',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final t in filters.educationTypes)
              DropdownMenuItem(value: t.id, child: Text(t.name)),
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
          decoration: const InputDecoration(
            labelText: 'المرحلة (اختياري)',
            border: OutlineInputBorder(),
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

class _DepartmentDoctorList extends StatelessWidget {
  const _DepartmentDoctorList({
    required this.department,
    required this.groupOption,
    required this.screen,
  });

  final TaskProgressDepartment department;
  final TaskProgressGroupOption groupOption;
  final _TaskProgressScreenState screen;

  @override
  Widget build(BuildContext context) {
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
      return const Center(child: Text('لا يوجد أطباء مطابقون.'));
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
                  tooltip: 'طباعة مهام هذا الطبيب (PDF)',
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
                '${doctor.username} — مكتمل ${doctor.completed}/${doctor.required}',
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

class _TaskSlotTile extends StatelessWidget {
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

  String _statusLabel() => switch (card.status) {
    'completed' => 'مكتملة',
    'assigned' => 'قيد التنفيذ',
    'pending' => 'معلّقة',
    _ => 'لم تبدأ بعد',
  };

  @override
  Widget build(BuildContext context) {
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
                  _statusLabel(),
                  style: TextStyle(
                    color: _statusColor(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              if (card.grade != null) ...[
                const SizedBox(width: 8),
                Text('الدرجة: ${card.grade}'),
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
              if (card.status == 'unassigned')
                TextButton(
                  onPressed: () => screen._startTask(doctor.id, card.taskId, groupOption),
                  child: const Text('بدء المهمة'),
                ),
              if (card.status == 'assigned')
                TextButton(
                  onPressed: () => screen._completeTask(card),
                  child: const Text('تأشير كمكتملة'),
                ),
              if (card.instanceId != null &&
                  (card.status == 'assigned' || card.status == 'completed'))
                TextButton(
                  onPressed: () => screen._editInstance(card),
                  child: const Text('تعديل'),
                ),
              // "معاينة الكيس شيت" — staff/admin's view of the doctor's
              // own case sheet (readonly, except the resource's supervisor
              // notes/signature fields — see _openCaseSheetPreview above).
              if (card.instanceId != null)
                TextButton(
                  onPressed: () => screen._openCaseSheetPreview(card),
                  child: const Text('معاينة الكيس شيت'),
                ),
              // Reprintable any time after starting — not just at the
              // moment `_startTask` first runs (a lost/damaged receipt, or
              // wanting an extra copy).
              if (card.instanceId != null)
                TextButton(
                  onPressed: () => screen._reprintReceipt(doctor, departmentName, card, groupOption),
                  child: const Text('طباعة الإيصال'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
