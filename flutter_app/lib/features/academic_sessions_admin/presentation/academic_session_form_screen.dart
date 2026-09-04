import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../data/academic_sessions_repository.dart';
import '../domain/academic_session_admin.dart';
import 'academic_sessions_providers.dart';

/// `sessionId == null` means create. Mirrors `AcademicSessions/Index.vue`'s
/// modal form fields exactly: name, start/end date, is_active, is_current.
class AcademicSessionFormScreen extends ConsumerStatefulWidget {
  const AcademicSessionFormScreen({super.key, this.sessionId});
  final int? sessionId;

  @override
  ConsumerState<AcademicSessionFormScreen> createState() => _AcademicSessionFormScreenState();
}

class _AcademicSessionFormScreenState extends ConsumerState<AcademicSessionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isActive = true;
  bool _isCurrent = false;
  bool _seeded = false;
  bool _submitting = false;

  bool get _isCreate => widget.sessionId == null;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _seed(AcademicSessionAdmin session) {
    if (_seeded) return;
    _seeded = true;
    _nameController.text = session.name;
    _startDate = DateTime.tryParse(session.startDate);
    _endDate = DateTime.tryParse(session.endDate);
    _isActive = session.isActive;
    _isCurrent = session.isCurrent;
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = (isStart ? _startDate : _endDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    final t = ref.read(translationsProvider);
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['academicSessionsAdmin.datesRequiredMsg']!)));
      return;
    }
    if (_endDate!.isBefore(_startDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['academicSessionsAdmin.endAfterStartMsg']!)));
      return;
    }
    setState(() => _submitting = true);

    final payload = {
      'name': _nameController.text.trim(),
      'start_date': _formatDate(_startDate!),
      'end_date': _formatDate(_endDate!),
      'is_active': _isActive,
      'is_current': _isCurrent,
    };

    try {
      final repo = ref.read(academicSessionsRepositoryProvider);
      if (_isCreate) {
        await repo.create(payload);
      } else {
        await repo.update(widget.sessionId!, payload);
        ref.invalidate(academicSessionDetailProvider(widget.sessionId!));
      }
      ref.invalidate(academicSessionListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isCreate ? t['academicSessionsAdmin.addedSuccess']! : t['academicSessionsAdmin.savedSuccess']!)));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        final t = ref.read(translationsProvider);
        final message = e is ApiException ? e.userMessage : t['academicSessionsAdmin.saveFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = _isCreate ? null : ref.watch(academicSessionDetailProvider(widget.sessionId!));
    final t = ref.watch(translationsProvider);

    if (detailAsync != null) {
      switch (detailAsync) {
        case AsyncError(:final error):
          return Scaffold(
            appBar: AppBar(title: Text(t['academicSessionsAdmin.singularTitle']!)),
            body: Center(child: Text(error is ApiException ? error.userMessage : t['academicSessionsAdmin.loadFailed']!)),
          );
        case AsyncData(:final value):
          _seed(value.session);
        default:
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(_isCreate ? t['academicSessionsAdmin.newTitle']! : t['academicSessionsAdmin.editTitle']!)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(labelText: t['academicSessionsAdmin.nameLabel'], border: const OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? t['academicSessionsAdmin.requiredField'] : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDate(isStart: true),
                    child: Text(_startDate == null ? t['academicSessionsAdmin.startDateLabel']! : _formatDate(_startDate!)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDate(isStart: false),
                    child: Text(_endDate == null ? t['academicSessionsAdmin.endDateLabel']! : _formatDate(_endDate!)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _isActive,
              title: Text(t['academicSessionsAdmin.activeLabel']!),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (v) => setState(() => _isActive = v ?? true),
            ),
            CheckboxListTile(
              value: _isCurrent,
              title: Text(t['academicSessionsAdmin.setCurrentLabel']!),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (v) => setState(() => _isCurrent = v ?? false),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(t['academicSessionsAdmin.save']!),
            ),
          ],
        ),
      ),
    );
  }
}
