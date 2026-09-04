import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/cascading_dropdown.dart';
import '../../clinic_settings/domain/clinic_settings.dart';
import '../../clinic_settings/presentation/clinic_settings_providers.dart';
import '../../printing/data/pos_printer_service.dart';
import '../../printing/presentation/printer_settings_providers.dart';
import '../../printing/presentation/printer_error_snackbar.dart';
import '../../printing/presentation/ticket_print_animation.dart';
import '../../printing/presentation/ticket_renderer.dart';
import '../../printing/presentation/ticket_widget.dart';
import '../../records/presentation/records_providers.dart' show tasksLookupProvider;
import '../data/patient_registration_repository.dart';
import '../domain/register_day.dart';
import 'patient_registration_providers.dart';

/// "تسجيل مريض جديد" — mirrors `PatientRegistrations/Create.vue`'s
/// day-first cascading picker exactly (pick a day, the service dropdown
/// filters to that day's services). On Android, a successful submit also
/// prints a ticket on the device's built-in POS printer — see
/// `PosPrinterService`'s doc comment. A print failure never blocks or
/// rolls back the registration itself, which already succeeded server-side
/// by the time printing is attempted.
class PatientRegistrationFormScreen extends ConsumerStatefulWidget {
  const PatientRegistrationFormScreen({super.key});

  @override
  ConsumerState<PatientRegistrationFormScreen> createState() => _PatientRegistrationFormScreenState();
}

class _PatientRegistrationFormScreenState extends ConsumerState<PatientRegistrationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  int? _dayId;
  int? _serviceId;
  int? _taskId;
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit(List<RegisterDay> days) async {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    if (_dayId == null || _serviceId == null) return;
    setState(() => _submitting = true);
    final t = ref.read(translationsProvider);

    try {
      final registration = await ref.read(patientRegistrationRepositoryProvider).create(
            name: _nameController.text.trim(),
            phone: _phoneController.text.trim(),
            registerDayId: _dayId!,
            serviceId: _serviceId!,
            taskId: _taskId,
          );
      ref.invalidate(patientRegistrationListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['patientRegFlutter.registeredSuccess']!)));
      }

      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS) && mounted) {
        try {
          // Best-effort: the registration already succeeded server-side,
          // so a QR fetch failure (offline, slow network) must not block
          // printing — the ticket just prints without the QR in that case.
          Uint8List? qrBytes;
          try {
            final bytes = await ref.read(apiClientProvider).getBytes('/patient-registrations/${registration.id}/qr');
            qrBytes = Uint8List.fromList(bytes);
          } catch (_) {
            qrBytes = null;
          }
          // Same fetch-before-capture, fail-open pattern as qrBytes above —
          // the logo is admin-uploaded (mutable), so it's fetched fresh
          // rather than bundled as an asset. `logoUrl` is already an
          // absolute URL (`Storage::url()`), which `getBytes` follows as-is.
          // `settings` is also kept (not just its logo) so the printed
          // header text can come from it too — see `TicketWidget.headerTitle`.
          Uint8List? logoBytes;
          ClinicSettings? settings;
          try {
            settings = await ref.read(clinicSettingsProvider.future);
            final logoUrl = settings?.ticketLogoUrl;
            if (logoUrl != null) {
              final bytes = await ref.read(apiClientProvider).getBytes(logoUrl);
              logoBytes = Uint8List.fromList(bytes);
            }
          } catch (_) {
            logoBytes = null;
          }
          if (!mounted) return;
          await precacheTicketImages(context, [qrBytes, logoBytes]);
          if (!mounted) return;
          final printerSettings = await ref.read(printerSettingsProvider.future);
          if (!mounted) return;
          final pngBytes = await renderWidgetToPng(
            context,
            TicketWidget(
              registration: registration,
              qrBytes: qrBytes,
              logoBytes: logoBytes,
              headerTitle: settings?.universityName ?? settings?.clinicName,
              headerSubtitle: settings?.collegeName,
              widthDots: printerSettings.dotsPerLine,
            ),
          );
          if (!mounted) return;
          await showTicketPrintAnimation<void>(
            context: context,
            ticketPngBytes: pngBytes,
            task: () => ref.read(posPrinterServiceProvider).printTicket(pngBytes),
          );
        } catch (e) {
          // The registration already succeeded — a print failure is
          // reported, not treated as the operation having failed.
          if (mounted) {
            showPrinterErrorSnackBar(context, t['patientRegFlutter.registeredPrintFailed']!, error: e);
          }
        }
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : t['patientRegFlutter.registrationFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final daysAsync = ref.watch(registerDaysProvider);
    final t = ref.watch(translationsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t['patientRegFlutter.newRegistrationTitle']!)),
      body: daysAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error is ApiException ? error.userMessage : t['common.loadFailed']!)),
        data: (days) {
          final selectedDay = days.where((d) => d.id == _dayId).firstOrNull;
          final servicesForDay = selectedDay?.services ?? const [];

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(labelText: t['patientRegFlutter.patientNameLabel']!, border: const OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? t['profile.requiredField']! : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: t['profile.phone']!, border: const OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? t['profile.requiredField']! : null,
                ),
                const SizedBox(height: 16),
                // DropdownMenu (not DropdownButtonFormField) so a clinic
                // with dozens of days/services gets type-to-filter for
                // free (`enableFilter`). Wrapped in a bare FormField to
                // keep the same required-field validation the plain
                // dropdown had — DropdownMenu has no FormField variant.
                FormField<int>(
                  initialValue: days.any((d) => d.id == _dayId) ? _dayId : null,
                  validator: (v) => v == null ? t['profile.requiredField'] : null,
                  builder: (field) => DropdownMenu<int>(
                    initialSelection: field.value,
                    enableFilter: true,
                    requestFocusOnTap: true,
                    expandedInsets: EdgeInsets.zero,
                    label: Text(t['patientRegFlutter.dayLabel']!),
                    errorText: field.errorText,
                    dropdownMenuEntries: [
                      for (final d in days) DropdownMenuEntry(value: d.id, label: d.name),
                    ],
                    onSelected: (v) {
                      field.didChange(v);
                      final newDay = days.where((d) => d.id == v).firstOrNull;
                      setState(() {
                        _dayId = v;
                        _serviceId = null;
                        // Day-governed diagnosis: only clear the current
                        // pick if the new day actually has rules and this
                        // task isn't one of them — an unconfigured day
                        // never needs to touch it.
                        if (newDay != null && newDay.taskIds.isNotEmpty && !newDay.taskIds.contains(_taskId)) {
                          _taskId = null;
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(height: 16),
                // `key` tied to `_dayId` forces this FormField to fully
                // reset (fresh `initialValue`) whenever the day changes,
                // instead of drifting out of sync with `_serviceId` (which
                // is cleared outside this widget, in the day picker above).
                FormField<int>(
                  key: ValueKey('service-field-$_dayId'),
                  initialValue: servicesForDay.any((s) => s.id == _serviceId) ? _serviceId : null,
                  validator: (v) => v == null ? t['profile.requiredField'] : null,
                  builder: (field) => DropdownMenu<int>(
                    initialSelection: field.value,
                    enabled: _dayId != null,
                    enableFilter: true,
                    requestFocusOnTap: true,
                    expandedInsets: EdgeInsets.zero,
                    label: Text(t['patientRegFlutter.serviceLabel']!),
                    helperText: _dayId == null
                        ? t['patientRegFlutter.chooseDayFirst']
                        : (servicesForDay.isEmpty ? t['patientRegFlutter.noServicesForDay'] : null),
                    errorText: field.errorText,
                    dropdownMenuEntries: [
                      for (final s in servicesForDay) DropdownMenuEntry(value: s.id, label: s.name),
                    ],
                    onSelected: _dayId == null
                        ? null
                        : (v) {
                            field.didChange(v);
                            setState(() => _serviceId = v);
                          },
                  ),
                ),
                const SizedBox(height: 16),
                // "التشخيص" — still doesn't gate anything *else* on this
                // form (see `PatientRegistration::task()`'s docblock for
                // the stage/education-type display below), but *which*
                // tasks are offered is now narrowed by the selected day,
                // once that day has any configured (empty `taskIds` means
                // no rule for this day — every task stays offered, same
                // as before this existed). Search comes free from
                // `CascadingDropdown` (`DropdownMenu(enableFilter: true)`),
                // fixing this picker's previous lack of any filter.
                Consumer(
                  builder: (context, ref, _) {
                    final tasksAsync = ref.watch(tasksLookupProvider);
                    final tasksForDay = tasksAsync.whenData(
                      (tasks) => selectedDay == null || selectedDay.taskIds.isEmpty
                          ? tasks
                          : tasks.where((t) => selectedDay.taskIds.contains(t.id)).toList(),
                    );
                    final selected = tasksAsync.valueOrNull?.where((t) => t.id == _taskId).firstOrNull;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CascadingDropdown(
                          key: ValueKey('task-$_dayId'),
                          label: t['patientRegFlutter.diagnosis']!,
                          itemsAsync: tasksForDay,
                          value: _taskId,
                          onChanged: (v) => setState(() => _taskId = v),
                        ),
                        if (selected != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, right: 4),
                            child: Text(
                              [
                                if (selected.stageName != null) selected.stageName!,
                                if (selected.educationTypeName != null) selected.educationTypeName!,
                              ].join(' · '),
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _submitting ? null : () => _submit(days),
                  child: _submitting
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(t['patientRegFlutter.submit']!),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
