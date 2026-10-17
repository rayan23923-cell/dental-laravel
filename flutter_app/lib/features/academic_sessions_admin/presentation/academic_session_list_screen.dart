import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/chat_list_tile.dart';
import '../../clinic_settings/presentation/clinic_settings_providers.dart';
import '../data/academic_sessions_repository.dart';
import '../domain/academic_session_admin.dart';
import 'academic_sessions_providers.dart';

class AcademicSessionListScreen extends ConsumerWidget {
  const AcademicSessionListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(academicSessionListProvider);
    final t = ref.watch(translationsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t['academicSessionsAdmin.title']!)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/admin/academic-sessions/new'),
        tooltip: t['academicSessionsAdmin.newTitle'],
        child: const Icon(Icons.add),
      ),
      body: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text(error is ApiException ? error.userMessage : t['academicSessionsAdmin.loadFailed']!),
        ),
        data: (sessions) {
          if (sessions.isEmpty) {
            return Center(child: Text(t['academicSessionsAdmin.emptyList']!));
          }
          // Chat-list style (2026-10-13, by request).
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(academicSessionListProvider),
            child: ListView.separated(
              padding: const EdgeInsets.only(top: 8, bottom: 88),
              itemCount: sessions.length,
              separatorBuilder: (_, __) => chatDivider,
              itemBuilder: (context, i) => _SessionTile(session: sessions[i]),
            ),
          );
        },
      ),
    );
  }
}

class _SessionTile extends ConsumerStatefulWidget {
  const _SessionTile({required this.session});
  final AcademicSessionAdmin session;

  @override
  ConsumerState<_SessionTile> createState() => _SessionTileState();
}

class _SessionTileState extends ConsumerState<_SessionTile> {
  bool _submitting = false;

  /// Turning this year's switch on makes it the active one — the backend's
  /// `AcademicSession::booted()` `saving()` hook (see `dental_laravel/
  /// README.md`) already guarantees every other row's `is_current` gets
  /// cleared in the same request, so this call alone is enough; no
  /// separate "turn off the others" step needed here. There's no
  /// corresponding "turn off" action — exactly one year must always be
  /// active, so switching off only ever happens by switching a *different*
  /// row on (that row's switch is left disabled below while it's already
  /// current, same reasoning `academic_session_detail_screen.dart`'s
  /// "اجعله العام الدراسي النشط" button already used before this replaced it).
  Future<void> _setCurrent() async {
    setState(() => _submitting = true);
    try {
      await ref.read(academicSessionsRepositoryProvider).setCurrent(widget.session.id);
      ref.invalidate(academicSessionListProvider);
      ref.invalidate(currentAcademicYearProvider);
    } catch (e) {
      if (mounted) {
        final t = ref.read(translationsProvider);
        final message = e is ApiException ? e.userMessage : t['academicSessionsAdmin.setCurrentFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// View this year from now on (the web's "عرض كمحدد"): every later
  /// request carries it, so lists and banners follow it.
  Future<void> _select() async {
    setState(() => _submitting = true);
    try {
      await ref.read(academicSessionsRepositoryProvider).select(widget.session.id);
      ref.invalidate(currentAcademicYearProvider);
      ref.invalidate(academicSessionListProvider);
    } catch (e) {
      if (mounted) {
        final t = ref.read(translationsProvider);
        final message = e is ApiException ? e.userMessage : t['academicSessionsAdmin.selectFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final t = ref.watch(translationsProvider);
    // The year the server resolves for this app — its choice, or the current one.
    final viewing = ref.watch(currentAcademicYearProvider).valueOrNull?.id == session.id;

    final groupsEnabled = ref.watch(groupsEnabledProvider);

    // The current year gets a green avatar and a check chip — a status
    // colour says more here than the per-id rotation.
    return ChatListTile(
      title: session.name,
      icon: Icons.calendar_month,
      color: session.isCurrent ? Colors.green : chatToneFor(session.id),
      selected: viewing,
      chips: [
        if (session.isCurrent)
          ChatChip(label: t['academicSessionsAdmin.currentLabel']!, icon: Icons.check_circle, color: Colors.green),
        if (viewing)
          ChatChip(label: t['academicSessionsAdmin.viewingLabel']!, icon: Icons.visibility, color: Colors.indigo),
        // Forced LTR: two dates joined only by "→" have no strong-
        // direction anchor inside RTL text, so the bidi algorithm
        // reorders them — confirmed live showing end before start.
        Directionality(
          textDirection: TextDirection.ltr,
          child: ChatChip(label: '${session.startDate} → ${session.endDate}', icon: Icons.date_range),
        ),
        if (groupsEnabled)
          Tooltip(
            message: t['academicSessionsAdmin.groupsStat']!,
            child: ChatChip(label: '${session.groupsCount}', icon: Icons.groups, color: Colors.indigo),
          ),
        Tooltip(
          message: t['academicSessionsAdmin.requiredTasksStat']!,
          child: ChatChip(label: '${session.tasksCount}', icon: Icons.assignment, color: Colors.orange.shade800),
        ),
      ],
      actions: [
        if (!viewing && session.isActive && !_submitting)
          IconButton(
            tooltip: t['academicSessionsAdmin.selectViewing']!,
            icon: const Icon(Icons.visibility_outlined),
            onPressed: _select,
          ),
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: _submitting
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Tooltip(
                  message: t['academicSessionsAdmin.setCurrentLabel']!,
                  child: CupertinoSwitch(
                    value: session.isCurrent,
                    onChanged: session.isCurrent ? null : (_) => _setCurrent(),
                  ),
                ),
        ),
      ],
      onTap: () => context.push('/admin/academic-sessions/${session.id}'),
    );
  }
}
