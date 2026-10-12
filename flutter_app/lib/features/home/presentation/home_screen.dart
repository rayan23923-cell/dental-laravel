import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/widgets/academic_year_banner.dart';
import '../../auth/domain/account_type.dart';
import '../../auth/domain/auth_account.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/auth_state.dart';
import '../../task_instances/presentation/my_tasks_screen.dart';

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
class _StaffDashboard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final registerShortcut = _Shortcut(
      t['labels.registerNewPatient']!,
      Icons.person_add_alt_1_outlined,
      () => context.push('/records/patient-registrations/new'),
    );
    final labShortcut = _Shortcut(
      t['labels.lab']!,
      Icons.coronavirus_outlined,
      () => context.push('/records/patient-registrations/scan-screening'),
    );
    final isDeskRole = role == 'reception' || role == 'lab';
    final shortcuts = role == 'reception'
        ? [registerShortcut]
        : role == 'lab'
            ? [labShortcut]
            : [
      _Shortcut(t['labels.registerNewPatient']!, Icons.person_add_alt_1_outlined, () => context.push('/records/patient-registrations/new')),
      _Shortcut(t['labels.appointments']!, Icons.event_outlined, () => context.push('/records/appointments')),
      _Shortcut(t['labels.payments']!, Icons.payments_outlined, () => context.push('/records/payments')),
      // Real bug found live: this still pointed at the old NFC-only
      // screen's route, removed when it was superseded by the full
      // day→group→department→doctor matrix (see that screen's own
      // docblock) — every tap crashed straight to "Page Not Found"
      // (`GoException: no routes for location: /admin/task-progress/nfc`).
      // The admin hub's own tile was updated at the time; this one was missed.
      _Shortcut(t['labels.taskProgress']!, Icons.fact_check_outlined, () => context.push('/admin/task-progress')),
      // The infectious-disease screening feature (2026-08-25) had no
      // dashboard entry point at all — the only way in was a small icon
      // inside the patient-registrations list, easy to miss. Added
      // (2026-08-26) so "المختبر" is a first-class shortcut like every
      // other daily action here.
      _Shortcut(
        t['labels.lab']!,
        Icons.coronavirus_outlined,
        () => context.push('/records/patient-registrations/scan-screening'),
      ),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Welcome header.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: colors.primary,
                backgroundImage: profileImageUrl != null ? NetworkImage(profileImageUrl!) : null,
                child: profileImageUrl == null ? const Icon(Icons.person, color: Colors.white, size: 28) : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 2),
                    Text(t['home.staffRole']!, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),

        const AcademicYearBanner(margin: EdgeInsets.only(top: 8)),

        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            t['home.quickShortcuts']!,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: colors.primary, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 8),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 2.2,
          children: [for (final s in shortcuts) _ShortcutCard(shortcut: s)],
        ),

        if (!isDeskRole) ...[
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            t['home.sections']!,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: colors.primary, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 8),
        _HubCard(
          title: t['nav.records']!,
          subtitle: t['home.recordsSubtitle']!,
          icon: Icons.folder_shared_outlined,
          onTap: () => context.push('/records'),
        ),
        const SizedBox(height: 10),
        _HubCard(
          title: t['nav.admin']!,
          subtitle: t['home.adminSubtitle']!,
          icon: Icons.admin_panel_settings_outlined,
          onTap: () => context.push('/admin'),
        ),
        ],
      ],
    );
  }
}

class _Shortcut {
  const _Shortcut(this.label, this.icon, this.onTap);
  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({required this.shortcut});
  final _Shortcut shortcut;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: shortcut.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(shortcut.icon, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  shortcut.label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HubCard extends StatelessWidget {
  const _HubCard({required this.title, required this.subtitle, required this.icon, required this.onTap});

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: colors.primary.withValues(alpha: 0.12),
                child: Icon(icon, color: colors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left),
            ],
          ),
        ),
      ),
    );
  }
}
