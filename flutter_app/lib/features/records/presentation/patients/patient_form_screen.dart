import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../data/records_repository.dart';
import '../../domain/patient.dart';
import '../records_providers.dart';

/// `patientId == null` means create. `doctor_id` (the treating `Doctor`,
/// distinct from the staff `doctor_id` on `Appointment` — see that
/// model's doc comment) is left out of this form: it's `nullable` and,
/// unlike `stage_id`, has no lightweight lookup endpoint to populate a
/// dropdown from (`/doctors` is the full paginated admin resource) —
/// deferred rather than built as a heavy picker for a rarely-set field.
class PatientFormScreen extends ConsumerStatefulWidget {
  const PatientFormScreen({super.key, this.patientId});
  final int? patientId;

  @override
  ConsumerState<PatientFormScreen> createState() => _PatientFormScreenState();
}

class _PatientFormScreenState extends ConsumerState<PatientFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  int? _stageId;
  bool _seeded = false;
  bool _submitting = false;

  bool get _isCreate => widget.patientId == null;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _seed(Patient patient) {
    if (_seeded) return;
    _seeded = true;
    _nameController.text = patient.name;
    _phoneController.text = patient.phone ?? '';
    _stageId = patient.stageId;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    setState(() => _submitting = true);

    final payload = {
      'name': _nameController.text.trim(),
      'phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      'stage_id': _stageId,
    };

    try {
      final repo = ref.read(recordsRepositoryProvider);
      if (_isCreate) {
        await repo.createPatient(payload);
      } else {
        await repo.updatePatient(widget.patientId!, payload);
        ref.invalidate(patientProvider(widget.patientId!));
      }
      ref.invalidate(patientListProvider(null));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isCreate ? 'تم إضافة المريض.' : 'تم الحفظ.')));
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
        title: const Text('حذف المريض'),
        content: const Text('هل أنت متأكد من حذف هذا المريض؟'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(recordsRepositoryProvider).deletePatient(widget.patientId!);
      ref.invalidate(patientListProvider(null));
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
    final stagesAsync = ref.watch(stagesLookupProvider);
    final patientAsync = _isCreate ? null : ref.watch(patientProvider(widget.patientId!));

    if (patientAsync != null) {
      switch (patientAsync) {
        case AsyncError(:final error):
          return Scaffold(
            appBar: AppBar(title: const Text('مريض')),
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
        title: Text(_isCreate ? 'مريض جديد' : 'تعديل المريض'),
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
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'الاسم', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'رقم الهاتف', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            stagesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const SizedBox.shrink(),
              data: (stages) => DropdownButtonFormField<int>(
                initialValue: stages.any((s) => s.id == _stageId) ? _stageId : null,
                decoration: const InputDecoration(labelText: 'المرحلة', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: null, child: Text('— بدون —')),
                  for (final s in stages) DropdownMenuItem(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) => setState(() => _stageId = v),
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
