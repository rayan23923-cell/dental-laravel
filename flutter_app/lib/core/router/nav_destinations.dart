import 'package:flutter/material.dart';

import '../../features/auth/domain/account_type.dart';

/// One sidebar nav entry (`AppSidebar`) — mirrors the existing
/// `_AdminItem`/`_AdminGroup` pattern `admin_hub_screen.dart` already uses
/// for its own menu, rather than inventing a new shape.
class NavDestination {
  const NavDestination({
    required this.label,
    required this.icon,
    required this.route,
    this.badgeCount,
  });
  final String label;
  final IconData icon;
  final String route;
  final int? badgeCount;
}

/// Account-type-aware top-level sections for the persistent sidebar
/// (revision, by request — "سايد بار مشابه لواجهة chatgbt") — the same
/// branching `HomeScreen` already does (`AccountType.doctor` sees My
/// Tasks/Case Sheets; staff sees Records/Admin), now surfaced as a
/// standing nav list instead of one-off AppBar icons.
/// [t] is `ref.watch(translationsProvider)` from the caller — kept as a
/// plain parameter rather than importing the i18n provider here, so this
/// stays a pure function independent of Riverpod's `ref` (2026-09-04, by
/// request — same feature as the web's per-locale nav labels).
List<NavDestination> navDestinationsFor(
  AccountType type, {
  required int unreadNotifications,
  required Map<String, String> t,
}) {
  final notifications = NavDestination(
    label: t['nav.notifications']!,
    icon: Icons.notifications_outlined,
    route: '/notifications',
    badgeCount: unreadNotifications > 0 ? unreadNotifications : null,
  );

  if (type == AccountType.doctor) {
    return [
      NavDestination(
        label: t['nav.home']!,
        icon: Icons.home_outlined,
        route: '/home',
      ),
      NavDestination(
        label: t['nav.caseSheets']!,
        icon: Icons.description_outlined,
        route: '/case-sheets',
      ),
      NavDestination(
        label: t['nav.scanQr']!,
        icon: Icons.qr_code_scanner,
        route: '/scan',
      ),
      // "رموز المهام المعلقة" (by request, 2026-09-01) — matches the web
      // doctor layout's own nav (`DoctorLayout.vue`), which links this as
      // a top-level item alongside the equivalents of the ones above.
      NavDestination(
        label: t['nav.pendingTasksQr']!,
        icon: Icons.qr_code_2,
        route: '/pending-tasks-qr',
      ),
      notifications,
    ];
  }

  return [
    NavDestination(
      label: t['nav.home']!,
      icon: Icons.home_outlined,
      route: '/home',
    ),
    NavDestination(
      label: t['nav.records']!,
      icon: Icons.folder_shared_outlined,
      route: '/records',
    ),
    NavDestination(
      label: t['nav.admin']!,
      icon: Icons.admin_panel_settings_outlined,
      route: '/admin',
    ),
    notifications,
  ];
}
