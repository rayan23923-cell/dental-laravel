import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../data/pos_printer_service.dart';

/// Shown whenever a `PosPrinterService.printTicket()` call throws — every
/// failure path in `PosPrinterPlugin.kt` funnels through the same
/// `finish(false, "...")` call with no distinct error code for "printer
/// not connected" versus anything else (paper-out/busy aren't even
/// reported from the print path itself — see that file's `finish()`
/// callers), so matching specific error strings here would be fragile.
/// In practice every failure this app can actually produce *is* some
/// flavor of "the configured printer wasn't reachable," so this always
/// offers the same fix: jump straight to "إعدادات الطابعة"
/// (`/admin/printer-settings`) rather than just reporting the raw
/// exception text and leaving the user to find that screen themselves.
///
/// `messagePrefix` keeps each call site's own framing (e.g. "تم التسجيل،
/// لكن..." — the underlying operation already succeeded, only printing
/// failed) instead of flattening all four call sites to one generic
/// wording.
///
/// `error` is the exception the call site just caught — passed through
/// only so this can special-case [BluetoothDisabledException] (2026-08-26):
/// when the configured printer is Bluetooth and the adapter was off,
/// `printTicket()` already triggered Android's "turn on Bluetooth?" system
/// prompt itself, so the message here just says so instead of sending the
/// user to printer settings for something a single tap already handles.
void showPrinterErrorSnackBar(BuildContext context, String messagePrefix, {Object? error}) {
  if (error is BluetoothDisabledException) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$messagePrefix البلوتوث غير مفعّل — وافق على تفعيله ثم أعد الطباعة.'),
      duration: const Duration(seconds: 6),
    ));
    return;
  }

  // Temporary (2026-08-28): appends the raw native error detail, purely
  // to diagnose the new iOS BLE plugin's real on-device failures instead
  // of guessing — remove once that path is confirmed stable, per this
  // file's own doc comment on why the message is normally kept generic.
  final detail = error is PlatformException ? ' [${error.code}: ${error.message}]' : '';

  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('$messagePrefix تحقق من توصيل الطابعة.$detail'),
    duration: const Duration(seconds: 10),
    action: SnackBarAction(
      label: 'إعدادات الطابعة',
      // Same fix as printer_settings_screen.dart's own SnackBarActions —
      // the theme's default action color is nearly invisible against
      // this app's SnackBar background in dark mode (found live on-device).
      textColor: InstagramColors.blue,
      onPressed: () => context.push('/admin/printer-settings'),
    ),
  ));
}
