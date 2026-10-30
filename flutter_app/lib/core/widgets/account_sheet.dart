import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../features/auth/domain/account_type.dart';
import '../../features/auth/domain/auth_account.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/auth_state.dart';
import '../../features/profile/data/profile_repository.dart';
import '../i18n/locale_controller.dart';
import '../network/api_exception.dart';
import '../theme/app_theme.dart';
import '../theme/theme_mode_controller.dart';
import '../updater/desktop_update_checker.dart';
import '../updater/desktop_update_gate.dart';
import '../updater/update_available.dart';
import 'account_privacy_actions.dart';
import 'app_sidebar.dart';
import 'server_status_indicator.dart';
import 'settings_menu_sheet.dart';

/// The footer's "حسابي" sheet: profile, connection, then update, language
/// and theme right under the profile (2026-10-28, by request: "حول التحديث
/// واللغة والثيم اسفل الملف الشخصي"), then settings and logout. The update
/// row carries the same badge as the tab while a newer build is out.
Future<void> showAccountSheet(BuildContext context, WidgetRef ref) {
  // Taken now: the sheet's own context is gone once it closes.
  final router = GoRouter.of(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _AccountSheet(outerContext: context, outerRef: ref, router: router),
  );
}

class _AccountSheet extends ConsumerWidget {
  const _AccountSheet({required this.outerContext, required this.outerRef, required this.router});

  /// The shell's context, still mounted after the sheet closes (dialogs,
  /// the settings sheet and logout run on it).
  final BuildContext outerContext;

  /// The tab's ref: this sheet's own is disposed once it closes.
  final WidgetRef outerRef;
  final GoRouter router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final authState = ref.watch(authControllerProvider).valueOrNull;
    final account = authState is Authenticated ? authState.account : null;
    final update = ref.watch(updateAvailableProvider);
    final themeMode = ref.watch(themeModeProvider);
    void close() => Navigator.of(context).pop();

    final locale = account?.locale ?? '';
    final languageLabel = switch (locale) {
      'ar' => t['profile.languageAr']!,
      'en' => t['profile.languageEn']!,
      _ => t['profile.languageSystem']!,
    };
    final themeLabel = switch (themeMode) {
      ThemeMode.light => t['theme.light']!,
      ThemeMode.dark => t['theme.dark']!,
      ThemeMode.system => t['theme.system']!,
    };

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProfileRow(
              account: account,
              card: true,
              hint: t['account.viewProfile'],
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
            if (DesktopUpdateChecker.isSupported)
              ListTile(
                leading: Badge(
                  isLabelVisible: update != null,
                  smallSize: 10,
                  backgroundColor: InstagramColors.red,
                  child: const Icon(Icons.system_update_outlined),
                ),
                title: Text(t['profile.updates']!),
                subtitle: update != null
                    ? Text(
                        trf(t['update.available']!, {'version': update.version}),
                        style: const TextStyle(color: InstagramColors.red, fontWeight: FontWeight.w600),
                      )
                    : FutureBuilder<PackageInfo>(
                        future: PackageInfo.fromPlatform(),
                        builder: (context, snap) => Text(
                          snap.hasData ? trf(t['profile.currentVersion']!, {'version': snap.data!.version}) : '',
                        ),
                      ),
                onTap: () {
                  close();
                  if (update != null) {
                    AppUpdateFlow.offer(outerContext, update);
                  } else {
                    AppUpdateFlow.checkNow(outerContext);
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.translate),
              title: Text(t['profile.language']!),
              subtitle: Text(languageLabel),
              onTap: account == null ? null : () => _pickLanguage(context, ref, account, locale),
            ),
            ListTile(
              leading: const Icon(Icons.dark_mode_outlined),
              title: Text(t['theme.title']!),
              subtitle: Text(themeLabel),
              onTap: () => _pickTheme(context, ref, themeMode),
            ),
            const Divider(height: 1),
            // Both app stores want these reachable in the app (2026-10-28).
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(t['account.privacy']!),
              onTap: () => openSitePage(outerContext, 'privacy-policy'),
            ),
            if (account != null)
              ListTile(
                leading: const Icon(Icons.person_remove_outlined),
                title: Text(t['account.delete']!),
                onTap: () {
                  close();
                  requestAccountDeletion(outerContext, outerRef);
                },
              ),
            const Divider(height: 1),
            if (account?.accountType == AccountType.staff)
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: Text(t['nav.settings']!),
                onTap: () {
                  close();
                  showAdminSettingsSheet(outerContext);
                },
              ),
            ListTile(
              leading: const Icon(Icons.logout, color: InstagramColors.red),
              title: Text(t['nav.logout']!, style: const TextStyle(color: InstagramColors.red)),
              onTap: () {
                close();
                confirmLogout(outerContext, outerRef);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<T?> _choose<T>(BuildContext context, String title, T current, List<(T, String)> options) => showDialog<T>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        RadioGroup<T>(
          groupValue: current,
          onChanged: (v) => Navigator.of(context).pop(v),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [for (final (value, label) in options) RadioListTile<T>(value: value, title: Text(label))],
          ),
        ),
      ],
    ),
  );

  Future<void> _pickTheme(BuildContext context, WidgetRef ref, ThemeMode current) async {
    final t = ref.read(translationsProvider);
    final mode = await _choose(context, t['theme.title']!, current, [
      (ThemeMode.system, t['theme.system']!),
      (ThemeMode.light, t['theme.light']!),
      (ThemeMode.dark, t['theme.dark']!),
    ]);
    if (mode != null) await ref.read(themeModeProvider.notifier).set(mode);
  }

  /// Saved on the account, as the profile page does ('' = system language);
  /// the profile endpoint wants the name and email along with it.
  Future<void> _pickLanguage(BuildContext context, WidgetRef ref, AuthAccount account, String current) async {
    final t = ref.read(translationsProvider);
    final messenger = ScaffoldMessenger.of(outerContext);
    final locale = await _choose(context, t['profile.language']!, current, [
      ('', t['profile.languageSystem']!),
      ('ar', t['profile.languageAr']!),
      ('en', t['profile.languageEn']!),
    ]);
    if (locale == null || locale == current) return;
    final fields = switch (account) {
      StaffAccount() => {'full_name': account.fullName, 'email': account.email, 'phone': account.phone},
      DoctorAccount() => {'name': account.name, 'email': account.email, 'phone': account.phone},
    };
    try {
      final updated = await ref
          .read(profileRepositoryProvider)
          .update(accountType: account.accountType, fields: {...fields, 'locale': locale});
      ref.read(authControllerProvider.notifier).updateAccount(updated);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e is ApiException ? e.userMessage : t['profile.saveFailed']!)));
    }
  }
}
