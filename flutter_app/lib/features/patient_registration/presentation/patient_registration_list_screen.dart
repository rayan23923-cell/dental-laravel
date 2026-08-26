import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/qr_image.dart';
import '../../clinic_settings/presentation/clinic_settings_providers.dart';
import '../../printing/data/pos_printer_service.dart';
import '../../printing/presentation/printer_error_snackbar.dart';
import '../../printing/presentation/printer_settings_providers.dart';
import '../../printing/presentation/ticket_print_animation.dart';
import '../../printing/presentation/ticket_renderer.dart';
import '../../printing/presentation/ticket_widget.dart';
import '../data/patient_registration_repository.dart';
import '../domain/patient_registration.dart';
import 'patient_registration_providers.dart';

/// "سجل تسجيل المرضى" — mirrors `PatientRegistrations/Index.vue`,
/// including its search + day/service filters (the repository/provider
/// already supported search; this screen just never had UI for it until
/// now). A FAB for a new registration, and a link to the days/services
/// settings screen, same as the web page's header links.
///
/// `pickMode: true` turns a row tap into `Navigator.pop(registration)`
/// instead of the normal QR/print actions, and hides the FAB/scan/settings
/// actions — reused by `PaymentFormScreen`'s and (Phase 2)
/// `AppointmentFormScreen`'s registered-patient picker, mirroring
/// `PatientListScreen(pickMode: true)`'s exact existing pattern so there's
/// one registration list, not two.
class PatientRegistrationListScreen extends ConsumerStatefulWidget {
  const PatientRegistrationListScreen({super.key, this.pickMode = false});
  final bool pickMode;

  @override
  ConsumerState<PatientRegistrationListScreen> createState() => _PatientRegistrationListScreenState();
}

class _PatientRegistrationListScreenState extends ConsumerState<PatientRegistrationListScreen> {
  final _searchController = TextEditingController();
  String _search = '';
  int? _registerDayId;
  int? _serviceId;
  Timer? _debounce;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => setState(() => _search = value));
  }

  PatientRegistrationFilter get _filter =>
      (search: _search.isEmpty ? null : _search, registerDayId: _registerDayId, serviceId: _serviceId);

  bool get _hasFilters => _search.isNotEmpty || _registerDayId != null || _serviceId != null;

  void _clearFilters() {
    _searchController.clear();
    _debounce?.cancel();
    setState(() {
      _search = '';
      _registerDayId = null;
      _serviceId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final registrationsAsync = ref.watch(patientRegistrationListProvider(_filter));
    final daysAsync = ref.watch(registerDaysProvider);
    final servicesAsync = ref.watch(servicesProvider);

    // Day narrows the service dropdown's *options* only (a filter, not
    // data entry — matches Index.vue's soft cascade), falling back to the
    // full flat service list when no day is picked yet.
    final days = daysAsync.valueOrNull ?? const [];
    final selectedDay = days.where((d) => d.id == _registerDayId).firstOrNull;
    final servicesForFilter = selectedDay?.services ?? servicesAsync.valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pickMode ? 'اختر مريضًا مسجلاً' : 'تسجيل المرضى'),
        actions: widget.pickMode
            ? null
            : [
                // Staff had no scanner entry point before Phase 5 — `/scan` was
                // doctor-only and hardcoded to task instances. This is the desk
                // clerk's way in to the scan-to-pay flow (Phase 5, Step 5).
                IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: 'مسح رمز الدفع',
                  onPressed: () => context.push('/records/patient-registrations/scan'),
                ),
                // Infectious-disease screening gate (2026-08-26) — the
                // lab/reception entry point, same shared ticket QR.
                IconButton(
                  icon: const Icon(Icons.coronavirus_outlined),
                  tooltip: 'فحص السلامة من الأمراض المعدية',
                  onPressed: () => context.push('/records/patient-registrations/scan-screening'),
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'إعدادات الخدمات والأيام',
                  onPressed: () => context.push('/records/patient-registrations/settings'),
                ),
              ],
      ),
      floatingActionButton: widget.pickMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                await context.push('/records/patient-registrations/new');
                ref.invalidate(patientRegistrationListProvider);
              },
              icon: const Icon(Icons.add),
              label: const Text('تسجيل مريض'),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    labelText: 'بحث بالاسم أو الهاتف',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    suffixIcon: _hasFilters
                        ? IconButton(icon: const Icon(Icons.clear), tooltip: 'مسح الفلاتر', onPressed: _clearFilters)
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownMenu<int>(
                        key: ValueKey('filter-day-$_registerDayId'),
                        enableFilter: true,
                        requestFocusOnTap: true,
                        expandedInsets: EdgeInsets.zero,
                        label: const Text('اليوم'),
                        initialSelection: days.any((d) => d.id == _registerDayId) ? _registerDayId : null,
                        dropdownMenuEntries: [
                          for (final d in days) DropdownMenuEntry(value: d.id, label: d.name),
                        ],
                        onSelected: (v) => setState(() {
                          _registerDayId = v;
                          if (!servicesForFilter.any((s) => s.id == _serviceId)) _serviceId = null;
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownMenu<int>(
                        key: ValueKey('filter-service-$_registerDayId'),
                        enableFilter: true,
                        requestFocusOnTap: true,
                        expandedInsets: EdgeInsets.zero,
                        label: const Text('الخدمة'),
                        initialSelection: servicesForFilter.any((s) => s.id == _serviceId) ? _serviceId : null,
                        dropdownMenuEntries: [
                          for (final s in servicesForFilter) DropdownMenuEntry(value: s.id, label: s.name),
                        ],
                        onSelected: (v) => setState(() => _serviceId = v),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: registrationsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text(error is ApiException ? error.userMessage : 'تعذر التحميل.')),
              data: (registrations) {
                if (registrations.isEmpty) {
                  return const Center(child: Text('لا يوجد سجلات مطابقة.'));
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(patientRegistrationListProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: registrations.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final r = registrations[i];
                      return Card(
                        child: ListTile(
                          title: Text(r.name),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Forced LTR: a lone phone number has no strong-
                              // direction anchor inside RTL text — same bidi
                              // class already fixed elsewhere in this app
                              // (academic_session_list_screen.dart). The
                              // service/day line below stays ambient RTL since
                              // it's genuine Arabic text, not a value to isolate.
                              Directionality(textDirection: TextDirection.ltr, child: Text(r.phone)),
                              Text('${r.serviceName ?? '—'} · ${r.registerDayName ?? '—'}'),
                              const SizedBox(height: 4),
                              _ScreeningBadge(status: r.screeningStatus),
                            ],
                          ),
                          isThreeLine: true,
                          onTap: widget.pickMode ? () => Navigator.of(context).pop(r) : () => _openPayment(context, r),
                          trailing: widget.pickMode
                              ? const Icon(Icons.chevron_left)
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!kIsWeb && Platform.isAndroid)
                                      IconButton(
                                        icon: const Icon(Icons.print_outlined),
                                        tooltip: 'إعادة طباعة التكت',
                                        onPressed: () => _reprintTicket(context, r),
                                      ),
                                    IconButton(
                                      icon: const Icon(Icons.qr_code_2),
                                      tooltip: 'رمز الدفع',
                                      onPressed: () => _showQrDialog(context, r),
                                    ),
                                  ],
                                ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Search-as-an-alternative-to-scanning (2026-08-26) — this list
  /// already had the search bar the user asked for; tapping a found row
  /// now opens the exact same payment screen the QR scan flow does,
  /// instead of doing nothing (this list's `onTap` previously only did
  /// anything in `pickMode`). Fetches fresh state (`status()`, not the
  /// list row's own possibly-stale `screeningStatus`) so the payment
  /// screen's gate reflects the latest lab result.
  Future<void> _openPayment(BuildContext context, PatientRegistration registration) async {
    try {
      final state = await ref.read(patientRegistrationRepositoryProvider).status(registration.id);
      if (context.mounted) context.push('/records/patient-registrations/payment', extra: state);
    } catch (e) {
      if (context.mounted) {
        final message = e is ApiException ? e.userMessage : 'تعذر فتح شاشة الدفع.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  /// The same desk-payment QR printed on the ticket (Phase 4D/5), viewable
  /// on screen too — the plan explicitly calls for both, since a ticket
  /// can be lost or the printer can fail (already observed once this
  /// project, see `PosPrinterService`'s doc comment).
  void _showQrDialog(BuildContext context, PatientRegistration registration) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(registration.name),
        content: SizedBox(
          width: 240,
          child: QrImage(path: '/patient-registrations/${registration.id}/qr', size: 220),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  /// Reprints an already-registered patient's ticket — today printing
  /// only ever happened once, immediately after creating a new
  /// registration (`patient_registration_form_screen.dart::_submit()`);
  /// this is the same best-effort sequence, triggered from the list
  /// instead. Android-POS-only, same constraint as the original print.
  Future<void> _reprintTicket(BuildContext context, PatientRegistration registration) async {
    Uint8List? qrBytes;
    try {
      final bytes = await ref.read(apiClientProvider).getBytes('/patient-registrations/${registration.id}/qr');
      qrBytes = Uint8List.fromList(bytes);
    } catch (_) {
      qrBytes = null;
    }
    Uint8List? logoBytes;
    try {
      final settings = await ref.read(clinicSettingsProvider.future);
      final logoUrl = settings?.ticketLogoUrl;
      if (logoUrl != null) {
        final bytes = await ref.read(apiClientProvider).getBytes(logoUrl);
        logoBytes = Uint8List.fromList(bytes);
      }
    } catch (_) {
      logoBytes = null;
    }
    if (!context.mounted) return;

    try {
      await precacheTicketImages(context, [qrBytes, logoBytes]);
      if (!context.mounted) return;
      final printerSettings = await ref.read(printerSettingsProvider.future);
      if (!context.mounted) return;
      final pngBytes = await renderWidgetToPng(
        context,
        TicketWidget(
          registration: registration,
          qrBytes: qrBytes,
          logoBytes: logoBytes,
          widthDots: printerSettings.dotsPerLine,
        ),
      );
      if (!context.mounted) return;
      await showTicketPrintAnimation<void>(
        context: context,
        ticketPngBytes: pngBytes,
        task: () => ref.read(posPrinterServiceProvider).printTicket(pngBytes),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إعادة طباعة التكت.')));
      }
    } catch (e) {
      if (context.mounted) {
        showPrinterErrorSnackBar(context, 'تعذرت طباعة التكت.', error: e);
      }
    }
  }
}

/// Small at-a-glance indicator of the infectious-disease screening result
/// (2026-08-26) — pure display; the actual gate is server-side
/// (`PatientScreeningGate`).
class _ScreeningBadge extends StatelessWidget {
  const _ScreeningBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      'clear' => (Colors.green, 'سليم'),
      'flagged' => (Colors.red, 'غير سليم'),
      _ => (Colors.orange, 'بانتظار الفحص'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: TextStyle(color: color.shade900, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
