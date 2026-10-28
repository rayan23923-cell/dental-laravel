import 'package:flutter/material.dart';

import '../../features/auth/domain/account_type.dart';
import '../../features/auth/domain/auth_account.dart';
import '../auth/staff_access.dart';

/// One sidebar nav entry (`AppSidebar`) — mirrors the existing
/// `_AdminItem`/`_AdminGroup` pattern `admin_hub_screen.dart` already uses
/// for its own menu, rather than inventing a new shape.
class NavDestination {
  const NavDestination({
    required this.label,
    required this.icon,
    required this.route,
    this.selectedIcon,
    this.badgeCount,
  });
  final String label;
  final IconData icon;

  /// Filled variant for the phone's bottom tab bar (2026-10-28).
  final IconData? selectedIcon;
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
/// A staff account sees "السجلات" and "الإدارة" only when it may open
/// something in them (2026-10-18).
List<NavDestination> navDestinationsFor(
  AccountType type, {
  required int unreadNotifications,
  required Map<String, String> t,
  AuthAccount? account,
}) {
  bool any(List<String> routes) => account is! StaffAccount || routes.any((r) => staffCanOpen(account, r));

  final notifications = NavDestination(
    label: t['nav.notifications']!,
    icon: Icons.notifications_outlined,
    selectedIcon: Icons.notifications,
    route: '/notifications',
    badgeCount: unreadNotifications > 0 ? unreadNotifications : null,
  );

  if (type == AccountType.doctor) {
    return [
      NavDestination(
        label: t['nav.home']!,
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
        route: '/home',
      ),
      NavDestination(
        label: t['nav.caseSheets']!,
        icon: Icons.description_outlined,
        selectedIcon: Icons.description,
        route: '/case-sheets',
      ),
      NavDestination(
        label: t['nav.scanQr']!,
        icon: Icons.qr_code_scanner,
        route: '/scan',
      ),
      notifications,
    ];
  }

  return [
    NavDestination(
      label: t['nav.home']!,
      icon: Icons.home_outlined,
        selectedIcon: Icons.home,
      route: '/home',
    ),
    if (any(recordsRoutes))
      NavDestination(
        label: t['nav.records']!,
        icon: Icons.folder_shared_outlined,
        selectedIcon: Icons.folder_shared,
        route: '/records',
      ),
    if (any(adminRoutes))
      NavDestination(
        label: t['nav.admin']!,
        icon: Icons.admin_panel_settings_outlined,
        selectedIcon: Icons.admin_panel_settings,
        route: '/admin',
      ),
    notifications,
  ];
}
