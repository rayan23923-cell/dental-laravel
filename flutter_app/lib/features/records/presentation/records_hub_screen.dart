import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// "السجلات" — staff-only entry point to the patients/appointments/
/// payments trio, mirroring `CaseSheetTypesScreen`'s role on the doctor
/// side (see flutter_app/README.md, "Case sheet create — the real
/// blocker was patient_id, not a Patients CRUD screen").
class RecordsHubScreen extends StatelessWidget {
  const RecordsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // "المرضى" (the standalone Patient CRUD list) is deliberately not
    // listed here — hidden from navigation now that "تسجيل المرضى" is the
    // reception-desk front door, but the route/screen behind it still
    // works: Appointments' patient picker has no other way to create a
    // new `Patient` row (see AppointmentController.php's formOptions()).
    final items = [
      ('تسجيل المرضى', Icons.how_to_reg_outlined, '/records/patient-registrations'),
      ('المواعيد', Icons.event_outlined, '/records/appointments'),
      ('الدفعات', Icons.payments_outlined, '/records/payments'),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('السجلات')),
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
