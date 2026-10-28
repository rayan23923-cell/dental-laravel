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
import 'app_sidebar.dart';
import 'server_status_indicator.dart';
import 'settings_menu_sheet.dart';

/// Android/iPhone frame for the shell routes (2026-10-28, by request:
/// "اضف فوتر وهيدر مشابه لتليجرام ووزع السايد بار على الهيدر والفوتر").
/// The sidebar is split the way Telegram lays out its own screens:
/// - header: each screen's own AppBar, made flat with a centred title and
///   a hairline under it, plus the account avatar on its leading corner
///   (profile, server connection, settings, logout — tap for the sheet);
/// - footer: a bottom tab bar with the sidebar's sections, the same list
///   and permission filtering as the sidebar ([navDestinationsFor]).
/// Wide screens and Windows keep the sidebar (`AppShell`).
class PhoneShell extends ConsumerWidget {
  const PhoneShell({required this.child, required this.clearance, super.key});
  final Widget child;

  /// Moves the AppBar's back arrow/title past the avatar (`AppShell`'s
  /// `_MenuButtonClearance`), passed in to keep that class private there.
  final Widget Function(Widget child) clearance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // The router's own current page, not the shell's state: a screen
    // pushed inside the shell (e.g. /records/patients from home) left the
    // shell's state on /home, and the wrong tab lit up.
    final router = GoRouter.of(context);
    return ListenableBuilder(
      listenable: router.routerDelegate,
      builder: (context, _) => _build(context, theme, router.state.matchedLocation),
    );
  }

  Widget _build(BuildContext context, ThemeData theme, String location) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    // Tabs switch with `go` (no growing stack), so the system back from a
    // tab other than home returns home first, like Telegram, rather than
    // leaving the app.
    final atHome = location == '/home';

    final appBarTheme = theme.appBarTheme.copyWith(
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: theme.dividerColor, width: 0.5)),
    );

    return PopScope(
      canPop: atHome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/home');
      },
      child: ColoredBox(
        color: theme.scaffoldBackgroundColor,
        child: Column(
          children: [
            Expanded(
              child: SafeArea(
                bottom: false,
                child: Stack(
                  children: [
                    // The tab bar below takes the bottom inset (home
                    // indicator), so the screen itself must not pad for it.
                    // (The SafeArea's own context, not the shell's — that one
                    // still carries the status bar inset.)
                    Builder(
                      builder: (context) => MediaQuery.removePadding(
                        context: context,
                        removeBottom: !keyboardOpen,
                        child: Theme(
                          data: theme.copyWith(appBarTheme: appBarTheme),
                          child: clearance(child),
                        ),
                      ),
                    ),
                    const PositionedDirectional(
                      top: 8,
                      start: 8,
                      child: _AccountButton(),
                    ),
                  ],
                ),
              ),
            ),
            // Hidden while typing so the keyboard gets the room, as Telegram does.
            if (!keyboardOpen) _TabBar(location: location),
          ],
        ),
      ),
    );
  }
}

/// The header's account avatar, with the server connection dot on it.
class _AccountButton extends ConsumerWidget {
  const _AccountButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final authState = ref.watch(authControllerProvider).valueOrNull;
    final account = authState is Authenticated ? authState.account : null;
    final name = account?.displayName ?? '';
    final imageUrl = switch (account) {
      StaffAccount(profileImageUrl: final url) => url,
      DoctorAccount(profileImageUrl: final url) => url,
      _ => null,
    };

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _showAccountSheet(context, ref),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(gradient: InstagramColors.gradient, shape: BoxShape.circle),
                child: CircleAvatar(
                  backgroundColor: theme.colorScheme.surface,
                  backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
                  child: imageUrl == null
                      ? Text(name.isNotEmpty ? name[0] : '?', style: theme.textTheme.titleSmall)
                      : null,
                ),
              ),
              const PositionedDirectional(top: 2, end: 2, child: ServerStatusDot(size: 11)),
            ],
          ),
        ),
      ),
    );
  }

  void _showAccountSheet(BuildContext context, WidgetRef ref) {
    final t = ref.read(translationsProvider);
    final authState = ref.read(authControllerProvider).valueOrNull;
    final account = authState is Authenticated ? authState.account : null;
    // Taken now: the sheet's own context is gone once it closes.
    final router = GoRouter.of(context);

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        void close() => Navigator.of(sheetContext).pop();
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProfileRow(
                account: account,
                onTap: () {
                  close();
                  router.push('/profile');
                },
              ),
              const Padding(
                padding: EdgeInsetsDirectional.only(start: 12, bottom: 4),
                child: Align(alignment: AlignmentDirectional.centerStart, child: ServerStatusChip()),
              ),
              const Divider(height: 1),
              if (account?.accountType == AccountType.staff)
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: Text(t['nav.settings']!),
                  onTap: () {
                    close();
                    showAdminSettingsSheet(context);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.logout, color: InstagramColors.red),
                title: Text(t['nav.logout']!, style: const TextStyle(color: InstagramColors.red)),
                onTap: () {
                  close();
                  confirmLogout(context, ref);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The footer: Telegram-style bottom tabs, icon over a small label.
class _TabBar extends ConsumerWidget {
  const _TabBar({required this.location});
  final String location;

  // Full-screen flows outside the shell are pushed on top; the shell's own
  // sections are switched to.
  static const _pushed = {'/scan'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final authState = ref.watch(authControllerProvider).valueOrNull;
    final account = authState is Authenticated ? authState.account : null;
    final destinations = navDestinationsFor(
      account?.accountType ?? AccountType.doctor,
      unreadNotifications: ref.watch(unreadNotificationCountProvider),
      t: ref.watch(translationsProvider),
      account: account,
    );

    return Material(
      color: theme.colorScheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.dividerColor, width: 0.5)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 58,
            child: Row(
              children: [
                for (final d in destinations)
                  Expanded(
                    child: _TabItem(
                      destination: d,
                      selected: location == d.route || location.startsWith('${d.route}/'),
                      onTap: () {
                        if (_pushed.contains(d.route)) {
                          context.push(d.route);
                        } else if (location != d.route) {
                          context.go(d.route);
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.destination, required this.selected, required this.onTap});
  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final badge = destination.badgeCount;

    return InkResponse(
      onTap: onTap,
      containedInkWell: true,
      highlightShape: BoxShape.rectangle,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Badge(
            isLabelVisible: badge != null,
            label: Text(badge != null && badge > 99 ? '99+' : '${badge ?? ''}'),
            backgroundColor: InstagramColors.red,
            child: Icon(selected ? (destination.selectedIcon ?? destination.icon) : destination.icon, color: color, size: 26),
          ),
          const SizedBox(height: 3),
          Text(
            destination.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
