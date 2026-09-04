import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/auth_state.dart';
import 'app_translations.dart';

/// Bilingual support (2026-09-04, by request) — the Flutter counterpart of
/// the web's `App\Http\Middleware\ResolveLocale`. Same precedence:
///   1. The signed-in account's own `locale` (either `StaffAccount` or
///      `DoctorAccount` — both carry it, see `AuthAccount.locale`), when set.
///   2. The device's own language ("حسب لغة النظام") — only ar/en are
///      supported, anything else falls through.
///   3. `ar` — this app's existing all-Arabic default.
///
/// A `Provider`, not a `StateProvider`: there's nothing to hold locally —
/// it's fully derived from `authControllerProvider`, so watching that is
/// enough to react to both login (account with its own locale becomes
/// known) and a profile save (`AuthController.updateAccount` already
/// replaces the held account, which this provider is watching through).
const kSupportedLocales = ['ar', 'en'];

final localeProvider = Provider<String>((ref) {
  final authState = ref.watch(authControllerProvider).valueOrNull;
  final accountLocale = authState is Authenticated ? authState.account.locale : null;

  if (accountLocale != null && kSupportedLocales.contains(accountLocale)) {
    return accountLocale;
  }

  final deviceLocale = ui.PlatformDispatcher.instance.locale.languageCode;

  return kSupportedLocales.contains(deviceLocale) ? deviceLocale : 'ar';
});

/// The current locale's whole string table — `ref.watch(translationsProvider)['nav.home']!`.
/// Deliberately not a `context.tr('key')`-style extension: this app's other
/// providers are read the same plain `ref.watch(...)` way throughout, and a
/// missing key is easier to spot as a raw dotted string falling through
/// than as a thrown exception from a stricter helper.
final translationsProvider = Provider<Map<String, String>>((ref) {
  final locale = ref.watch(localeProvider);
  return locale == 'en' ? kTranslationsEn : kTranslationsAr;
});

/// Interpolates `{name}` placeholders in a translated string — the Dart
/// side of vue-i18n's `t(key, params)` param substitution, since
/// `kTranslationsAr`/`kTranslationsEn` are plain string maps with no
/// built-in interpolation of their own. Example:
/// `trf(t['myTasks.slotTitle']!, {'slot': slot.slot})`.
String trf(String template, Map<String, Object> params) {
  var result = template;
  for (final entry in params.entries) {
    result = result.replaceAll('{${entry.key}}', '${entry.value}');
  }
  return result;
}
