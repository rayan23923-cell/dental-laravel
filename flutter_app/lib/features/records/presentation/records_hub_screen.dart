import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/staff_access.dart';
import '../../../core/i18n/locale_controller.dart';
import '../../auth/domain/auth_account.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/auth_state.dart';

/// "السجلات" — staff-only entry point to the patients/appointments/
/// payments trio (see flutter_app/README.md, "Case sheet create — the real
/// blocker was patient_id, not a Patients CRUD screen").
class RecordsHubScreen extends ConsumerWidget {
  const RecordsHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    // "المرضى" (the standalone Patient CRUD list) is deliberately not
    // listed here — hidden from navigation now that "تسجيل المرضى" is the
    // reception-desk front door, but the route/screen behind it still
    // works: Appointments' patient picker has no other way to create a
    // new `Patient` row (see AppointmentController.php's formOptions()).
    final authState = ref.watch(authControllerProvider).valueOrNull;
    final account = authState is Authenticated ? authState.account : null;
    final items = [
      (t['labels.registerPatients']!, Icons.how_to_reg_outlined, '/records/patient-registrations'),
      // Appointments hidden for now (2026-10-13, by request), as on the web.
      (t['labels.payments']!, Icons.payments_outlined, '/records/payments'),
    ].where((item) => account is! StaffAccount || staffCanOpen(account, item.$3)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(t['nav.records']!),
        actions: [
          IconButton(
            tooltip: t['search.title'],
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/search'),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final (title, icon, route) = items[i];
          return Card(
            child: ListTile(
              leading: Icon(icon),
              title: Text(title),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => context.push(route),
            ),
          );
        },
      ),
    );
  }
}
