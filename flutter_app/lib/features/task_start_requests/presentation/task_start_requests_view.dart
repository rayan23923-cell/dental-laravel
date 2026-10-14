import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../data/task_start_request_repository.dart';
import '../domain/task_start_request.dart';
import 'task_start_request_providers.dart';

/// "الطلبات" tab of task progress (2026-10-14) — the app's copy of the
/// web's `TaskStartRequestsPanel.vue`: waiting / started / turned down,
/// preview the doctor's electronic form or paper photo, then start the
/// task or turn the request down.
class TaskStartRequestsView extends ConsumerStatefulWidget {
  const TaskStartRequestsView({super.key});

  @override
  ConsumerState<TaskStartRequestsView> createState() => _TaskStartRequestsViewState();
}

class _TaskStartRequestsViewState extends ConsumerState<TaskStartRequestsView> {
  String _tab = 'pending';
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final boardAsync = ref.watch(taskStartRequestBoardProvider);
    final board = boardAsync.valueOrNull;
    final lists = {'pending': board?.pending ?? const [], 'approved': board?.approved ?? const [], 'rejected': board?.rejected ?? const []};
    final labels = {
      'pending': t['taskRequests.pendingTab']!,
      'approved': t['taskRequests.startedTab']!,
      'rejected': t['taskRequests.rejectedTab']!,
    };
    final q = _query.trim().toLowerCase();
    final rows = (lists[_tab] ?? const <TaskStartRequest>[])
        .where((r) => q.isEmpty || [r.doctorName, r.taskTitle, r.department, r.doctorStage].any((v) => (v ?? '').toLowerCase().contains(q)))
        .toList();

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              for (final key in labels.keys) ...[
                ChoiceChip(
                  label: Text('${labels[key]} (${lists[key]!.length})'),
                  selected: _tab == key,
                  selectedColor: key == 'pending' && lists[key]!.isNotEmpty ? Colors.red.shade100 : null,
                  onSelected: (_) => setState(() => _tab = key),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: InputDecoration(
              hintText: t['taskRequests.searchPlaceholder'],
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: boardAsync.isLoading && board == null
              ? const Center(child: CircularProgressIndicator())
              : boardAsync.hasError && board == null
              ? Center(
                  child: Text(
                    boardAsync.error is ApiException ? (boardAsync.error as ApiException).userMessage : t['taskRequests.actionFailed']!,
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => ref.refresh(taskStartRequestBoardProvider.future),
                  child: rows.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: 80),
                            Icon(Icons.assignment_turned_in_outlined, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            Text(
                              t['taskRequests.empty']!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                          itemCount: rows.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, i) => _RequestCard(request: rows[i]),
                        ),
                ),
        ),
      ],
    );
  }
}

class _RequestCard extends ConsumerWidget {
  const _RequestCard({required this.request});
  final TaskStartRequest request;

  String _fmt(BuildContext context, DateTime? d) =>
      d == null ? '' : DateFormat.yMMMd(Localizations.localeOf(context).languageCode).add_jm().format(d.toLocal());

  Future<void> _review(BuildContext context, WidgetRef ref, bool approve) async {
    final t = ref.read(translationsProvider);
    final note = TextEditingController();
    String? error;
    var busy = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(approve ? t['taskRequests.startTitle']! : t['taskRequests.rejectTitle']!),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${request.doctorName} · ${request.taskTitle}'),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: approve ? t['taskRequests.startNotePlaceholder'] : t['taskRequests.rejectNotePlaceholder'],
                  border: const OutlineInputBorder(),
                ),
              ),
              if (error != null) ...[const SizedBox(height: 8), Text(error!, style: const TextStyle(color: Colors.red))],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(t['paperPhotos.cancel']!)),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: approve ? Colors.green.shade700 : Colors.red.shade700),
              onPressed: busy
                  ? null
                  : () async {
                      setState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        final repo = ref.read(taskStartRequestRepositoryProvider);
                        final text = note.text.trim().isEmpty ? null : note.text.trim();
                        approve ? await repo.approve(request.id, note: text) : await repo.reject(request.id, note: text);
                        ref.invalidate(taskStartRequestBoardProvider);
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (e) {
                        setState(() {
                          busy = false;
                          error = e is ApiException ? e.userMessage : t['taskRequests.actionFailed'];
                        });
                      }
                    },
              child: Text(approve ? t['taskRequests.start']! : t['taskRequests.reject']!),
            ),
          ],
        ),
      ),
    );
    note.dispose();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final r = request;
    final scheme = Theme.of(context).colorScheme;

    Widget chip(String text, Color bg, Color fg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: TextStyle(fontSize: 12, color: fg)),
    );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundImage: r.doctorPhotoUrl != null ? NetworkImage(r.doctorPhotoUrl!) : null,
              child: r.doctorPhotoUrl == null ? Text(r.doctorName.trim().isEmpty ? '?' : r.doctorName.trim()[0]) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.doctorName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(_fmt(context, r.createdAt), style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text(r.taskTitle),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (r.department != null) chip(r.department!, Colors.grey.shade200, Colors.grey.shade800),
                      if (r.doctorStage != null) chip(r.doctorStage!, Colors.grey.shade200, Colors.grey.shade800),
                      r.isPaper
                          ? chip(t['taskRequests.paperForm']!, Colors.amber.shade50, Colors.amber.shade900)
                          : chip(t['taskRequests.electronicForm']!, Colors.lightBlue.shade50, Colors.lightBlue.shade900),
                    ],
                  ),
                  if (r.notes != null && r.notes!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${t['taskRequests.doctorNote']}: ${r.notes}',
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ),
                  if (r.status != 'pending')
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        [
                          trf(t[r.status == 'approved' ? 'taskRequests.startedBy' : 'taskRequests.rejectedBy']!, {
                            'name': r.reviewer ?? '—',
                          }),
                          _fmt(context, r.reviewedAt),
                          if (r.reviewNote != null && r.reviewNote!.isNotEmpty) r.reviewNote!,
                        ].join(' · '),
                        style: TextStyle(fontSize: 12, color: r.status == 'approved' ? Colors.green.shade700 : Colors.red.shade700),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (r.photoUrl != null)
                        ActionChip(
                          avatar: const Icon(Icons.image_outlined, size: 18),
                          label: Text(t['taskRequests.viewPhoto']!),
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(r.photoUrl!))),
                          ),
                        ),
                      if (r.caseSheetResource != null && r.caseSheetRecordId != null)
                        ActionChip(
                          avatar: const Icon(Icons.description_outlined, size: 18),
                          label: Text(t['taskRequests.viewForm']!),
                          onPressed: () => context.push('/case-sheets/${r.caseSheetResource}/${r.caseSheetRecordId}'),
                        )
                      else if (!r.isPaper)
                        Chip(
                          label: Text(t['taskRequests.formNotFilled']!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ),
                      if (r.status == 'pending') ...[
                        ActionChip(
                          avatar: const Icon(Icons.play_arrow, size: 18, color: Colors.white),
                          backgroundColor: Colors.green.shade700,
                          label: Text(t['taskRequests.start']!, style: const TextStyle(color: Colors.white)),
                          onPressed: () => _review(context, ref, true),
                        ),
                        ActionChip(
                          avatar: Icon(Icons.close, size: 18, color: Colors.red.shade700),
                          label: Text(t['taskRequests.reject']!, style: TextStyle(color: Colors.red.shade700)),
                          onPressed: () => _review(context, ref, false),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
