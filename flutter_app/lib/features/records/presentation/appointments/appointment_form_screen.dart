import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/widgets/cascading_dropdown.dart';
import '../../../auth/domain/auth_account.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../auth/presentation/auth_state.dart';
import '../../../patient_registration/domain/patient_registration.dart';
import '../../../patient_registration/presentation/patient_registration_list_screen.dart';
import '../../data/records_repository.dart';
import '../../domain/appointment.dart';
import '../records_providers.dart';

/// `appointmentId == null` means create. `doctor_id` (really "staff
/// member in charge" — see `Appointment`'s doc comment) is silently
/// filled with the logged-in staff user's own id, never shown as a
/// picker: there's no `/users` list endpoint in this API to populate one
/// from (the web app's own form builds it straight from `User::all()`
/// inside the Inertia controller, with no API equivalent needed there),
/// and defaulting to self mirrors the same precedent already used for
/// case-sheet creation's `doctor_id`.
class AppointmentFormScreen extends ConsumerStatefulWidget {
  const AppointmentFormScreen({super.key, this.appointmentId});
  final int? appointmentId;

  @override
  ConsumerState<AppointmentFormScreen> createState() => _AppointmentFormScreenState();
}

class _AppointmentFormScreenState extends ConsumerState<AppointmentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  PatientRegistration? _registration;
  int? _taskId;
  DateTime? _appointmentDate;
  bool _confirmedByAccountant = false;
  bool _pinned = false;
  bool _seeded = false;
  bool _submitting = false;

  bool get _isCreate => widget.appointmentId == null;

  @override
  void dispose() {
    _fullNameController.dispose();
    super.dispose();
  }

  void _seed(Appointment appointment) {
    if (_seeded) return;
    _seeded = true;
    _fullNameController.text = appointment.fullName;
    _taskId = appointment.taskId;
    _appointmentDate = appointment.appointmentDate == null ? null : DateTime.tryParse(appointment.appointmentDate!);
    _confirmedByAccountant = appointment.confirmedByAccountant;
    _pinned = appointment.pinned;
    if (appointment.patientRegistrationId != null) {
      _registration = PatientRegistration(
        id: appointment.patientRegistrationId!,
        name: appointment.patientRegistrationName ?? 'مريض #${appointment.patientRegistrationId}',
        phone: appointment.patientRegistrationPhone ?? '',
        serviceId: null,
        registerDayId: null,
        serviceName: null,
        registerDayName: null,
        createdAt: null,
        taskId: null,
        taskTitle: null,
        stageName: null,
        educationTypeName: null,
        // Unknown here — see the identical seed in `payment_form_screen.dart`.
        screeningStatus: 'pending',
      );
    }
  }

  Future<void> _pickRegistration() async {
    final picked = await Navigator.of(context).push<PatientRegistration>(
      MaterialPageRoute(builder: (_) => const PatientRegistrationListScreen(pickMode: true)),
    );
    if (picked != null) setState(() => _registration = picked);
  }

  Future<void> _pickDate() async {
    // Clamped, not just `DateTime.now()` — a misconfigured device clock
    // (confirmed live: one test device reads year 2010) falls before
    // `firstDate` and trips `showDatePicker`'s own assertion, crashing
    // the picker outright instead of just showing a wrong default month.
    final firstDate = DateTime(2020);
    final lastDate = DateTime(2100);
    var initialDate = _appointmentDate ?? DateTime.now();
    if (initialDate.isBefore(firstDate)) initialDate = firstDate;
    if (initialDate.isAfter(lastDate)) initialDate = lastDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked != null) setState(() => _appointmentDate = picked);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    // A registration pick is required to create a new appointment, but an
    // edit of a legacy appointment (patient_id only, no registration to
    // pre-fill) must stay allowed without forcing one retroactively — same
    // partial-update contract as the API's own `sometimes` rule.
    if ((_isCreate && _registration == null) || _taskId == null || _appointmentDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى اختيار المريض والمهمة والتاريخ.')));
      return;
    }

    final authState = ref.read(authControllerProvider).valueOrNull;
    final account = authState is Authenticated ? authState.account : null;
    if (account is! StaffAccount) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر تحديد المستخدم الحالي.')));
      return;
    }

    setState(() => _submitting = true);

    final payload = {
      'full_name': _fullNameController.text.trim(),
      if (_registration != null) 'patient_registration_id': _registration!.id,
      'doctor_id': account.id,
      'task_id': _taskId,
      'appointment_date': DateFormat('yyyy-MM-dd').format(_appointmentDate!),
      'confirmed_by_accountant': _confirmedByAccountant,
      'pinned': _pinned,
    };

    try {
      final repo = ref.read(recordsRepositoryProvider);
      if (_isCreate) {
        await repo.createAppointment(payload);
      } else {
        await repo.updateAppointment(widget.appointmentId!, payload);
      }
      ref.invalidate(appointmentListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isCreate ? 'تم إضافة الموعد.' : 'تم الحفظ.')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : 'تعذر الحفظ.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الموعد'),
        content: const Text('هل أنت متأكد من حذف هذا الموعد؟'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(recordsRepositoryProvider).deleteAppointment(widget.appointmentId!);
      ref.invalidate(appointmentListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحذف.')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : 'تعذر الحذف.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(tasksLookupProvider);
    final appointmentAsync = _isCreate ? null : ref.watch(appointmentProvider(widget.appointmentId!));

    if (appointmentAsync != null) {
      switch (appointmentAsync) {
        case AsyncError(:final error):
          return Scaffold(
            appBar: AppBar(title: const Text('موعد')),
            body: Center(child: Text(error is ApiException ? error.userMessage : 'تعذر التحميل.')),
          );
        case AsyncData(:final value):
          _seed(value);
        default:
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isCreate ? 'موعد جديد' : 'تعديل الموعد'),
        actions: [
          if (!_isCreate) IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _fullNameController,
              decoration: const InputDecoration(labelText: 'الاسم الكامل', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null,
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickRegistration,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'المريض المسجل', border: OutlineInputBorder(), isDense: true),
                child: Text(_registration?.name ?? '— اختر مريضًا مسجلاً —'),
              ),
            ),
            if (!_isCreate && _registration == null)
              const Padding(
                padding: EdgeInsets.only(top: 4, right: 4),
                child: Text(
                  'هذا الموعد قديم ومرتبط بجدول المرضى السابق مباشرة — اتركه فارغًا للإبقاء عليه كما هو.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            const SizedBox(height: 16),
            // `CascadingDropdown` (`core/widgets/cascading_dropdown.dart`)
            // instead of a plain dropdown — this list had no search at
            // all before, unlike every other admin task/diagnosis picker
            // in the app.
            CascadingDropdown(
              label: 'المهمة',
              itemsAsync: tasksAsync,
              value: _taskId,
              onChanged: (v) => setState(() => _taskId = v),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'تاريخ الموعد',
                  border: OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: Icon(Icons.calendar_today, size: 18),
                ),
                child: Text(_appointmentDate == null ? '— اختر تاريخًا —' : DateFormat('yyyy-MM-dd').format(_appointmentDate!)),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('مؤكد من المحاسب'),
              value: _confirmedByAccountant,
              onChanged: (v) => setState(() => _confirmedByAccountant = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('مثبت (Pinned)'),
              value: _pinned,
              onChanged: (v) => setState(() => _pinned = v),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}
