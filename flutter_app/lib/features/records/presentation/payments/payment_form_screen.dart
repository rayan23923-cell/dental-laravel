import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/api_exception.dart';
import '../../../patient_registration/domain/patient_registration.dart';
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
    if (picked != null) setState(() => _registration = picked);
  }

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
                if (v != null) setState(() => _source = v);
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
            else
              InkWell(
                onTap: _pickRegistration,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'المريض المسجل', border: OutlineInputBorder(), isDense: true),
                  child: Text(_registration?.name ?? '— اختر مريضًا مسجلاً —'),
                ),
              ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'المبلغ', border: OutlineInputBorder()),
              validator: (v) => (v == null || double.tryParse(v.trim()) == null) ? 'أدخل مبلغًا صحيحًا' : null,
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
