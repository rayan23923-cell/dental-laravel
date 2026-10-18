import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/auth_account.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/auth_state.dart';
import '../auth/staff_access.dart';
import '../i18n/locale_controller.dart';

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

List<_SettingsItem> _settingsItems(Map<String, String> t) => [
      _SettingsItem(t['settingsMenu.printerSettings']!, Icons.print_outlined, '/admin/printer-settings'),
      _SettingsItem(t['settingsMenu.clinicSettings']!, Icons.settings_outlined, '/admin/clinic-settings'),
      _SettingsItem(t['settingsMenu.permissions']!, Icons.lock_outline, '/admin/permissions'),
      _SettingsItem(t['settingsMenu.activityLog']!, Icons.history_outlined, '/admin/activity-log'),
      _SettingsItem(t['settingsMenu.backup']!, Icons.backup_outlined, '/admin/backup'),
    ];

Future<void> showAdminSettingsSheet(BuildContext context) {
  final container = ProviderScope.containerOf(context);
  final t = container.read(translationsProvider);
  final authState = container.read(authControllerProvider).valueOrNull;
  final account = authState is Authenticated ? authState.account : null;
  // Taken now: the sheet's own context is gone once it closes, so pushing
  // through it did nothing (2026-10-18, "it shows but won't open").
  final router = GoRouter.of(context);
  // Only what the account may open (2026-10-18).
  final items = [
    for (final item in _settingsItems(t))
      if (account is! StaffAccount || staffCanOpen(account, item.route)) item,
  ];
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
              child: Text(t['nav.settings']!, style: Theme.of(context).textTheme.titleMedium),
            ),
          ),
          for (final item in items)
            ListTile(
              leading: Icon(item.icon),
              title: Text(item.label),
              onTap: () {
                Navigator.of(context).pop();
                router.push(item.route);
              },
            ),
        ],
      ),
    ),
  );
}
