import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/cascading_dropdown.dart';
import '../data/doctors_admin_repository.dart';
import 'doctor_files.dart';
import 'doctors_admin_providers.dart';
import '../../../core/theme/app_theme.dart';

/// Port of the web `Doctors/Import.vue` (2026-10-17): pick an Excel sheet
/// (First Name, Last Name, Email, Phone, Username — the template's
/// columns), the education type and stage every imported doctor gets, and
/// an optional default password; `POST /doctors-import`.
class DoctorImportScreen extends ConsumerStatefulWidget {
  const DoctorImportScreen({super.key});

  @override
  ConsumerState<DoctorImportScreen> createState() => _DoctorImportScreenState();
}

class _DoctorImportScreenState extends ConsumerState<DoctorImportScreen> {
  final _passwordController = TextEditingController();
  ({String name, List<int> bytes})? _file;
  int? _educationTypeId;
  int? _stageId;
  bool _busy = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pick() async {
    final file = await pickExcelFile();
    if (file != null && mounted) setState(() => _file = file);
  }

  Future<void> _downloadTemplate() async {
    final t = ref.read(translationsProvider);
    try {
      final bytes = await ref.read(doctorsAdminRepositoryProvider).template();
      final path = await saveDownloadedFile('doctors_template.xlsx', bytes);
      if (path != null) _snack(trf(t['doctorsAdmin.fileSaved']!, {'path': path}));
    } catch (e) {
      _snack(e is ApiException ? e.userMessage : t['doctorsAdmin.downloadFailed']!);
    }
  }

  Future<void> _import() async {
    final t = ref.read(translationsProvider);
    final file = _file;
    final password = _passwordController.text.trim();
    if (file == null || _educationTypeId == null || _stageId == null) {
      _snack(t['doctorsAdmin.importMissing']!);
      return;
    }
    if (password.isNotEmpty && password.length < 6) {
      _snack(t['doctorsAdmin.passwordTooShort']!);
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await ref.read(doctorsAdminRepositoryProvider).import(
            bytes: file.bytes,
            fileName: file.name,
            educationTypeId: _educationTypeId!,
            stageId: _stageId!,
            defaultPassword: password,
          );
      ref.invalidate(doctorAdminListProvider);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t['doctorsAdmin.importTitle']!),
          content: Text(trf(t['doctorsAdmin.importResult']!, {
            'imported': result.imported,
            'skipped': result.skipped,
            'emails': result.emailsQueued,
          })),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(t['common.ok']!))],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _snack(e is ApiException ? e.userMessage : t['doctorsAdmin.importFailed']!);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final educationTypesAsync = ref.watch(doctorEducationTypesProvider);
    final stagesAsync = ref.watch(doctorStagesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t['doctorsAdmin.importTitle']!)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t['doctorsAdmin.importInstructions']!),
                  const SizedBox(height: 4),
                  Text(t['doctorsAdmin.importNote']!, style: const TextStyle(color: InstagramColors.gray, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _downloadTemplate,
                    icon: const Icon(Icons.download_outlined),
                    label: Text(t['doctorsAdmin.downloadTemplate']!),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.upload_file_outlined),
            label: Text(_file?.name ?? t['doctorsAdmin.pickExcel']!),
          ),
          const SizedBox(height: 16),
          CascadingDropdown(
            label: t['doctorsAdmin.educationTypeLabel']!,
            itemsAsync: educationTypesAsync,
            value: _educationTypeId,
            onChanged: (v) => setState(() {
              _educationTypeId = v;
              _stageId = null;
            }),
          ),
          const SizedBox(height: 16),
          CascadingDropdown(
            key: ValueKey('import-stage-$_educationTypeId'),
            label: t['doctorsAdmin.stageLabel']!,
            itemsAsync: stagesAsync.whenData(
              (items) => _educationTypeId == null ? items : items.where((s) => s.educationTypeId == _educationTypeId).toList(),
            ),
            value: _stageId,
            enabled: _educationTypeId != null,
            onChanged: (v) => setState(() => _stageId = v),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: t['doctorsAdmin.defaultPasswordLabel'],
              helperText: t['doctorsAdmin.defaultPasswordHint'],
              helperMaxLines: 3,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _import,
            icon: _busy
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.file_upload_outlined),
            label: Text(t['doctorsAdmin.import']!),
          ),
        ],
      ),
    );
  }
}
