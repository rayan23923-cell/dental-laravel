import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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

class AdminHubScreen extends StatelessWidget {
  const AdminHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final groups = [
      const _AdminGroup('إدارة الأطباء', [
        _AdminItem('الأطباء', Icons.medical_information_outlined, '/admin/doctors'),
        _AdminItem('المجموعات', Icons.groups_outlined, '/admin/groups'),
        _AdminItem('خريطة كراسي العيادة', Icons.event_seat_outlined, '/admin/clinic-chairs'),
      ]),
      const _AdminGroup('البيانات الأساسية', [
        _AdminItem('الأعوام الدراسية', Icons.event_note_outlined, '/admin/academic-sessions'),
        _AdminItem('أنواع التعليم', Icons.school_outlined, '/admin/education-types'),
        _AdminItem('المراحل', Icons.layers_outlined, '/admin/stages'),
        _AdminItem('الأقسام', Icons.apartment_outlined, '/admin/departments'),
        _AdminItem('المهام', Icons.checklist_outlined, '/admin/tasks'),
        _AdminItem('أنواع النماذج السريرية', Icons.description_outlined, '/admin/case-sheet-types'),
      ]),
      const _AdminGroup('سير العمل', [
        _AdminItem('تقدم المهام', Icons.fact_check_outlined, '/admin/task-progress'),
      ]),
      const _AdminGroup('الإعدادات', [
        _AdminItem('إعدادات الطابعة', Icons.print_outlined, '/admin/printer-settings'),
        _AdminItem('إعدادات العيادة', Icons.settings_outlined, '/admin/clinic-settings'),
        _AdminItem('الصلاحيات', Icons.lock_outline, '/admin/permissions'),
        _AdminItem('سجل النشاط', Icons.history_outlined, '/admin/activity-log'),
        _AdminItem('النسخ الاحتياطي', Icons.backup_outlined, '/admin/backup'),
      ]),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('الإدارة')),
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
