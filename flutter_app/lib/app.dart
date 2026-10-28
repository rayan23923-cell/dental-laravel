import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/security/app_lock.dart';
import 'core/theme/app_theme.dart';
import 'core/updater/desktop_update_gate.dart';
import 'core/widgets/server_status_indicator.dart';
import 'features/case_sheet_forms/data/case_sheet_sync_service.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // Keeps the offline case-sheet sync listener alive for the app's whole
    // lifetime — see CaseSheetSyncService's own doc comment. `watch`, not
    // `read`: a plain `Provider` is never recreated by this widget's own
    // rebuilds either way, but `watch` is what keeps it from being torn
    // down if nothing else is holding a reference.
    ref.watch(caseSheetSyncServiceProvider);

    return MaterialApp.router(
      title: 'العيادة التعليمية',
      debugShowCheckedModeBanner: false,
      // Instagram-style visual identity (see core/theme/app_theme.dart) —
      // both a light and dark variant, following system brightness the
      // same way Instagram's own app does, rather than a single fetched
      // palette.
      theme: instagramLightTheme,
      darkTheme: instagramDarkTheme,
      themeMode: ThemeMode.system,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      // Connection strip at the bottom while the server is unreachable
      // (2026-10-22) — see ServerStatusFrame.
      // Fingerprint / Face ID lock when turned on (2026-10-28).
      builder: (context, child) => DesktopUpdateGate(
        child: AppLockGate(
          child: ServerStatusFrame(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}
