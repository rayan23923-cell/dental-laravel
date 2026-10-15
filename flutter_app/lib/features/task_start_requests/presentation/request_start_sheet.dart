import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../data/task_start_request_repository.dart';

/// "طلب بدء مهمة" (2026-10-14): the doctor picks the electronic form (their
/// draft, opened with [onOpenForm]) or a photo of the paper one, adds an
/// optional note and sends. Returns true once sent.
Future<bool> showRequestStartSheet(
  BuildContext context, {
  required int taskId,
  required String taskTitle,
  required VoidCallback onOpenForm,
}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _RequestStartSheet(taskId: taskId, taskTitle: taskTitle, onOpenForm: onOpenForm),
  );
  return sent ?? false;
}

class _RequestStartSheet extends ConsumerStatefulWidget {
  const _RequestStartSheet({required this.taskId, required this.taskTitle, required this.onOpenForm});
  final int taskId;
  final String taskTitle;
  final VoidCallback onOpenForm;

  @override
  ConsumerState<_RequestStartSheet> createState() => _RequestStartSheetState();
}

class _RequestStartSheetState extends ConsumerState<_RequestStartSheet> {
  String _formType = 'electronic';
  XFile? _photo;
  Uint8List? _preview;
  final _notes = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _photo = file;
      _preview = bytes;
    });
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(taskStartRequestRepositoryProvider)
          .create(taskId: widget.taskId, formType: _formType, photo: _formType == 'paper' ? _photo : null, notes: _notes.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      final t = ref.read(translationsProvider);
      setState(() {
        _error = e is ValidationException
            ? (e.errors.values.expand((v) => v).firstOrNull ?? e.message)
            : e is ApiException
            ? e.userMessage
            : t['taskRequests.actionFailed']!;
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final scheme = Theme.of(context).colorScheme;

    Widget option(String value, IconData icon, String label) {
      final selected = _formType == value;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _formType = value),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: selected ? scheme.primaryContainer : null,
              border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: 2),
            ),
            child: Column(
              children: [
                Icon(icon, color: selected ? scheme.primary : scheme.onSurfaceVariant),
                const SizedBox(height: 4),
                Text(label, style: TextStyle(color: selected ? scheme.primary : scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t['taskRequests.requestTitle']!, style: Theme.of(context).textTheme.titleMedium),
            Text(widget.taskTitle, style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            Row(
              children: [
                option('electronic', Icons.description_outlined, t['taskRequests.electronicForm']!),
                const SizedBox(width: 8),
                option('paper', Icons.photo_camera_outlined, t['taskRequests.paperForm']!),
              ],
            ),
            const SizedBox(height: 12),
            if (_formType == 'electronic')
              Card(
                margin: EdgeInsets.zero,
                color: scheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t['taskRequests.electronicHint']!, style: const TextStyle(fontSize: 13)),
                      TextButton.icon(
                        onPressed: widget.onOpenForm,
                        icon: const Icon(Icons.edit_document),
                        label: Text(t['labels.caseSheetForm']!),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              if (_preview != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(_preview!, height: 180, fit: BoxFit.cover),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pick(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera),
                      label: Text(t['taskRequests.camera']!),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pick(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(t['taskRequests.gallery']!),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: InputDecoration(labelText: t['taskRequests.notesPlaceholder'], border: const OutlineInputBorder()),
            ),
            if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: TextStyle(color: scheme.error))],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _sending || (_formType == 'paper' && _photo == null) ? null : _send,
              icon: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              label: Text(t['taskRequests.send']!),
            ),
          ],
        ),
      ),
    );
  }
}
