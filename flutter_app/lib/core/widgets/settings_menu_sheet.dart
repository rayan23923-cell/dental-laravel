import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Staff-only "الإعدادات" destinations — the exact 5 items already grouped
/// under that heading in `AdminHubScreen`, deep-linked directly rather than
/// duplicated as new screens. Reached from the sidebar's pinned bottom
/// settings row (`AppSidebar`).
class _SettingsItem {
  const _SettingsItem(this.label, this.icon, this.route);
  final String label;
  final IconData icon;
  final String route;
}

const _kSettingsItems = [
  _SettingsItem('إعدادات الطابعة', Icons.print_outlined, '/admin/printer-settings'),
  _SettingsItem('إعدادات العيادة', Icons.settings_outlined, '/admin/clinic-settings'),
  _SettingsItem('الصلاحيات', Icons.lock_outline, '/admin/permissions'),
  _SettingsItem('سجل النشاط', Icons.history_outlined, '/admin/activity-log'),
  _SettingsItem('النسخ الاحتياطي', Icons.backup_outlined, '/admin/backup'),
];

Future<void> showAdminSettingsSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text('الإعدادات', style: Theme.of(context).textTheme.titleMedium),
            ),
          ),
          for (final item in _kSettingsItems)
            ListTile(
              leading: Icon(item.icon),
              title: Text(item.label),
              onTap: () {
                Navigator.of(context).pop();
                context.push(item.route);
              },
            ),
        ],
      ),
    ),
  );
}
