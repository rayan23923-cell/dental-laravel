import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../data/clinic_chairs_admin_repository.dart';
import '../domain/clinic_chair_admin.dart';
import 'clinic_chairs_admin_providers.dart';

/// Clinic seating map (2026-09-04, by request — "اضفها الى فلتر", porting
/// the web-only `ClinicChairs/Index.vue` feature here). Two drag gestures,
/// both built on Flutter's own `Draggable`/`DragTarget` (no extra
/// package — same reasoning the web page's own doc comment gives for
/// using plain HTML5 DnD there rather than a library):
///   - dragging a group chip onto a chair assigns the whole group there
///   - dragging a chair onto another chair swaps their positions
/// A `DragTarget<Object>` per chair distinguishes the two by the dragged
/// payload's runtime type (`ChairGroup` vs `ClinicChairAdmin`) rather than
/// the web's own explicit `{type, id}` tag, since Dart's type system
/// already gives that for free.
///
/// Doesn't attempt to reproduce the web page's own hand-drawn CSS
/// dental-chair artwork (a large, specifically-commissioned SVG/CSS asset
/// — see `AdvancedPerioChart.vue`'s doc comment for the same reasoning
/// applied to a different asset) — a circular avatar + `Icons.event_seat`
/// carries the same information (assigned doctor's photo/name, empty vs
/// occupied) without that disproportionate porting cost.
class ClinicChairsScreen extends ConsumerWidget {
  const ClinicChairsScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(clinicChairsBoardProvider);
    await ref.read(clinicChairsBoardProvider.future);
  }

  void _showMessage(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _assignGroup(BuildContext context, WidgetRef ref, ChairGroup group) async {
    try {
      final message = await ref.read(clinicChairsAdminRepositoryProvider).assignGroup(group.id);
      await _refresh(ref);
      if (context.mounted) _showMessage(context, message);
    } catch (e) {
      if (context.mounted) _showMessage(context, e is ApiException ? e.userMessage : 'تعذر التوزيع.');
    }
  }

  Future<void> _dropOnChair(BuildContext context, WidgetRef ref, ClinicChairAdmin target, Object data) async {
    final repo = ref.read(clinicChairsAdminRepositoryProvider);
    try {
      if (data is ChairGroup) {
        await repo.assignChairToGroup(target.id, data.id);
      } else if (data is ClinicChairAdmin && data.id != target.id) {
        await repo.moveChair(data.id, rowNumber: target.rowNumber, columnNumber: target.columnNumber);
      }
      await _refresh(ref);
    } catch (e) {
      if (context.mounted) _showMessage(context, e is ApiException ? e.userMessage : 'فشلت العملية.');
    }
  }

  Future<void> _unassign(BuildContext context, WidgetRef ref, ClinicChairAdmin chair) async {
    try {
      await ref.read(clinicChairsAdminRepositoryProvider).unassignChair(chair.id);
      await _refresh(ref);
    } catch (e) {
      if (context.mounted) _showMessage(context, e is ApiException ? e.userMessage : 'تعذر إلغاء التخصيص.');
    }
  }

  Future<void> _addChair(WidgetRef ref, {int? rowNumber}) async {
    await ref.read(clinicChairsAdminRepositoryProvider).addChair(rowNumber: rowNumber);
    await _refresh(ref);
  }

  Future<void> _removeChair(BuildContext context, WidgetRef ref, ClinicChairAdmin chair) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف الكرسي؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(clinicChairsAdminRepositoryProvider).deleteChair(chair.id);
    await _refresh(ref);
  }

  void _viewChair(BuildContext context, ClinicChairAdmin chair) {
    if (chair.group == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        expand: false,
        builder: (sheetContext, scrollController) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(chair.doctor?.name ?? chair.group!.name, style: Theme.of(sheetContext).textTheme.titleLarge),
              Text(
                'كرسي ${chair.positionLabel}${chair.doctor != null ? ' · ${chair.group!.name}' : ''}',
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (chair.doctor != null) Text('باقي المجموعة', style: Theme.of(sheetContext).textTheme.labelSmall),
              const SizedBox(height: 8),
              Expanded(
                child: chair.group!.doctors.isEmpty
                    ? const Center(child: Text('لا يوجد أطباء في هذه المجموعة بعد.'))
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: chair.group!.doctors.length,
                        itemBuilder: (context, index) {
                          final doctor = chair.group!.doctors[index];
                          final isThisChair = doctor.id == chair.doctor?.id;
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.person_outline),
                            title: Text(
                              doctor.name,
                              style: isThisChair
                                  ? TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)
                                  : null,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardAsync = ref.watch(clinicChairsBoardProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('خريطة كراسي العيادة')),
      body: boardAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text(error is ApiException ? error.userMessage : 'تعذر تحميل خريطة الكراسي.'),
        ),
        data: (board) => RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (board.currentSessionName != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('العام الدراسي: ${board.currentSessionName}', style: Theme.of(context).textTheme.bodySmall),
                ),
              Text(
                'اضغط "توزيع" لتوزيع أطباء مجموعة على كراسي مستقلة. اسحب مجموعة إلى كرسي لتخصيصه للمجموعة كاملة. اسحب كرسيًا إلى آخر لتبديل مكانيهما.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 12),
              _GroupsRow(board: board, onAssign: (group) => _assignGroup(context, ref, group)),
              const SizedBox(height: 16),
              for (final row in board.rows) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text('صف ${row.rowNumber}', style: Theme.of(context).textTheme.labelSmall),
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final chair in row.chairs)
                      _ChairCard(
                        chair: chair,
                        onDrop: (data) => _dropOnChair(context, ref, chair, data),
                        onTap: () => _viewChair(context, chair),
                        onUnassign: () => _unassign(context, ref, chair),
                        onDelete: () => _removeChair(context, ref, chair),
                      ),
                    _AddChairButton(onTap: () => _addChair(ref, rowNumber: row.rowNumber)),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (board.rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('لا توجد كراسي بعد — ابدأ صفًا جديدًا.', style: TextStyle(color: Colors.grey))),
                ),
              OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('صف جديد'),
                onPressed: () => _addChair(ref),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupsRow extends StatelessWidget {
  const _GroupsRow({required this.board, required this.onAssign});
  final ClinicChairsBoard board;
  final ValueChanged<ChairGroup> onAssign;

  @override
  Widget build(BuildContext context) {
    if (board.groups.isEmpty) {
      return const Text('لا توجد مجموعات.', style: TextStyle(color: Colors.grey));
    }
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: board.groups.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final group = board.groups[index];
          final unseated = board.unseatedCount(group);
          final card = Container(
            width: 170,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.indigo.shade100),
              borderRadius: BorderRadius.circular(10),
              color: Colors.indigo.shade50,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(group.name, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  '${group.stageName ?? '—'} · ${group.doctors.length} طبيب',
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                if (unseated > 0)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 4), minimumSize: Size.zero),
                      onPressed: () => onAssign(group),
                      child: Text(
                        unseated == group.doctors.length ? 'توزيع' : 'تحديث ($unseated جديد)',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ),
          );

          return Draggable<ChairGroup>(
            data: group,
            feedback: Material(color: Colors.transparent, child: SizedBox(width: 170, child: card)),
            childWhenDragging: Opacity(opacity: 0.4, child: card),
            child: card,
          );
        },
      ),
    );
  }
}

class _ChairCard extends StatefulWidget {
  const _ChairCard({required this.chair, required this.onDrop, required this.onTap, required this.onUnassign, required this.onDelete});
  final ClinicChairAdmin chair;
  final ValueChanged<Object> onDrop;
  final VoidCallback onTap;
  final VoidCallback onUnassign;
  final VoidCallback onDelete;

  @override
  State<_ChairCard> createState() => _ChairCardState();
}

class _ChairCardState extends State<_ChairCard> {
  @override
  Widget build(BuildContext context) {
    final chair = widget.chair;
    final assigned = chair.doctor != null || chair.group != null;

    final card = DragTarget<Object>(
      onWillAcceptWithDetails: (details) => details.data is ChairGroup || (details.data is ClinicChairAdmin && details.data != chair),
      onAcceptWithDetails: (details) => widget.onDrop(details.data),
      builder: (context, candidateData, rejectedData) {
        final dragOver = candidateData.isNotEmpty;
        return GestureDetector(
          onTap: widget.onTap,
          onLongPress: widget.onDelete,
          child: Container(
            width: 108,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: dragOver ? Theme.of(context).colorScheme.primary : Colors.grey.shade300, width: dragOver ? 2 : 1),
              color: assigned ? Colors.green.shade50 : Colors.grey.shade50,
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: chair.doctor != null
                      ? Colors.purple.shade300
                      : (chair.group != null ? Colors.indigo.shade300 : Colors.grey.shade300),
                  backgroundImage: chair.doctor?.profileImageUrl != null ? NetworkImage(chair.doctor!.profileImageUrl!) : null,
                  child: chair.doctor?.profileImageUrl == null ? const Icon(Icons.person, color: Colors.white, size: 22) : null,
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        chair.doctor?.name ?? chair.group?.name ?? 'فارغ',
                        style: const TextStyle(fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (assigned)
                      GestureDetector(
                        onTap: widget.onUnassign,
                        child: const Padding(
                          padding: EdgeInsets.only(right: 2),
                          child: Icon(Icons.close, size: 12, color: Colors.grey),
                        ),
                      ),
                  ],
                ),
                if (chair.doctor != null && chair.group != null)
                  Text(chair.group!.name, style: const TextStyle(fontSize: 9, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Icon(Icons.event_seat, size: 26, color: Colors.blueGrey.shade300),
                Text(chair.positionLabel, style: const TextStyle(fontSize: 9, color: Colors.grey)),
              ],
            ),
          ),
        );
      },
    );

    return LongPressDraggable<ClinicChairAdmin>(
      data: chair,
      feedback: Material(color: Colors.transparent, child: SizedBox(width: 108, child: card)),
      childWhenDragging: Opacity(opacity: 0.4, child: card),
      child: card,
    );
  }
}

class _AddChairButton extends StatelessWidget {
  const _AddChairButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 44,
        height: 108,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
        ),
        child: const Icon(Icons.add, color: Colors.grey),
      ),
    );
  }
}
