import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../clinic_settings/presentation/clinic_settings_providers.dart';
import '../../printing/data/pos_printer_service.dart';
import '../../printing/presentation/printer_error_snackbar.dart';
import '../../printing/presentation/printer_settings_providers.dart';
import '../../printing/presentation/ticket_print_animation.dart';
import '../../printing/presentation/ticket_renderer.dart';
import '../../printing/presentation/ticket_widget.dart';
import '../data/patient_registration_repository.dart';
import '../domain/registration_payment_state.dart';

/// The lab/reception infectious-disease screening confirmation screen —
/// reached after scanning a registration's ticket QR (the exact same QR
/// the payment desk scans, see `qr_scan_screen.dart`'s
/// `QrScanMode.patientRegistrationScreening`). Records "سليم" (clear) or
/// "غير سليم" (flagged); until "سليم" is recorded, `PatientScreeningGate`
/// blocks payment and starting a task against this registration
/// server-side.
class PatientRegistrationScreeningScreen extends ConsumerStatefulWidget {
  const PatientRegistrationScreeningScreen({super.key, required this.initial});

  final RegistrationPaymentState initial;

  @override
  ConsumerState<PatientRegistrationScreeningScreen> createState() => _PatientRegistrationScreeningScreenState();
}

class _PatientRegistrationScreeningScreenState extends ConsumerState<PatientRegistrationScreeningScreen> {
  late RegistrationPaymentState _state;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _state = widget.initial;
  }

  Future<void> _confirm(String status) async {
    setState(() => _submitting = true);
    final t = ref.read(translationsProvider);
    try {
      final updated =
          await ref.read(patientRegistrationRepositoryProvider).confirmScreening(_state.registration.id, status);
      if (!mounted) return;
      setState(() => _state = updated);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(status == 'clear' ? t['screening.markedClear']! : t['screening.markedFlagged']!),
      ));
      // Saving a result prints the lab slip (2026-10-11, by request) —
      // same POS-printer path and mobile-only gate as the registration
      // ticket. A print failure never undoes the saved result.
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await _printSlip(updated);
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : t['screening.recordFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Lab slip: the registration ticket layout with the result banner,
  /// payment status and the same patient QR (fetched like the reprint
  /// in `patient_registration_list_screen.dart`).
  Future<void> _printSlip(RegistrationPaymentState state) async {
    final t = ref.read(translationsProvider);
    final r = state.registration;
    Uint8List? qrBytes;
    try {
      qrBytes = Uint8List.fromList(await ref.read(apiClientProvider).getBytes('/patient-registrations/${r.id}/qr'));
    } catch (_) {
      qrBytes = null;
    }
    Uint8List? logoBytes;
    String? headerTitle;
    String? headerSubtitle;
    try {
      final settings = await ref.read(clinicSettingsProvider.future);
      headerTitle = settings?.universityName ?? settings?.clinicName;
      headerSubtitle = settings?.collegeName;
      final logoUrl = settings?.ticketLogoUrl;
      if (logoUrl != null) {
        logoBytes = Uint8List.fromList(await ref.read(apiClientProvider).getBytes(logoUrl));
      }
    } catch (_) {
      logoBytes = null;
    }
    if (!mounted) return;

    try {
      await precacheTicketImages(context, [qrBytes, logoBytes]);
      if (!mounted) return;
      final printerSettings = await ref.read(printerSettingsProvider.future);
      if (!mounted) return;
      final result = r.screeningStatus == 'clear'
          ? t['patientRegFlutter.screeningClear']!
          : t['patientRegFlutter.screeningFlagged']!;
      final pngBytes = await renderWidgetToPng(
        context,
        TicketWidget(
          registration: r,
          qrBytes: qrBytes,
          logoBytes: logoBytes,
          headerTitle: headerTitle,
          headerSubtitle: headerSubtitle,
          resultBanner: '${t['screening.labResultHeading']!}: $result',
          extraRows: [
            (t['screening.paymentStatus']!, state.isPaid ? '${t['screening.paid']!} (${_money(state.totalPaid)})' : t['screening.unpaid']!),
            (t['screening.checkedAt']!, DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())),
          ],
          qrCaption: t['screening.patientCode']!,
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
      if (mounted) showPrinterErrorSnackBar(context, t['patientRegFlutter.printFailed']!, error: e);
    }
  }

  static String _money(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final r = _state.registration;
    final t = ref.watch(translationsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t['patientRegFlutter.screeningTooltip']!)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.name, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Directionality(textDirection: TextDirection.ltr, child: Text(r.phone)),
                  const SizedBox(height: 4),
                  Text('${r.serviceName ?? '—'} · ${r.registerDayName ?? '—'}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Payment status (2026-10-11, by request) — lab staff can see
          // whether the patient has paid before screening.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _state.isPaid ? Colors.blue.shade50 : Colors.grey.shade100,
              border: Border.all(color: _state.isPaid ? Colors.blue.shade200 : Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(_state.isPaid ? Icons.paid : Icons.money_off, color: _state.isPaid ? Colors.blue.shade700 : Colors.grey.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${t['screening.paymentStatus']!}: ${_state.isPaid ? '${t['screening.paid']!} (${_money(_state.totalPaid)})' : t['screening.unpaid']!}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _StatusBanner(status: r.screeningStatus),
          const SizedBox(height: 24),
          Text(t['screening.labResultHeading']!, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _submitting ? null : () => _confirm('clear'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(t['patientRegFlutter.screeningClear']!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _submitting ? null : () => _confirm('flagged'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                  icon: const Icon(Icons.cancel_outlined),
                  label: Text(t['patientRegFlutter.screeningFlagged']!),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends ConsumerWidget {
  const _StatusBanner({required this.status});

  final String status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final (color, icon, label) = switch (status) {
      'clear' => (Colors.green, Icons.check_circle, '${t['patientRegFlutter.currentStatusPrefix']} ${t['patientRegFlutter.screeningClear']}'),
      'flagged' => (Colors.red, Icons.warning_amber, '${t['patientRegFlutter.currentStatusPrefix']} ${t['patientRegFlutter.screeningFlagged']}'),
      _ => (Colors.amber, Icons.hourglass_empty, '${t['patientRegFlutter.currentStatusPrefix']} ${t['patientRegFlutter.screeningPending']}'),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.shade50,
        border: Border.all(color: color.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(color: color.shade900, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
