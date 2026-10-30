import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/case_code.dart';
import '../data/task_progress_repository.dart';
import '../domain/case_lookup_result.dart';
import '../domain/task_progress_group.dart';
import 'task_slot_actions.dart';

/// The case a supervisor scanned or typed the code of (2026-10-30, by
/// request): who and what it is, with the same start / complete / steps /
/// edit / photos / case sheet / receipt actions as its card on the task
/// progress matrix (`TaskSlotTile`), without drilling down to it.
class CaseLookupScreen extends ConsumerStatefulWidget {
  const CaseLookupScreen({super.key, required this.result});

  final CaseLookupResult result;

  @override
  ConsumerState<CaseLookupScreen> createState() => _CaseLookupScreenState();
}

class _CaseLookupScreenState extends ConsumerState<CaseLookupScreen> with TaskSlotActions<CaseLookupScreen> {
  late CaseLookupResult _result = widget.result;

  /// After an action, the case again — by its own code, so a task that
  /// was just started now shows as the started case.
  @override
  void reloadSlots() {
    final instanceId = _result.card?.instanceId ?? startedInstanceId;
    final code = instanceId != null ? CaseCode.forInstance(instanceId) : _result.code;
    if (code != null) _reload(code);
  }

  Future<void> _reload(String code) async {
    final repo = ref.read(taskProgressRepositoryProvider);
    try {
      CaseLookupResult next;
      try {
        next = await repo.lookup(code);
      } on ApiException {
        // A start just cancelled: the case is gone, the task is back to
        // not started.
        final taskId = _result.taskId;
        if (taskId == null) rethrow;
        next = await repo.lookup(CaseCode.forPending(taskId, _result.doctor.id));
      }
      if (mounted) setState(() => _result = next);
    } catch (e) {
      if (!mounted) return;
      final t = ref.read(translationsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.userMessage : t['qrScan.unknownCode']!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final r = _result;
    final card = r.card;
    final theme = Theme.of(context);
    final rows = <(String, String)>[
      (t['taskDetail.doctorLabel']!, r.doctor.username.isNotEmpty ? '${r.doctor.name} (${r.doctor.username})' : r.doctor.name),
      if (r.department != null) (t['labels.department']!, r.department!),
      if (r.caseSheet != null) (t['taskDetail.caseSheetTypeLabel']!, r.caseSheet!),
      if (r.group != null && r.group!.name.isNotEmpty) (r.group!.stageName ?? '', r.group!.name),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(r.taskTitle ?? t['caseCode.screenTitle']!)),
      body: RefreshIndicator(
        onRefresh: () async => reloadSlots(),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.taskTitle ?? '', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    for (final row in rows)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (row.$1.isNotEmpty)
                              Text('${row.$1}: ', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                            Expanded(child: Text(row.$2)),
                          ],
                        ),
                      ),
                    if (r.code != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            Text('${t['caseCode.codeLabel']}: ', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                            Text(
                              CaseCode.format(r.code!),
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, letterSpacing: 1.5),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (card != null)
              Card(
                child: TaskSlotTile(
                  doctor: TaskProgressDoctorRow(
                    id: r.doctor.id,
                    name: r.doctor.name,
                    username: r.doctor.username,
                    required: 0,
                    completed: 0,
                    assigned: 0,
                    pending: 0,
                    unassigned: 0,
                    tasks: [card],
                  ),
                  departmentName: r.department ?? '',
                  groupOption: r.group ?? const TaskProgressGroupOption(id: null, name: ''),
                  card: card,
                  screen: this,
                ),
              )
            else
              Card(
                color: Colors.amber.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(t['caseCode.noSlotLeft']!, style: TextStyle(color: Colors.amber.shade900)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
