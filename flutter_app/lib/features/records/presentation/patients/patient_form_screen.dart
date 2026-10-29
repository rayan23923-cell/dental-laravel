import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/locale_controller.dart';
import '../../../../core/network/api_exception.dart';
import '../../data/records_repository.dart';
import '../../domain/patient.dart';
import '../records_providers.dart';
import '../../../../core/widgets/numeric_input.dart';
import '../../../../core/widgets/tg_spinner.dart';

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
        final t = ref.read(translationsProvider);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isCreate ? t['recordsHub.patientAddedSuccess']! : t['recordsHub.savedSuccess']!)));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        final t = ref.read(translationsProvider);
        final message = e is ApiException ? e.userMessage : t['recordsHub.saveFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _delete() async {
    final t = ref.read(translationsProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t['recordsHub.deletePatientTitle']!),
        content: Text(t['recordsHub.deletePatientConfirm']!),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t['recordsHub.cancelAction']!)),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(t['recordsHub.deleteAction']!)),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(recordsRepositoryProvider).deletePatient(widget.patientId!);
      ref.invalidate(patientListProvider(null));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['recordsHub.deletedSuccess']!)));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : t['recordsHub.deleteFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stagesAsync = ref.watch(stagesLookupProvider);
    final patientAsync = _isCreate ? null : ref.watch(patientProvider(widget.patientId!));
    final t = ref.watch(translationsProvider);

    if (patientAsync != null) {
      switch (patientAsync) {
        case AsyncError(:final error):
          return Scaffold(
            appBar: AppBar(title: Text(t['recordsHub.patientTitle']!)),
            body: Center(child: Text(error is ApiException ? error.userMessage : t['recordsHub.loadFailed']!)),
          );
        case AsyncData(:final value):
          _seed(value);
        default:
          return const Scaffold(body: Center(child: TgSpinner()));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isCreate ? t['recordsHub.newPatientTitle']! : t['recordsHub.editPatientTitle']!),
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
              decoration: InputDecoration(labelText: t['recordsHub.nameLabel'], border: const OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? t['recordsHub.requiredField'] : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              inputFormatters: phoneOnly,
              decoration: InputDecoration(labelText: t['recordsHub.phoneLabel'], border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            stagesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const SizedBox.shrink(),
              data: (stages) => DropdownButtonFormField<int>(
                initialValue: stages.any((s) => s.id == _stageId) ? _stageId : null,
                decoration: InputDecoration(labelText: t['recordsHub.stageLabel'], border: const OutlineInputBorder()),
                items: [
                  DropdownMenuItem(value: null, child: Text(t['recordsHub.noneOption']!)),
                  for (final s in stages) DropdownMenuItem(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) => setState(() => _stageId = v),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(height: 20, width: 20, child: TgSpinner(strokeWidth: 2))
                  : Text(t['recordsHub.saveButton']!),
            ),
          ],
        ),
      ),
    );
  }
}
