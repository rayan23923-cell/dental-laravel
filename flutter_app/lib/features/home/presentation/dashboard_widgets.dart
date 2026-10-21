import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/chat_list_tile.dart';
import '../data/dashboard_repository.dart';
import '../domain/dashboard_data.dart';
import '../../../core/theme/muted_colors.dart';

/// The web dashboard's widgets for the app's staff home (2026-10-17):
/// counter tiles, task statuses, latest doctors and the tasks per
/// education type. Charts are drawn with plain widgets (bars), no chart
/// package.

final _plain = NumberFormat('#,##0', 'en');

String _fmtDate(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  return d == null ? '—' : DateFormat('yyyy/MM/dd HH:mm').format(d);
}

Widget _card(List<Widget> children) => Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) chatDivider,
            children[i],
          ],
        ],
      ),
    );

/// Headline counters: doctors, patients (today), tasks (done %), and
/// today's income with the month's when the role may open payments.
class DashboardCounters extends StatelessWidget {
  const DashboardCounters({super.key, required this.data, required this.t});
  final DashboardData data;
  final Map<String, String> t;

  @override
  Widget build(BuildContext context) {
    String money(double v) => '${_plain.format(v)} ${data.currency}'.trim();
    final tiles = [
      _Counter(
        label: t['home.doctorsCount']!,
        value: _plain.format(data.doctors),
        icon: Icons.medical_services_outlined,
        color: Colors.indigo,
        onTap: data.canDoctors ? () => context.push('/admin/doctors') : null,
      ),
      _Counter(
        label: t['home.patientsCount']!,
        value: _plain.format(data.registrations),
        hint: trf(t['home.todayCount']!, {'n': _plain.format(data.registrationsToday)}),
        icon: Icons.how_to_reg_outlined,
        color: Colors.lightBlue,
        onTap: () => context.push('/records/patient-registrations'),
      ),
      _Counter(
        label: t['home.tasksCount']!,
        value: _plain.format(data.tasks),
        hint: trf(t['home.donePercent']!, {'n': data.donePercent}),
        icon: Icons.assignment_outlined,
        color: Colors.teal,
        onTap: data.canTaskProgress ? () => context.push('/admin/task-progress') : null,
      ),
      if (data.canPayments && data.todayIncome != null)
        _Counter(
          label: t['home.todayIncome']!,
          value: money(data.todayIncome!),
          hint: trf(t['home.monthIncome']!, {'amount': money(data.monthIncome ?? 0)}),
          icon: Icons.payments_outlined,
          color: Colors.orange,
          onTap: () => context.push('/records/payments'),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth >= 720 ? 4 : 2;
        final width = (constraints.maxWidth - 8 * (perRow - 1)) / perRow;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final tile in tiles) SizedBox(width: width, child: tile)],
        );
      },
    );
  }
}

/// The per-role panels (2026-10-18, by request): the lab's screening
/// queue, the ticket desk's registrations and the accountant's income,
/// as counter tiles that open the matching screen.
class DeskPanelCounters extends StatelessWidget {
  const DeskPanelCounters({super.key, required this.panels, required this.t});
  final DeskPanels panels;
  final Map<String, String> t;

  @override
  Widget build(BuildContext context) {
    final reg = panels.registrations;
    final lab = panels.lab;
    final pay = panels.payments;
    String money(double v) => '${_plain.format(v)} ${pay?.currency ?? ''}'.trim();
    final tiles = [
      if (lab != null) ...[
        _Counter(
          label: t['home.labPending']!,
          value: _plain.format(lab.pending),
          hint: trf(t['home.labCheckedToday']!, {'n': _plain.format(lab.checkedToday)}),
          icon: Icons.hourglass_empty,
          color: Colors.orange,
          onTap: () => context.push('/lab'),
        ),
        _Counter(
          label: t['home.labFlagged']!,
          value: _plain.format(lab.flagged),
          hint: trf(t['home.labClear']!, {'n': _plain.format(lab.clear)}),
          icon: Icons.coronavirus_outlined,
          color: Colors.red,
          onTap: () => context.push('/lab'),
        ),
      ],
      if (reg != null)
        _Counter(
          label: t['home.registrationsToday']!,
          value: _plain.format(reg.today),
          hint: trf(t['home.registrationsTotal']!, {'n': _plain.format(reg.total)}),
          icon: Icons.how_to_reg_outlined,
          color: Colors.lightBlue,
          onTap: () => context.push('/records/patient-registrations'),
        ),
      if (pay != null) ...[
        _Counter(
          label: t['home.todayIncome']!,
          value: money(pay.today.total),
          hint: trf(t['home.paymentsCount']!, {'n': _plain.format(pay.today.count)}),
          icon: Icons.payments_outlined,
          color: Colors.green,
          onTap: () => context.push('/records/payments'),
        ),
        _Counter(
          label: t['home.weekIncome']!,
          value: money(pay.week.total),
          hint: trf(t['home.monthIncome']!, {'amount': money(pay.month.total)}),
          icon: Icons.account_balance_wallet_outlined,
          color: Colors.orange,
          onTap: () => context.push('/records/payments'),
        ),
      ],
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth >= 720 ? 4 : 2;
        final width = (constraints.maxWidth - 8 * (perRow - 1)) / perRow;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final tile in tiles) SizedBox(width: width, child: tile)],
        );
      },
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({required this.label, required this.value, required this.icon, required this.color, this.hint, this.onTap});
  final String label;
  final String value;
  final String? hint;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(radius: 21, backgroundColor: color, foregroundColor: Colors.white, child: Icon(icon, size: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(label,
                        style: TextStyle(fontSize: 12, color: context.mutedText),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (hint != null)
                      Text(hint!,
                          style: TextStyle(fontSize: 11, color: context.faintText),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "حالات المهام": done vs not-done tasks as a bar, and the cases split
/// into completed / in progress / pending as one stacked bar.
class DashboardTaskStatuses extends StatelessWidget {
  const DashboardTaskStatuses({super.key, required this.data, required this.t});
  final DashboardData data;
  final Map<String, String> t;

  @override
  Widget build(BuildContext context) {
    final segments = [
      (data.instancesCompleted, Colors.green, Icons.check_circle_outline, t['home.completed']!),
      (data.instancesAssigned, Colors.orange, Icons.pending_outlined, t['home.inProgress']!),
      (data.instancesPending, Colors.blueGrey, Icons.hourglass_empty, t['home.pending']!),
    ];
    final total = data.instancesTotal;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(t['home.doneVsNotDone']!, style: TextStyle(fontSize: 12, color: context.mutedText))),
                Text('${data.donePercent}%', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.green)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: data.donePercent / 100,
                minHeight: 8,
                color: Colors.green,
                backgroundColor: context.track,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                ChatChip(label: '${t['home.done']!}: ${data.tasksDone}', icon: Icons.task_alt, color: Colors.green),
                ChatChip(label: '${t['home.notDone']!}: ${data.tasksNotDone}', icon: Icons.radio_button_unchecked),
              ],
            ),
            const Divider(height: 24),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 10,
                child: total == 0
                    ? ColoredBox(color: context.track)
                    : Row(
                        children: [
                          for (final s in segments)
                            if (s.$1 > 0) Expanded(flex: s.$1, child: ColoredBox(color: s.$2)),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final s in segments) ChatChip(label: '${s.$4}: ${s.$1}', icon: s.$3, color: s.$2),
                Text(trf(t['home.totalCases']!, {'n': total}), style: TextStyle(fontSize: 11, color: context.faintText)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "أحدث الأطباء": the five newest doctors; each opens the doctors list.
class DashboardLatestDoctors extends StatelessWidget {
  const DashboardLatestDoctors({super.key, required this.data, required this.t});
  final DashboardData data;
  final Map<String, String> t;

  @override
  Widget build(BuildContext context) {
    if (data.latestDoctors.isEmpty) return _card([ListTile(title: Text(t['home.noDoctorsYet']!))]);
    return _card([
      for (final d in data.latestDoctors)
        ChatListTile(
          title: d.name,
          color: chatToneFor(d.id),
          onTap: data.canDoctors ? () => context.push('/admin/doctors/${d.id}') : null,
          chips: [
            if (d.educationType != null) ChatChip(label: d.educationType!, icon: Icons.school_outlined, color: Colors.deepPurple),
            ChatChip(label: _fmtDate(d.createdAt), icon: Icons.schedule),
          ],
        ),
    ]);
  }
}

/// "المهام المطلوبة لكل قسم ومرحلة حسب نوع الدراسة": pick an education
/// type, then each department/stage shows required vs completed as a bar
/// and opens to its tasks.
class DashboardTasksByEducationType extends ConsumerStatefulWidget {
  const DashboardTasksByEducationType({super.key, required this.data});
  final DashboardData data;

  @override
  ConsumerState<DashboardTasksByEducationType> createState() => _DashboardTasksByEducationTypeState();
}

class _DashboardTasksByEducationTypeState extends ConsumerState<DashboardTasksByEducationType> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final departmentsAsync = _selected == null ? null : ref.watch(dashboardTasksByEducationTypeProvider(_selected!));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final e in widget.data.educationTypes)
              ChoiceChip(
                avatar: const Icon(Icons.school_outlined, size: 16),
                label: Text(e.name),
                selected: _selected == e.id,
                onSelected: (_) => setState(() => _selected = e.id),
              ),
          ],
        ),
        if (departmentsAsync != null) ...[
          const SizedBox(height: 8),
          departmentsAsync.when(
            loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => _card([ListTile(title: Text(e is ApiException ? e.userMessage : t['common.loadFailed']!))]),
            data: (departments) {
              if (departments.isEmpty) return _card([ListTile(title: Text(t['home.noTasksForEduType']!))]);
              return _card([
                for (var i = 0; i < departments.length; i++) _DepartmentRow(department: departments[i], index: i, t: t),
              ]);
            },
          ),
        ],
      ],
    );
  }
}

class _DepartmentRow extends StatelessWidget {
  const _DepartmentRow({required this.department, required this.index, required this.t});
  final DashboardDepartment department;
  final int index;
  final Map<String, String> t;

  @override
  Widget build(BuildContext context) {
    final color = chatToneFor(index);
    final ratio = department.required > 0 ? (department.completed / department.required).clamp(0.0, 1.0) : 0.0;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        leading: CircleAvatar(backgroundColor: color, foregroundColor: Colors.white, child: const Icon(Icons.folder_outlined)),
        title: Text(department.department, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(department.stage ?? '—', style: TextStyle(fontSize: 12, color: context.mutedText)),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: ratio, minHeight: 6, color: Colors.green, backgroundColor: context.track),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                ChatChip(label: '${t['home.requiredLabel']!}: ${department.required}', icon: Icons.flag_outlined, color: Colors.indigo),
                ChatChip(label: '${t['home.completed']!}: ${department.completed}', icon: Icons.check_circle_outline, color: Colors.green),
                ChatChip(label: '${department.tasks.length}', icon: Icons.assignment_outlined),
              ],
            ),
          ],
        ),
        childrenPadding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
        children: [
          for (final task in department.tasks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text(task.title)),
                  ChatChip(label: '${task.required}', color: Colors.indigo),
                  const SizedBox(width: 4),
                  ChatChip(label: '${task.completed}', color: Colors.green),
                  const SizedBox(width: 4),
                  ChatChip(label: '${t['home.remaining']!}: ${task.remaining}', color: Colors.orange),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
