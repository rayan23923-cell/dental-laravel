import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:intl/intl.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/widgets/academic_year_banner.dart';
import '../../../core/widgets/chat_list_tile.dart';
import '../../auth/domain/account_type.dart';
import '../../auth/domain/auth_account.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/auth_state.dart';
import '../../patient_registration/presentation/patient_registration_providers.dart';
import '../../records/presentation/records_providers.dart';
import '../../task_instances/presentation/my_tasks_screen.dart';
import '../data/dashboard_repository.dart';
import '../domain/dashboard_data.dart';
import 'dashboard_widgets.dart';

/// A doctor's home *is* their task list (`/my-task-progress` is
/// doctor-only server-side — a staff token 403s it, see
/// `Api\TaskProgressController::mine()`), so this branches on account type
/// rather than always showing the same placeholder. Staff get the
/// patients/appointments/payments "records" trio (`/records`) and the
/// Phase 3 admin hub (`/admin` — doctors, groups, academic sessions,
/// tasks, case sheet types, permissions, backup, activity log, clinic
/// settings, education types/stages/departments — the full tracked
/// Phase 3 admin list, done as of 2026-08-21) — both permission-gated
/// staff-only server-side, so this nav only ever makes sense for staff.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider).valueOrNull;
    final account = authState is Authenticated ? authState.account : null;
    final isDoctor = account?.accountType == AccountType.doctor;
    final t = ref.watch(translationsProvider);

    return Scaffold(
      // Records/admin/notifications/profile/logout all now live in the
      // persistent sidebar (AppSidebar) — see this file's own doc comment
      // above for the account-type branching that already drove these same
      // destinations, now surfaced once in the sidebar instead of per-screen.
      appBar: AppBar(title: Text(isDoctor ? t['nav.myTasks']! : t['nav.home']!)),
      floatingActionButton: isDoctor
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/scan'),
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(t['nav.scanQr']!),
            )
          : null,
      body: isDoctor
          ? const MyTasksScreen()
          : _StaffDashboard(
              displayName: account?.displayName ?? '',
              profileImageUrl: account is StaffAccount ? account.profileImageUrl : null,
              role: account is StaffAccount ? account.role : '',
              t: t,
            ),
    );
  }
}

/// Staff landing dashboard — replaces the old two-button placeholder with a
/// welcome header, a grid of the actions staff reach for every day (not a
/// copy of `RecordsHubScreen`'s full list, just the frequent subset), and
/// the two module hubs ("السجلات"/"الإدارة") as proper cards instead of
/// plain buttons.
class _StaffDashboard extends ConsumerWidget {
  const _StaffDashboard({
    required this.displayName,
    required this.profileImageUrl,
    required this.role,
    required this.t,
  });

  final String displayName;
  final String? profileImageUrl;

  /// Desk roles (2026-10-12): 'reception' (موظف التذاكر) and 'lab'
  /// (مختبري) only get their own shortcut, the rest is outside their grants.
  final String role;
  final Map<String, String> t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    // One "تسجيل المرضى" entry, the same as the web menu (2026-10-13, by
    // request): the separate "register a new patient" shortcut confused
    // users, and the registrations list already registers patients.
    final registerShortcut = _Shortcut(
      t['labels.registerPatients']!,
      Icons.how_to_reg_outlined,
      () => context.push('/records/patient-registrations'),
      Colors.indigo,
    );
    final labShortcut = _Shortcut(
      t['labels.lab']!,
      Icons.coronavirus_outlined,
      () => context.push('/records/patient-registrations/scan-screening'),
      Colors.red,
    );
    final paymentsShortcut =
        _Shortcut(t['labels.payments']!, Icons.payments_outlined, () => context.push('/records/payments'), Colors.orange);
    // Roles with a home of their own (2026-10-18, by request): the lab, the
    // ticket desk and the accountant see their own panels and shortcuts
    // instead of the admin dashboard.
    final isDeskRole = role == 'reception' || role == 'lab' || role == 'accountant';
    // The web dashboard's figures (2026-10-17); desk roles don't get them,
    // as on the web, so they never call the endpoint.
    final dashboardAsync = isDeskRole ? null : ref.watch(dashboardProvider);
    final dashboard = dashboardAsync?.valueOrNull;
    final deskAsync = isDeskRole ? ref.watch(deskPanelsProvider) : null;
    final shortcuts = role == 'reception'
        ? [registerShortcut]
        : role == 'lab'
            ? [labShortcut]
            : role == 'accountant'
                ? [paymentsShortcut]
            : [
      registerShortcut,
      // Appointments hidden for now (2026-10-13, by request), as on the web.
      paymentsShortcut,
      // Real bug found live: this still pointed at the old NFC-only
      // screen's route, removed when it was superseded by the full
      // day→group→department→doctor matrix (see that screen's own
      // docblock) — every tap crashed straight to "Page Not Found"
      // (`GoException: no routes for location: /admin/task-progress/nfc`).
      // The admin hub's own tile was updated at the time; this one was missed.
      _Shortcut(t['labels.taskProgress']!, Icons.fact_check_outlined, () => context.push('/admin/task-progress'), Colors.lightBlue),
      // The infectious-disease screening feature (2026-08-25) had no
      // dashboard entry point at all — the only way in was a small icon
      // inside the patient-registrations list, easy to miss. Added
      // (2026-08-26) so "المختبر" is a first-class shortcut like every
      // other daily action here.
      labShortcut,
      // "عرض تقدم الأطباء", as on the web dashboard: the doctors list,
      // where each doctor's progress opens.
      if (dashboard?.canDoctors ?? false)
        _Shortcut(t['home.doctorsProgress']!, Icons.medical_services_outlined, () => context.push('/admin/doctors'), Colors.green),
    ];

    // Chat-list layout (2026-10-13, by request), as on the web dashboard:
    // the shortcuts as rows, then the latest registrations (opening the
    // patient registry) and the latest payments.
    final rows = [
      for (final s in shortcuts) (s.label, null as String?, s.icon, s.color, s.onTap),
      if (!isDeskRole) ...[
        (t['nav.records']!, t['home.recordsSubtitle'], Icons.folder_shared_outlined, Colors.blueGrey, () => context.push('/records')),
        (t['nav.admin']!, t['home.adminSubtitle'], Icons.admin_panel_settings_outlined, Colors.deepPurple, () => context.push('/admin')),
      ],
    ];

    final list = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: ChatListTile(
            title: displayName,
            subtitle: t['home.staffRole'],
            color: colors.primary,
            icon: Icons.person,
            imageUrl: profileImageUrl,
          ),
        ),
        const AcademicYearBanner(margin: EdgeInsets.only(top: 8)),
        const SizedBox(height: 16),
        if (dashboardAsync != null) ...[
          dashboardAsync.when(
            loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => _SectionCard(children: [ListTile(title: Text(t['home.dashboardLoadFailed']!))]),
            data: (data) => DashboardCounters(data: data, t: t),
          ),
          const SizedBox(height: 16),
        ],
        if (deskAsync != null) ...[
          deskAsync.when(
            loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => _SectionCard(children: [ListTile(title: Text(t['home.dashboardLoadFailed']!))]),
            data: (panels) => DeskPanelCounters(panels: panels, t: t),
          ),
          const SizedBox(height: 16),
        ],
        _SectionCard(
          children: [
            for (final r in rows)
              ChatListTile(title: r.$1, subtitle: r.$2, icon: r.$3, color: r.$4, onTap: r.$5),
          ],
        ),
        if (role != 'lab' && role != 'accountant') ...[
          const SizedBox(height: 20),
          _SectionHeader(
            title: t['home.latestPatients']!,
            onViewAll: () => context.push('/records/patient-registrations'),
            t: t,
          ),
          const _LatestRegistrations(),
        ],
        if (!isDeskRole || role == 'accountant') ...[
          const SizedBox(height: 20),
          _SectionHeader(
            title: t['home.latestPayments']!,
            onViewAll: () => context.push('/records/payments'),
            t: t,
          ),
          const _LatestPayments(),
        ],
        if (dashboard != null) ..._dashboardSections(context, dashboard),
      ],
    );

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(isDeskRole ? deskPanelsProvider : dashboardProvider);
        ref.invalidate(patientRegistrationListProvider(null));
        ref.invalidate(paymentListProvider((search: null, from: null, to: null, source: null)));
      },
      child: list,
    );
  }

  /// Latest doctors, task statuses and tasks per education type, below the
  /// lists the dashboard already had — the web dashboard's other widgets.
  List<Widget> _dashboardSections(BuildContext context, DashboardData data) => [
        const SizedBox(height: 20),
        if (data.canDoctors)
          _SectionHeader(title: t['home.latestDoctors']!, onViewAll: () => context.push('/admin/doctors'), t: t)
        else
          _SectionTitle(t['home.latestDoctors']!),
        DashboardLatestDoctors(data: data, t: t),
        const SizedBox(height: 20),
        _SectionTitle(t['home.taskStatuses']!),
        DashboardTaskStatuses(data: data, t: t),
        if (data.educationTypes.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionTitle(t['home.tasksByEduType']!),
          DashboardTasksByEducationType(data: data),
        ],
      ];
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
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
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.onViewAll, required this.t});
  final String title;
  final VoidCallback onViewAll;
  final Map<String, String> t;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4, bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
          TextButton(onPressed: onViewAll, child: Text(t['home.viewAll']!)),
        ],
      ),
    );
  }
}

String _fmtDate(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  return d == null ? '—' : DateFormat('yyyy/MM/dd HH:mm').format(d);
}

/// The five newest registrations; each opens the patient registry.
class _LatestRegistrations extends ConsumerWidget {
  const _LatestRegistrations();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final async = ref.watch(patientRegistrationListProvider(null));
    return async.when(
      loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      error: (e, _) => _SectionCard(children: [ListTile(title: Text(e.toString()))]),
      data: (items) {
        if (items.isEmpty) return _SectionCard(children: [ListTile(title: Text(t['home.noPatientsYet']!))]);
        return _SectionCard(
          children: [
            for (final r in items.take(5))
              ChatListTile(
                title: r.name,
                color: chatToneFor(r.id),
                onTap: () => context.push('/records/patient-registrations'),
                chips: [
                  if (r.phone.isNotEmpty) ChatChip(label: r.phone, icon: Icons.call_outlined),
                  if (r.serviceName != null) ChatChip(label: r.serviceName!, icon: Icons.medical_services_outlined, color: Colors.indigo),
                  switch (r.screeningStatus) {
                    'clear' => ChatChip(label: t['patientRegFlutter.screeningClear']!, icon: Icons.verified_outlined, color: Colors.green),
                    'flagged' => ChatChip(label: t['patientRegFlutter.screeningFlagged']!, icon: Icons.coronavirus_outlined, color: Colors.red),
                    _ => ChatChip(label: t['patientRegFlutter.screeningPending']!, icon: Icons.hourglass_empty, color: Colors.orange),
                  },
                  ChatChip(label: _fmtDate(r.createdAt), icon: Icons.schedule),
                ],
              ),
          ],
        );
      },
    );
  }
}

/// The five newest payments; each opens the payments list.
class _LatestPayments extends ConsumerWidget {
  const _LatestPayments();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final async = ref.watch(paymentListProvider((search: null, from: null, to: null, source: null)));
    final money = NumberFormat('#,##0', 'en');
    return async.when(
      loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      error: (e, _) => _SectionCard(children: [ListTile(title: Text(e.toString()))]),
      data: (page) {
        if (page.items.isEmpty) return _SectionCard(children: [ListTile(title: Text(t['home.noPaymentsYet']!))]);
        return _SectionCard(
          children: [
            for (final p in page.items.take(5))
              ChatListTile(
                title: p.personName,
                color: Colors.teal,
                icon: Icons.payments_outlined,
                onTap: () => context.push('/records/payments'),
                chips: [
                  ChatChip(label: money.format(p.amount), icon: Icons.payments_outlined, color: Colors.green),
                  ChatChip(label: _fmtDate(p.paidAt), icon: Icons.schedule),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _Shortcut {
  const _Shortcut(this.label, this.icon, this.onTap, [this.color = Colors.indigo]);
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
}
