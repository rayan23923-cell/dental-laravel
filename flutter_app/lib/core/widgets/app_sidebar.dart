import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/account_type.dart';
import '../../features/auth/domain/auth_account.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/auth_state.dart';
import '../../features/notifications/presentation/notifications_providers.dart';
import '../i18n/locale_controller.dart';
import '../router/nav_destinations.dart';
import '../theme/app_theme.dart';
import 'server_status_indicator.dart';
import 'settings_menu_sheet.dart';

/// The sidebar's own content — a ChatGPT-style persistent nav list with a
/// pinned bottom profile/settings/logout area (by request: "سايد بار
/// مشابه لواجهة chatgbt من حيث بروفايل والإعدادات"). Rendered two ways by
/// `AppShell`: permanently, beside the routed content on wide screens, or
/// as a slide-in overlay on narrow ones — this widget itself doesn't know
/// which, it just needs a `closeOverlay` callback when it's shown that way
/// (nav taps should dismiss the overlay too, not just navigate).
///
/// Instagram gradient usage (`InstagramColors.gradient` — defined in
/// `app_theme.dart` since the app's theme was first built, but never
/// actually used anywhere until now): the header badge, the selected-item
/// indicator bar, and the profile "story ring" below — three deliberately
/// small, accent-only spots, matching the same restraint the web app's
/// `GuestLayout.vue`/`BrandMark.vue` already established for this exact
/// gradient (logo + highlight, never a full-UI repaint).
class AppSidebar extends ConsumerWidget {
  const AppSidebar({super.key, this.onNavigate});

  /// Called after a nav/profile/settings tap navigates — lets the overlay
  /// variant close itself. Null for the permanent (wide-screen) sidebar.
  final VoidCallback? onNavigate;

  void _go(BuildContext context, String route) {
    onNavigate?.call();
    context.push(route);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider).valueOrNull;
    final account = authState is Authenticated ? authState.account : null;
    final accountType = account?.accountType ?? AccountType.doctor;
    final unreadCount = ref.watch(unreadNotificationCountProvider);
    final currentLocation = GoRouterState.of(context).matchedLocation;
    final t = ref.watch(translationsProvider);
    final destinations = navDestinationsFor(accountType, unreadNotifications: unreadCount, t: t, account: account);
    final theme = Theme.of(context);

    return Material(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: InstagramColors.gradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.medical_services_outlined, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        t['nav.clinicName']!,
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // Server connection: green/red, tap to reconnect (2026-10-22).
                      const ServerStatusChip(dense: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.dividerColor),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final destination in destinations)
                  _NavRow(
                    destination: destination,
                    selected: currentLocation == destination.route ||
                        currentLocation.startsWith('${destination.route}/'),
                    onTap: () => _go(context, destination.route),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.dividerColor),
          _ProfileRow(account: account, onTap: () => _go(context, '/profile')),
          if (accountType == AccountType.staff)
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: Text(t['nav.settings']!),
              onTap: () {
                onNavigate?.call();
                showAdminSettingsSheet(context);
              },
            ),
          ListTile(
            leading: const Icon(Icons.logout, color: InstagramColors.red),
            title: Text(t['nav.logout']!, style: const TextStyle(color: InstagramColors.red)),
            onTap: () => _confirmLogout(context, ref, t),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref, Map<String, String> t) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t['nav.logoutConfirmTitle']!),
        content: Text(t['nav.logoutConfirmBody']!),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(t['nav.cancel']!)),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t['nav.logout']!, style: const TextStyle(color: InstagramColors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      onNavigate?.call();
      await ref.read(authControllerProvider.notifier).logout();
    }
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.destination, required this.selected, required this.onTap});
  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? theme.colorScheme.primary.withValues(alpha: 0.08) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            children: [
              // Selected-state indicator — the gradient bar, not a flat fill.
              Container(
                width: 3,
                height: 28,
                margin: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(
                  gradient: selected ? InstagramColors.gradient : null,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Icon(destination.icon, size: 22, color: theme.colorScheme.onSurface),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    destination.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
              if (destination.badgeCount != null)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: InstagramColors.red, borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    '${destination.badgeCount}',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.account, required this.onTap});
  final AuthAccount? account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = this.account;
    final name = account?.displayName ?? '';
    final subtitle = switch (account) {
      StaffAccount(role: final role) => role,
      DoctorAccount(stageName: final stage, educationTypeName: final edu) => stage ?? edu ?? '',
      _ => '',
    };
    final imageUrl = switch (account) {
      StaffAccount(profileImageUrl: final url) => url,
      DoctorAccount(profileImageUrl: final url) => url,
      _ => null,
    };

    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(gradient: InstagramColors.gradient, shape: BoxShape.circle),
        child: CircleAvatar(
          backgroundColor: theme.colorScheme.surface,
          backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
          child: imageUrl == null ? Text(name.isNotEmpty ? name[0] : '?') : null,
        ),
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle.isNotEmpty ? Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
    );
  }
}
