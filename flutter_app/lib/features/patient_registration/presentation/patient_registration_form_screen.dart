import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../clinic_settings/domain/clinic_settings.dart';
import '../../clinic_settings/presentation/clinic_settings_providers.dart';
import '../../printing/data/pos_printer_service.dart';
import '../../printing/presentation/printer_settings_providers.dart';
import '../../printing/presentation/printer_error_snackbar.dart';
import '../../printing/presentation/ticket_print_animation.dart';
import '../../printing/presentation/ticket_renderer.dart';
import '../../printing/presentation/ticket_widget.dart';
import '../data/patient_registration_repository.dart';
import '../domain/service.dart';
import 'patient_registration_providers.dart';

/// "تسجيل مريض جديد" — mirrors `PatientRegistrations/Create.vue`: name,
/// phone and a service picked from cards with its price (2026-10-12 — the
/// day picker is gone, registration is by service only). Payment is
/// mandatory and is the service's price, recorded by the server, so there
/// is no amount field; a service with no price yet cannot be picked. On Android, a successful submit also
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
  int? _serviceId;
  int? _taskId;
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    if (_serviceId == null) return;
    setState(() => _submitting = true);
    final t = ref.read(translationsProvider);

    try {
      final registration = await ref.read(patientRegistrationRepositoryProvider).create(
            name: _nameController.text.trim(),
            phone: _phoneController.text.trim(),
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
    final servicesAsync = ref.watch(servicesProvider);
    final t = ref.watch(translationsProvider);
    final priceFormat = NumberFormat('#,##0.##');

    return Scaffold(
      appBar: AppBar(title: Text(t['patientRegFlutter.newRegistrationTitle']!)),
      body: servicesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error is ApiException ? error.userMessage : t['common.loadFailed']!)),
        data: (services) {
          final Service? selected = services.where((s) => s.id == _serviceId).firstOrNull;
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
                Text(t['patientRegFlutter.serviceLabel']!, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                FormField<int>(
                  initialValue: services.any((s) => s.id == _serviceId) ? _serviceId : null,
                  validator: (v) => v == null ? t['profile.requiredField'] : null,
                  builder: (field) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (services.isEmpty) Text(t['patientRegFlutter.noServices']!),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1.9,
                        children: [
                          for (final s in services)
                            _ServiceCard(
                              service: s,
                              selected: s.id == field.value,
                              priceLabel: s.price == null
                                  ? t['patientRegFlutter.noPriceYet']!
                                  : priceFormat.format(s.price),
                              onTap: s.price == null
                                  ? null
                                  : () {
                                      field.didChange(s.id);
                                      setState(() => _serviceId = s.id);
                                    },
                            ),
                        ],
                      ),
                      if (field.errorText != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(field.errorText!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        ),
                    ],
                  ),
                ),
                // "التشخيص" picker removed from registration (2026-10-11, by
                // request); registrations are saved with no task.
                if (selected != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      title: Text(t['patientRegFlutter.amountDue']!),
                      trailing: Text(
                        priceFormat.format(selected.price),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _submitting || _serviceId == null ? null : _submit,
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

/// One service in the registration picker: its name and price; tapping
/// selects it. A service with no price yet is shown greyed out and cannot
/// be picked.
class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service, required this.selected, required this.priceLabel, required this.onTap});

  final Service service;
  final bool selected;
  final String priceLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  service.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  priceLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: enabled ? scheme.primary : scheme.error, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
