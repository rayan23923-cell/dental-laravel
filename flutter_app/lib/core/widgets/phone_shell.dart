import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/account_type.dart';
import '../../features/auth/domain/auth_account.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/auth_state.dart';
import '../../features/notifications/presentation/notifications_providers.dart';
import '../auth/staff_access.dart';
import '../i18n/locale_controller.dart';
import '../router/nav_destinations.dart';
import '../theme/app_theme.dart';
import '../updater/update_available.dart';
import 'account_sheet.dart';
import 'server_status_indicator.dart';

/// Android/iPhone frame for the shell routes (2026-10-28, by request:
/// "اضف فوتر وهيدر مشابه لتليجرام ووزع السايد بار على الهيدر والفوتر").
/// The sidebar is split the way Telegram lays out its own screens:
/// - header: each screen's own AppBar, made flat with a centred title and
///   a hairline under it;
/// - footer: a floating glass tab bar with the sidebar's sections, the same list
///   and permission filtering as the sidebar ([navDestinationsFor]), and the
///   account avatar beside notifications (profile, server connection,
///   settings, logout — tap for the sheet; moved there from the header by
///   request, 2026-10-28: "حول البروفايل بجانب الاشعارات").
/// Wide screens and Windows keep the sidebar (`AppShell`).
class PhoneShell extends ConsumerWidget {
  const PhoneShell({required this.child, super.key});
  final Widget child;

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
        child: Stack(
          children: [
            // The screen ends at the bar's top: running under it hid the
            // last rows of every list whose own padding ignores the inset
            // (2026-10-28, "يتم تغطية اخر قسم او اخر بيانات بالفوتر").
            Padding(
              padding: EdgeInsets.only(
                bottom: keyboardOpen ? 0 : _TabBar.offsetFor(MediaQuery.paddingOf(context).bottom) + _TabBar.height + 6,
              ),
              child: SafeArea(
                bottom: false,
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  removeLeft: true,
                  removeRight: true,
                  removeBottom: !keyboardOpen,
                  child: Theme(
                    data: theme.copyWith(appBarTheme: appBarTheme),
                    child: child,
                  ),
                ),
              ),
            ),
            // Hidden while typing so the keyboard gets the room, as Telegram does.
            if (!keyboardOpen)
              Positioned(
                left: 16,
                right: 16,
                bottom: _TabBar.offsetFor(MediaQuery.paddingOf(context).bottom),
                child: Row(
                  children: [
                    Expanded(child: _TabBar(location: location)),
                    // Quick actions beside the bar, as Telegram's round
                    // button next to its tabs (2026-10-28).
                    const _QuickActionsButton(),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The footer's account tab: avatar with the server connection dot on it.
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
        borderRadius: BorderRadius.circular(_TabBar.height / 2),
        onTap: () => showAccountSheet(context, ref),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  padding: const EdgeInsets.all(1.5),
                  decoration: const BoxDecoration(gradient: InstagramColors.gradient, shape: BoxShape.circle),
                  child: CircleAvatar(
                    backgroundColor: theme.colorScheme.surface,
                    backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
                    child: imageUrl == null
                        ? Text(name.isNotEmpty ? name[0] : '?', style: const TextStyle(fontSize: 12))
                        : null,
                  ),
                ),
                const PositionedDirectional(top: -2, end: -2, child: ServerStatusDot(size: 10)),
                // A newer build is out: the same dot is on the sheet's update row.
                if (ref.watch(updateAvailableProvider) != null)
                  PositionedDirectional(
                    top: -3,
                    start: -3,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: InstagramColors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.colorScheme.surface, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              ref.watch(translationsProvider)['nav.account']!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The footer: a floating, rounded, frosted-glass tab bar (2026-10-28, by
/// request: "اجعل فوتر يبدو طافيا وحواف دائرية وتأثير زجاجي مثل تليجرام").
class _TabBar extends ConsumerWidget {
  const _TabBar({required this.location});
  final String location;

  static const height = 64.0;

  /// Gap under the bar: part of the home indicator's inset, or a margin.
  static double offsetFor(double bottomInset) => bottomInset > 0 ? (bottomInset * 0.6).clamp(12.0, 28.0) : 12.0;

  // Full-screen flows outside the shell are pushed on top; the shell's own
  // sections are switched to.
  static const _pushed = {'/scan'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final authState = ref.watch(authControllerProvider).valueOrNull;
    final account = authState is Authenticated ? authState.account : null;
    final destinations = navDestinationsFor(
      account?.accountType ?? AccountType.doctor,
      unreadNotifications: ref.watch(unreadNotificationCountProvider),
      t: ref.watch(translationsProvider),
      account: account,
    );
    final radius = BorderRadius.circular(height / 2);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.4 : 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            height: height,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: dark ? 0.62 : 0.72),
              borderRadius: radius,
              border: Border.all(color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.08), width: 0.8),
            ),
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
                const Expanded(child: _AccountButton()),
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

    final radius = BorderRadius.circular(_TabBar.height / 2);

    // The selected tab sits on a soft pill, as in Telegram.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected ? theme.colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: radius,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Badge(
                isLabelVisible: badge != null,
                label: Text(badge != null && badge > 99 ? '99+' : '${badge ?? ''}'),
                backgroundColor: InstagramColors.red,
                child: Icon(
                  selected ? (destination.selectedIcon ?? destination.icon) : destination.icon,
                  color: color,
                  size: 24,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One quick action of [_QuickActionsButton].
class _QuickAction {
  const _QuickAction(this.label, this.icon, this.color, this.route);
  final String label;
  final IconData icon;
  final Color color;
  final String route;
}

/// The round "+" beside the tab bar: the role's everyday actions one tap
/// away from any screen (2026-10-28, by request). Only what the account
/// may do; hidden when that leaves nothing (doctors have the scan tab).
class _QuickActionsButton extends ConsumerWidget {
  const _QuickActionsButton();

  static List<_QuickAction> _actionsFor(StaffAccount account, Map<String, String> t) {
    final registrations = staffCanOpen(account, '/records/patient-registrations');
    return [
      if (registrations && account.can('patients', 'create'))
        _QuickAction(
          t['patientRegFlutter.newRegistrationTitle']!,
          Icons.person_add_alt_1_outlined,
          Colors.indigo,
          '/records/patient-registrations/new',
        ),
      if (registrations)
        _QuickAction(
          t['patientRegFlutter.scanPaymentCode']!,
          Icons.qr_code_scanner,
          Colors.orange,
          '/records/patient-registrations/scan',
        ),
      if (staffCanOpen(account, '/lab'))
        _QuickAction(t['lab.scanTicket']!, Icons.coronavirus_outlined, Colors.red, '/lab/scan'),
      if (staffCanOpen(account, '/admin/doctors') && account.can('doctors', 'create'))
        _QuickAction(t['doctorsAdmin.newTitle']!, Icons.school_outlined, Colors.green, '/admin/doctors/new'),
      _QuickAction(t['search.title']!, Icons.search, Colors.blueGrey, '/search'),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider).valueOrNull;
    final account = authState is Authenticated ? authState.account : null;
    if (account is! StaffAccount) return const SizedBox.shrink();
    final t = ref.watch(translationsProvider);
    final actions = _actionsFor(account, t);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.4 : 0.12),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Material(
              color: theme.colorScheme.primary.withValues(alpha: 0.9),
              child: InkWell(
                onTap: () => _show(context, actions, t),
                child: const SizedBox(
                  width: _TabBar.height,
                  height: _TabBar.height,
                  child: Icon(Icons.add, color: Colors.white, size: 30),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _show(BuildContext context, List<_QuickAction> actions, Map<String, String> t) {
    // Taken now: the sheet's own context is gone once it closes.
    final router = GoRouter.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(t['quick.title']!, style: Theme.of(sheetContext).textTheme.titleMedium),
              ),
              Wrap(
                spacing: 12,
                runSpacing: 16,
                children: [
                  for (final a in actions)
                    SizedBox(
                      width: 96,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          router.push(a.route);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor: a.color.withValues(alpha: 0.14),
                                child: Icon(a.icon, color: a.color, size: 26),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                a.label,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
