import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/api_exception.dart';
import '../../../patient_registration/domain/patient_registration.dart';
import '../../../patient_registration/domain/registration_payment_state.dart';
import '../../../patient_registration/presentation/patient_registration_list_screen.dart';
import '../../data/records_repository.dart';
import '../../domain/appointment.dart';
import '../../domain/payment.dart';
import '../appointments/appointment_list_screen.dart';
import '../records_providers.dart';

class PaymentFormScreen extends ConsumerStatefulWidget {
  const PaymentFormScreen({super.key, this.paymentId});
  final int? paymentId;

  @override
  ConsumerState<PaymentFormScreen> createState() => _PaymentFormScreenState();
}

class _PaymentFormScreenState extends ConsumerState<PaymentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _paidByController = TextEditingController();
  Appointment? _appointment;
  PatientRegistration? _registration;
  // Screening confirmation (2026-08-29) — set instead of `_registration`
  // when a resolved patient (scan or list-pick) isn't screening-clear, so
  // the blocked banner can show who was rejected and why, mirroring the
  // reception-desk `PatientRegistrationPaymentScreen`'s
  // `_ScreeningBlockedBanner`. `PatientScreeningGate` still enforces this
  // server-side regardless — this is purely earlier client-side feedback.
  PatientRegistration? _blockedRegistration;
  bool _scanningRegistration = false;
  // A payment settles either an appointment or a reception-desk
  // registration — never both (see Api\PaymentController::validatePayment()'s
  // required_without/prohibits pair). Mirrors the web Create.vue's toggle.
  String _source = 'appointment';
  DateTime? _paidAt;
  bool _seeded = false;
  bool _submitting = false;

  bool get _isCreate => widget.paymentId == null;

  @override
  void dispose() {
    _amountController.dispose();
    _paidByController.dispose();
    super.dispose();
  }

  void _seed(Payment payment) {
    if (_seeded) return;
    _seeded = true;
    _amountController.text = payment.amount.toStringAsFixed(2);
    _paidByController.text = payment.paidBy ?? '';
    _paidAt = payment.paidAt == null ? null : DateTime.tryParse(payment.paidAt!);
    if (payment.patientRegistrationId != null) {
      _source = 'registration';
      _registration = PatientRegistration(
        id: payment.patientRegistrationId!,
        name: payment.patientRegistrationName ?? 'تسجيل #${payment.patientRegistrationId}',
        phone: payment.patientRegistrationPhone ?? '',
        age: null,
        sex: null,
        address: null,
        occupation: null,
        serviceId: null,
        registerDayId: null,
        serviceName: null,
        registerDayName: null,
        createdAt: null,
        taskId: null,
        taskTitle: null,
        stageName: null,
        educationTypeName: null,
        // Unknown here — this seed comes from `Payment`'s denormalized
        // fields, not a fresh fetch, and this manual-entry form doesn't
        // gate on screening status anyway (only the QR desk flow does).
        screeningStatus: 'pending',
      );
    } else if (payment.appointmentId != null) {
      _source = 'appointment';
      _appointment = Appointment(
        id: payment.appointmentId!,
        fullName: payment.appointmentFullName ?? 'موعد #${payment.appointmentId}',
        patientId: null,
        patientRegistrationId: null,
        doctorId: null,
        taskId: null,
        appointmentDate: null,
        confirmedByAccountant: false,
        pinned: false,
        patientName: null,
        patientRegistrationName: null,
        patientRegistrationPhone: null,
        staffName: null,
        taskTitle: null,
        paidTotal: null,
      );
    }
  }

  Future<void> _pickAppointment() async {
    final picked = await Navigator.of(context).push<Appointment>(
      MaterialPageRoute(builder: (_) => const AppointmentListScreen(pickMode: true)),
    );
    if (picked != null) setState(() => _appointment = picked);
  }

  Future<void> _pickRegistration() async {
    final picked = await Navigator.of(context).push<PatientRegistration>(
      MaterialPageRoute(builder: (_) => const PatientRegistrationListScreen(pickMode: true)),
    );
    if (picked != null) _applyRegistration(picked);
  }

  /// "مسح رمز المريض" (2026-08-29) — scans the same reception-desk ticket
  /// QR used elsewhere, resolving it to a registration the same way
  /// `_pickRegistration()`'s list-picker does, just faster than typing a
  /// search. Reuses the staff-gated `patient-registrations/scan` endpoint
  /// (this whole screen is staff-only — see `RecordsHubScreen`), unlike
  /// the doctor-only case-sheet autofill scan.
  Future<void> _scanRegistration() async {
    setState(() => _scanningRegistration = true);
    try {
      final result = await context.push<RegistrationPaymentState>('/records/patient-registrations/scan-for-payment');
      if (result != null) _applyRegistration(result.registration);
    } finally {
      if (mounted) setState(() => _scanningRegistration = false);
    }
  }

  /// Shared by both resolution paths (scan and list-pick) — a patient who
  /// isn't screening-clear is shown as blocked rather than accepted, so
  /// the clerk sees why immediately instead of typing an amount only to
  /// have `PatientScreeningGate` reject the submit.
  void _applyRegistration(PatientRegistration registration) {
    setState(() {
      if (registration.isScreeningClear) {
        _registration = registration;
        _blockedRegistration = null;
      } else {
        _registration = null;
        _blockedRegistration = registration;
      }
    });
  }

  // Quick-digit amount entry (2026-08-29) — matches the reception-desk
  // `PatientRegistrationPaymentScreen` and web `Payments/Create.vue`'s
  // identical "0"/"00"/"000" append buttons, for consistent, fast amount
  // entry across every platform this app ships on.
  void _appendDigits(String digits) {
    setState(() {
      _amountController.text += digits;
      _amountController.selection = TextSelection.collapsed(offset: _amountController.text.length);
    });
  }

  void _clearAmount() => setState(() => _amountController.clear());

  Future<void> _pickPaidAt() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidAt ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _paidAt = picked);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    if (_source == 'appointment' && _appointment == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى اختيار الموعد.')));
      return;
    }
    if (_source == 'registration' && _registration == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى اختيار المريض المسجل.')));
      return;
    }

    setState(() => _submitting = true);

    final payload = {
      'appointment_id': _source == 'appointment' ? _appointment!.id : null,
      'patient_registration_id': _source == 'registration' ? _registration!.id : null,
      'amount': double.tryParse(_amountController.text.trim()) ?? 0,
      'paid_by': _paidByController.text.trim().isEmpty ? null : _paidByController.text.trim(),
      'paid_at': _paidAt == null ? null : DateFormat('yyyy-MM-dd').format(_paidAt!),
    };

    try {
      final repo = ref.read(recordsRepositoryProvider);
      if (_isCreate) {
        await repo.createPayment(payload);
      } else {
        await repo.updatePayment(widget.paymentId!, payload);
      }
      ref.invalidate(paymentListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isCreate ? 'تم إضافة الدفعة.' : 'تم الحفظ.')));
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
        title: const Text('حذف الدفعة'),
        content: const Text('هل أنت متأكد من حذف هذه الدفعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(recordsRepositoryProvider).deletePayment(widget.paymentId!);
      ref.invalidate(paymentListProvider);
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
    final paymentAsync = _isCreate ? null : ref.watch(paymentProvider(widget.paymentId!));

    if (paymentAsync != null) {
      switch (paymentAsync) {
        case AsyncError(:final error):
          return Scaffold(
            appBar: AppBar(title: const Text('دفعة')),
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
        title: Text(_isCreate ? 'دفعة جديدة' : 'تعديل الدفعة'),
        actions: [
          if (!_isCreate) IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('نوع المدفوعة', style: Theme.of(context).textTheme.titleSmall),
            RadioGroup<String>(
              groupValue: _source,
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _source = v;
                  if (v == 'appointment') _blockedRegistration = null;
                });
              },
              child: const Row(
                children: [
                  Expanded(child: RadioListTile<String>(title: Text('موعد'), value: 'appointment')),
                  Expanded(child: RadioListTile<String>(title: Text('تسجيل مريض'), value: 'registration')),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (_source == 'appointment')
              InkWell(
                onTap: _pickAppointment,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'الموعد', border: OutlineInputBorder(), isDense: true),
                  child: Text(_appointment?.fullName ?? '— اختر موعدًا —'),
                ),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _pickRegistration,
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'المريض المسجل', border: OutlineInputBorder(), isDense: true),
                        child: Text(_registration?.name ?? '— اختر مريضًا مسجلاً —'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _scanningRegistration
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : IconButton.filledTonal(
                          onPressed: _scanRegistration,
                          icon: const Icon(Icons.qr_code_scanner),
                          tooltip: 'مسح رمز المريض',
                        ),
                ],
              ),
              // Screening confirmation (2026-08-29) — see `_applyRegistration()`.
              // `PatientScreeningGate` still enforces this server-side
              // regardless; this is earlier, clearer client-side feedback.
              if (_blockedRegistration != null)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.block, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _blockedRegistration!.screeningStatus == 'flagged'
                              ? 'لا يمكن الدفع — نتيجة فحص "${_blockedRegistration!.name}" غير سليمة.'
                              : 'لا يمكن الدفع قبل تأكيد سلامة "${_blockedRegistration!.name}" من الأمراض المعدية عبر فحص المختبر.',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'المبلغ', border: OutlineInputBorder()),
              validator: (v) => (v == null || double.tryParse(v.trim()) == null) ? 'أدخل مبلغًا صحيحًا' : null,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final digits in const ['0', '00', '000'])
                  OutlinedButton(onPressed: () => _appendDigits(digits), child: Text(digits)),
                OutlinedButton.icon(
                  onPressed: _clearAmount,
                  icon: const Icon(Icons.backspace_outlined),
                  label: const Text('مسح'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _paidByController,
              decoration: const InputDecoration(labelText: 'دفع بواسطة', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickPaidAt,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'تاريخ الدفع',
                  border: OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: Icon(Icons.calendar_today, size: 18),
                ),
                child: Text(_paidAt == null ? '— اختر تاريخًا —' : DateFormat('yyyy-MM-dd').format(_paidAt!)),
              ),
            ),
            const SizedBox(height: 24),
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
