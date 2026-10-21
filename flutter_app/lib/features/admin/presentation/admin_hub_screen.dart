import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/staff_access.dart';
import '../../../core/i18n/locale_controller.dart';
import '../../auth/domain/auth_account.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/auth_state.dart';
import '../../clinic_settings/presentation/clinic_settings_providers.dart';

/// "الإدارة" — staff-only entry point to Phase 3's admin modules, built
/// incrementally (see flutter_app/README.md's Phase 3 breakdown). Distinct
/// from `RecordsHubScreen` ("السجلات"): that one is front-desk operations
/// (patients/appointments/payments), this one is system administration
/// (doctors/groups/sessions/settings/…).
///
/// Grouped into sections rather than one flat 14-item list — the same
/// grouping the web navbar was reorganized into (`AuthenticatedLayout.vue`,
/// "إدارة الأطباء" / "البيانات الأساسية" / "الإعدادات"), so a staff member
/// who knows the web layout finds the same shape here.
class _AdminItem {
  const _AdminItem(this.title, this.icon, this.route);
  final String title;
  final IconData icon;
  final String route;
}

class _AdminGroup {
  const _AdminGroup(this.title, this.items);
  final String title;
  final List<_AdminItem> items;
}

class AdminHubScreen extends ConsumerWidget {
  const AdminHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final authState = ref.watch(authControllerProvider).valueOrNull;
    final account = authState is Authenticated ? authState.account : null;
    // Only what the account may open (2026-10-18).
    bool allowed(_AdminItem item) => account is! StaffAccount || staffCanOpen(account, item.route);
    final groups = [
      // Doctors, tasks and task progress sit with the reference data,
      // ordered tasks → academic year → doctors → groups → task progress
      // (2026-10-13, by request — the same order as the web's menu).
      _AdminGroup(t['adminHub.referenceData']!, [
        _AdminItem(t['adminHub.educationTypes']!, Icons.school_outlined, '/admin/education-types'),
        _AdminItem(t['adminHub.stages']!, Icons.layers_outlined, '/admin/stages'),
        _AdminItem(t['adminHub.departments']!, Icons.apartment_outlined, '/admin/departments'),
        _AdminItem(t['adminHub.tasks']!, Icons.checklist_outlined, '/admin/tasks'),
        _AdminItem(t['adminHub.academicSessions']!, Icons.event_note_outlined, '/admin/academic-sessions'),
        _AdminItem(t['adminHub.doctors']!, Icons.medical_information_outlined, '/admin/doctors'),
        // Hidden while groups are turned off in clinic settings.
        if (ref.watch(groupsEnabledProvider)) _AdminItem(t['adminHub.groups']!, Icons.groups_outlined, '/admin/groups'),
        _AdminItem(t['labels.taskProgress']!, Icons.fact_check_outlined, '/admin/task-progress'),
        _AdminItem(t['adminHub.caseSheetTypes']!, Icons.description_outlined, '/admin/case-sheet-types'),
      ]),
      _AdminGroup(t['nav.settings']!, [
        _AdminItem(t['settingsMenu.printerSettings']!, Icons.print_outlined, '/admin/printer-settings'),
        _AdminItem(t['settingsMenu.clinicSettings']!, Icons.settings_outlined, '/admin/clinic-settings'),
        _AdminItem(t['registerSettings.title']!, Icons.tune, '/records/patient-registrations/settings'),
        _AdminItem(t['settingsMenu.users']!, Icons.manage_accounts_outlined, '/admin/users'),
        _AdminItem(t['settingsMenu.permissions']!, Icons.lock_outline, '/admin/permissions'),
        _AdminItem(t['departmentRolesAdmin.shortTitle']!, Icons.workspace_premium_outlined, '/admin/department-roles'),
        _AdminItem(t['settingsMenu.activityLog']!, Icons.history_outlined, '/admin/activity-log'),
        _AdminItem(t['settingsMenu.backup']!, Icons.backup_outlined, '/admin/backup'),
        // Ported from the web (2026-10-17).
        _AdminItem(t['waitingScreenSettings.title']!, Icons.tv_outlined, '/admin/waiting-screen-settings'),
        _AdminItem(t['waitingScreenPairing.title']!, Icons.connected_tv_outlined, '/admin/waiting-screen/pair'),
        _AdminItem(t['adminBroadcast.title']!, Icons.campaign_outlined, '/admin/broadcast'),
      ]),
    ]
        .map((g) => _AdminGroup(g.title, g.items.where(allowed).toList()))
        .where((g) => g.items.isNotEmpty)
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(t['nav.admin']!)),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: groups.length,
        itemBuilder: (context, groupIndex) {
          final group = groups[groupIndex];
          return Padding(
            padding: EdgeInsets.only(bottom: groupIndex == groups.length - 1 ? 0 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, right: 4, left: 4),
                  child: Text(
                    group.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < group.items.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          leading: Icon(group.items[i].icon),
                          title: Text(group.items[i].title),
                          trailing: const Icon(Icons.chevron_left),
                          onTap: () => context.push(group.items[i].route),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
