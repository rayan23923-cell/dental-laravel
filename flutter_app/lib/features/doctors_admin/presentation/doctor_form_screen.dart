import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/nfc/nfc_uid_reader.dart';
import '../data/doctors_admin_repository.dart';
import '../domain/doctor_admin.dart';
import 'doctors_admin_providers.dart';
import '../../../core/widgets/numeric_input.dart';

/// `doctorId == null` means create. `password` is required on create,
/// optional on edit (blank = unchanged) — matches
/// `Api\DoctorController::validateDoctor()` exactly.
class DoctorFormScreen extends ConsumerStatefulWidget {
  const DoctorFormScreen({super.key, this.doctorId});
  final int? doctorId;

  @override
  ConsumerState<DoctorFormScreen> createState() => _DoctorFormScreenState();
}

class _DoctorFormScreenState extends ConsumerState<DoctorFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nfcTagIdController = TextEditingController();
  int? _educationTypeId;
  int? _stageId;
  bool _seeded = false;
  bool _submitting = false;
  bool _scanningNfc = false;

  bool get _isCreate => widget.doctorId == null;

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _nfcTagIdController.dispose();
    super.dispose();
  }

  void _seed(DoctorAdmin doctor) {
    if (_seeded) return;
    _seeded = true;
    _nameController.text = doctor.name;
    _usernameController.text = doctor.username;
    _emailController.text = doctor.email;
    _phoneController.text = doctor.phone ?? '';
    _educationTypeId = doctor.educationTypeId;
    _stageId = doctor.stageId;
    _nfcTagIdController.text = doctor.nfcTagId ?? '';
  }

  /// Only the Flutter app can read NFC — this just fills the text field,
  /// the existing "حفظ" button persists it like any other field, so no
  /// separate "link" endpoint is needed.
  Future<void> _scanNfcTag() async {
    setState(() => _scanningNfc = true);
    try {
      final uid = await NfcUidReader.readUid();
      _nfcTagIdController.text = uid;
      if (mounted) {
        final t = ref.read(translationsProvider);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(trf(t['doctorsAdmin.nfcTagScannedMsg']!, {'uid': uid}))));
      }
    } catch (e) {
      if (mounted) {
        final t = ref.read(translationsProvider);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(trf(t['doctorsAdmin.nfcTagScanFailedMsg']!, {'error': e}))));
      }
    } finally {
      if (mounted) setState(() => _scanningNfc = false);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    setState(() => _submitting = true);

    final payload = {
      'name': _nameController.text.trim(),
      'username': _usernameController.text.trim(),
      'email': _emailController.text.trim(),
      'phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      'education_type_id': _educationTypeId,
      'stage_id': _stageId,
      if (_isCreate || _passwordController.text.isNotEmpty) 'password': _passwordController.text,
      'nfc_tag_id': _nfcTagIdController.text.trim().isEmpty ? null : _nfcTagIdController.text.trim().toUpperCase(),
    };

    try {
      final repo = ref.read(doctorsAdminRepositoryProvider);
      if (_isCreate) {
        await repo.create(payload);
      } else {
        await repo.update(widget.doctorId!, payload);
        ref.invalidate(doctorAdminProvider(widget.doctorId!));
      }
      ref.invalidate(doctorAdminListProvider);
      if (mounted) {
        final t = ref.read(translationsProvider);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isCreate ? t['doctorsAdmin.addedSuccess']! : t['doctorsAdmin.savedSuccess']!)));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        final t = ref.read(translationsProvider);
        final message = e is ApiException ? e.userMessage : t['doctorsAdmin.saveFailed']!;
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
        title: Text(t['doctorsAdmin.deleteTitle']!),
        content: Text(t['doctorsAdmin.deleteConfirmBody']!),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t['nav.cancel']!)),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(t['doctorsAdmin.delete']!)),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(doctorsAdminRepositoryProvider).delete(widget.doctorId!);
      ref.invalidate(doctorAdminListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['doctorsAdmin.deletedSuccess']!)));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : t['doctorsAdmin.deleteFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final educationTypesAsync = ref.watch(doctorEducationTypesProvider);
    final stagesAsync = ref.watch(doctorStagesProvider);
    final doctorAsync = _isCreate ? null : ref.watch(doctorAdminProvider(widget.doctorId!));
    final t = ref.watch(translationsProvider);

    if (doctorAsync != null) {
      switch (doctorAsync) {
        case AsyncError(:final error):
          return Scaffold(
            appBar: AppBar(title: Text(t['doctorsAdmin.singularTitle']!)),
            body: Center(child: Text(error is ApiException ? error.userMessage : t['doctorsAdmin.loadFailed']!)),
          );
        case AsyncData(:final value):
          _seed(value);
        default:
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isCreate ? t['doctorsAdmin.newTitle']! : t['doctorsAdmin.editTitle']!),
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
              decoration: InputDecoration(labelText: t['doctorsAdmin.nameLabel'], border: const OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? t['doctorsAdmin.requiredField'] : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _usernameController,
              decoration: InputDecoration(labelText: t['doctorsAdmin.usernameLabel'], border: const OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? t['doctorsAdmin.requiredField'] : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              inputFormatters: digitsOnly,
              decoration: InputDecoration(labelText: t['doctorsAdmin.emailLabel'], border: const OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? t['doctorsAdmin.requiredField'] : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              inputFormatters: phoneOnly,
              decoration: InputDecoration(labelText: t['doctorsAdmin.phoneLabel'], border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            educationTypesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => Text(t['doctorsAdmin.loadEducationTypeFailed']!),
              data: (types) => DropdownButtonFormField<int>(
                initialValue: types.any((et) => et.id == _educationTypeId) ? _educationTypeId : null,
                decoration: InputDecoration(labelText: t['doctorsAdmin.educationTypeLabel'], border: const OutlineInputBorder()),
                items: [for (final et in types) DropdownMenuItem(value: et.id, child: Text(et.name))],
                onChanged: (v) => setState(() {
                  _educationTypeId = v;
                  _stageId = null;
                }),
                validator: (v) => v == null ? t['doctorsAdmin.requiredField'] : null,
              ),
            ),
            const SizedBox(height: 16),
            // Real bug, found live: this dropdown used to list every stage
            // regardless of the education type picked above (unlike
            // task_form_screen.dart's already-correct cascade). Disabled
            // until an education type is chosen, then narrowed to it —
            // matches Doctors/Create.vue's own filteredStages/:disabled
            // pattern on the web.
            stagesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => Text(t['doctorsAdmin.loadStageFailed']!),
              data: (allStages) {
                final stages =
                    _educationTypeId == null ? allStages : allStages.where((s) => s.educationTypeId == _educationTypeId).toList();
                return DropdownButtonFormField<int>(
                  key: ValueKey('stage-$_educationTypeId'),
                  initialValue: stages.any((s) => s.id == _stageId) ? _stageId : null,
                  decoration: InputDecoration(
                    labelText: t['doctorsAdmin.stageLabel'],
                    border: const OutlineInputBorder(),
                    helperText: _educationTypeId == null ? t['doctorsAdmin.chooseEducationTypeFirst'] : null,
                  ),
                  items: [for (final s in stages) DropdownMenuItem(value: s.id, child: Text(s.name))],
                  onChanged: _educationTypeId == null ? null : (v) => setState(() => _stageId = v),
                  validator: (v) => v == null ? t['doctorsAdmin.requiredField'] : null,
                );
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: _isCreate ? t['doctorsAdmin.passwordLabel'] : t['doctorsAdmin.newPasswordOptionalLabel'],
                border: const OutlineInputBorder(),
              ),
              validator: (v) {
                if (_isCreate && (v == null || v.length < 6)) return t['doctorsAdmin.passwordTooShort'];
                if (!_isCreate && v != null && v.isNotEmpty && v.length < 6) return t['doctorsAdmin.passwordTooShort'];
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nfcTagIdController,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: t['doctorsAdmin.nfcTagLabel'],
                border: const OutlineInputBorder(),
                suffixIcon: _scanningNfc
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(icon: const Icon(Icons.nfc), tooltip: t['doctorsAdmin.scanTagTooltip'], onPressed: _scanNfcTag),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(t['doctorsAdmin.save']!),
            ),
          ],
        ),
      ),
    );
  }
}
