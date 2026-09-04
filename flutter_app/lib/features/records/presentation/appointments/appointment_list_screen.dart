import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/locale_controller.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/appointment.dart';
import '../records_providers.dart';

/// `pickMode: true` turns taps into `Navigator.pop(appointment)` instead of
/// pushing the edit screen — reused by `PaymentFormScreen`'s appointment
/// picker, same pattern as `PatientListScreen`'s own `pickMode`.
class AppointmentListScreen extends ConsumerWidget {
  const AppointmentListScreen({super.key, this.pickMode = false});
  final bool pickMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appointmentsAsync = ref.watch(appointmentListProvider);
    final t = ref.watch(translationsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(pickMode ? t['recordsHub.pickAppointmentTitle']! : t['recordsHub.appointmentsTitle']!)),
      floatingActionButton: pickMode
          ? null
          : FloatingActionButton(
              onPressed: () => context.push('/records/appointments/new'),
              child: const Icon(Icons.add),
            ),
      body: appointmentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text(error is ApiException ? error.userMessage : t['recordsHub.loadFailed']!),
        ),
        data: (page) {
          if (page.items.isEmpty) {
            return Center(child: Text(t['recordsHub.appointmentsEmptyList']!));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(appointmentListProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: page.items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _AppointmentTile(appointment: page.items[i], pickMode: pickMode),
            ),
          );
        },
      ),
    );
  }
}

class _AppointmentTile extends ConsumerWidget {
  const _AppointmentTile({required this.appointment, required this.pickMode});
  final Appointment appointment;
  final bool pickMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    return Card(
      child: ListTile(
        leading: appointment.pinned ? const Icon(Icons.push_pin, size: 18) : null,
        title: Text(appointment.fullName),
        subtitle: Text([
          if (appointment.patientRegistrationName != null) appointment.patientRegistrationName!,
          if (appointment.appointmentDate != null) appointment.appointmentDate!.split('T').first,
          if (appointment.taskTitle != null) appointment.taskTitle!,
          if (appointment.confirmedByAccountant) t['recordsHub.confirmedBadge']!,
        ].join(' · ')),
        trailing: const Icon(Icons.chevron_left),
        onTap: () {
          if (pickMode) {
            Navigator.of(context).pop(appointment);
          } else {
            context.push('/records/appointments/${appointment.id}');
          }
        },
      ),
    );
  }
}
