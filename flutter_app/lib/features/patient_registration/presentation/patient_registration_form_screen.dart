import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/platform/platform_support.dart';
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
import '../../records/domain/payment.dart';
import '../data/patient_registration_repository.dart';
import '../domain/service.dart';
import 'live_registrations.dart';
import 'patient_registration_providers.dart';
import '../../../core/widgets/numeric_input.dart';

/// "تسجيل مريض جديد" — mirrors `PatientRegistrations/Create.vue`: name,
/// phone and a service picked from a horizontal, swipeable row of cards
/// with its price (2026-10-18) (2026-10-12 — the
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

class _PatientRegistrationFormScreenState extends ConsumerState<PatientRegistrationFormScreen>
    with LiveRegistrations<PatientRegistrationFormScreen> {
  // Services and prices edited elsewhere show up while the form is open
  // (2026-10-21); the mixin reloads them when the server's stamp changes.
  @override
  void onRegistrationsChanged() {}

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  int? _serviceId;
  int? _taskId;
  bool _submitting = false;

  /// Services as one swiping row, or wrapped in rows below each other
  /// (2026-10-18, by request); remembered on this device.
  static const _verticalKey = 'registration_services_vertical';
  bool _servicesVertical = false;

  @override
  void initState() {
    super.initState();
    // The list screen keeps the services loaded; take them fresh here.
    ref.invalidate(servicesProvider);
    SharedPreferences.getInstance().then((prefs) {
      final v = prefs.getBool(_verticalKey) ?? false;
      if (mounted && v != _servicesVertical) setState(() => _servicesVertical = v);
    });
  }

  void _toggleServicesLayout() {
    final v = !_servicesVertical;
    setState(() => _servicesVertical = v);
    SharedPreferences.getInstance().then((prefs) => prefs.setBool(_verticalKey, v));
  }

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
      final registration = await ref
          .read(patientRegistrationRepositoryProvider)
          .create(
            name: _nameController.text.trim(),
            phone: _phoneController.text.trim(),
            serviceId: _serviceId!,
            taskId: _taskId,
          );
      ref.invalidate(patientRegistrationListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['patientRegFlutter.registeredSuccess']!)));
      }

      if (canPrintTickets && mounted) {
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
              showPaid: true,
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
    final currency = ref.watch(clinicSettingsProvider).valueOrNull?.currency;

    return Scaffold(
      appBar: AppBar(title: Text(t['patientRegFlutter.newRegistrationTitle']!)),
      body: servicesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error is ApiException ? error.userMessage : t['common.loadFailed']!)),
        data: (services) {
          final Service? selected = services.where((s) => s.id == _serviceId).firstOrNull;
          final scheme = Theme.of(context).colorScheme;
          final nameField = TextFormField(
            controller: _nameController,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: t['patientRegFlutter.patientNameLabel']!,
              prefixIcon: const Icon(Icons.person_outline),
              border: const OutlineInputBorder(),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? t['profile.requiredField']! : null,
          );
          // Digits keep their left-to-right order but sit at the label's
          // side of the field, as the rest of the form reads (2026-10-21).
          final phoneField = TextFormField(
            controller: _phoneController,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.end,
            keyboardType: TextInputType.phone,
            inputFormatters: phoneOnly,
            decoration: InputDecoration(
              labelText: t['profile.phone']!,
              prefixIcon: const Icon(Icons.phone_outlined),
              border: const OutlineInputBorder(),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? t['profile.requiredField']! : null,
          );

          // Redesigned for the computer too (2026-10-21, by request): a
          // centred column of cards instead of fields stretched across the
          // whole window, name and phone side by side when there is room.
          return Form(
            key: _formKey,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _Section(
                      icon: Icons.badge_outlined,
                      title: t['patientRegFlutter.patientInfo']!,
                      child: LayoutBuilder(
                        builder: (context, constraints) => constraints.maxWidth >= 560
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 3, child: nameField),
                                  const SizedBox(width: 12),
                                  Expanded(flex: 2, child: phoneField),
                                ],
                              )
                            : Column(children: [nameField, const SizedBox(height: 12), phoneField]),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _Section(
                      icon: Icons.medical_services_outlined,
                      title: t['patientRegFlutter.serviceLabel']!,
                      trailing: IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(_servicesVertical ? Icons.view_carousel_outlined : Icons.grid_view),
                        tooltip: _servicesVertical
                            ? t['patientRegFlutter.servicesHorizontal']!
                            : t['patientRegFlutter.servicesVertical']!,
                        onPressed: _toggleServicesLayout,
                      ),
                      child: FormField<int>(
                        initialValue: services.any((s) => s.id == _serviceId) ? _serviceId : null,
                        validator: (v) => v == null ? t['profile.requiredField'] : null,
                        builder: (field) {
                          Widget card(Service s) => _ServiceCard(
                            service: s,
                            selected: s.id == field.value,
                            priceLabel: s.price == null
                                ? t['patientRegFlutter.noPriceYet']!
                                : formatMoney(s.price!, currency),
                            onTap: s.price == null
                                ? null
                                : () {
                                    field.didChange(s.id);
                                    setState(() => _serviceId = s.id);
                                  },
                          );
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (services.isEmpty) Text(t['patientRegFlutter.noServices']!),
                              // One row that swipes left and right, for faster entry
                              // than scanning a grid (2026-10-18, by request). The
                              // mouse drags it too, for the Windows app.
                              if (_servicesVertical)
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    const gap = 8.0;
                                    final perRow = (constraints.maxWidth / 158).floor().clamp(2, 8);
                                    final width = (constraints.maxWidth - gap * (perRow - 1)) / perRow;
                                    return Wrap(
                                      spacing: gap,
                                      runSpacing: gap,
                                      children: [
                                        for (final s in services) SizedBox(width: width, height: 96, child: card(s)),
                                      ],
                                    );
                                  },
                                )
                              else
                                SizedBox(
                                  height: 96,
                                  child: ScrollConfiguration(
                                    behavior: ScrollConfiguration.of(
                                      context,
                                    ).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: services.length,
                                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                                      itemBuilder: (context, i) => SizedBox(width: 150, child: card(services[i])),
                                    ),
                                  ),
                                ),
                              if (field.errorText != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(field.errorText!, style: TextStyle(color: scheme.error)),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                    // "التشخيص" picker removed from registration (2026-10-11, by
                    // request); registrations are saved with no task.
                    const SizedBox(height: 16),
                    // The amount due beside the button, so both read at a glance.
                    Card(
                      margin: EdgeInsets.zero,
                      color: scheme.primaryContainer.withValues(alpha: 0.35),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(t['patientRegFlutter.amountDue']!, style: Theme.of(context).textTheme.labelLarge),
                                  const SizedBox(height: 2),
                                  Text(
                                    selected == null ? '—' : formatMoney(selected.price!, currency),
                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  if (selected != null)
                                    Text(selected.name, style: Theme.of(context).textTheme.bodySmall),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              height: 52,
                              child: FilledButton.icon(
                                onPressed: _submitting || _serviceId == null ? null : _submit,
                                icon: _submitting
                                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.how_to_reg),
                                label: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Text(t['patientRegFlutter.submit']!, style: const TextStyle(fontSize: 16)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A titled card of the registration form (2026-10-21).
class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.child, this.trailing});

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
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
