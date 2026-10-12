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
  bool _reusing = false;

  /// The lab fee is taken with the result (2026-10-12, by request): picking
  /// "سليم" or "غير سليم" records it and prints one paid slip (see the
  /// server's `LabFeeGate::chargeIfDue`). Nothing is due when an earlier
  /// clear result is still valid.
  bool get _feeDue =>
      (_state.labFee ?? 0) > 0 && !_state.labPaid && _state.previousScreening == null;

  @override
  void initState() {
    super.initState();
    _state = widget.initial;
    // A valid earlier test found by phone (2026-10-12, by request): no new
    // test, the clear slip prints straight away. A name-only match waits
    // for staff to confirm it is the same patient.
    final previous = _state.previousScreening;
    if (previous != null && previous.matchedByPhone && _state.registration.screeningStatus == 'pending') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reusePrevious();
      });
    }
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

  /// Reuses the patient's still-valid earlier clear result (2026-10-12):
  /// marks this registration clear, then prints the lab slip exactly as
  /// after recording a result.
  Future<void> _reusePrevious() async {
    setState(() => _reusing = true);
    final t = ref.read(translationsProvider);
    // Kept for the slip: the refreshed state no longer carries it once
    // the registration is clear.
    final previous = _state.previousScreening;
    try {
      final updated = await ref.read(patientRegistrationRepositoryProvider).reuseScreening(_state.registration.id);
      if (!mounted) return;
      setState(() => _state = updated);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['screening.reused']!)));
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await _printSlip(updated, reusedFrom: previous);
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : t['screening.reuseFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _reusing = false);
    }
  }

  /// "2026-10-01" from the API's `checked_at` (ISO or "Y-m-d H:i:s").
  static String _formatDate(String? raw) {
    final parsed = raw == null ? null : DateTime.tryParse(raw);
    return parsed == null ? (raw ?? '—') : DateFormat('yyyy-MM-dd').format(parsed.toLocal());
  }

  /// Lab slip: the registration ticket layout with the result banner,
  /// payment status and the same patient QR (fetched like the reprint
  /// in `patient_registration_list_screen.dart`). With [reusedFrom] the
  /// fee row reads "exempt" plus the earlier test's date, as on the web
  /// `print/lab-result.blade.php`.
  Future<void> _printSlip(RegistrationPaymentState state, {PreviousScreening? reusedFrom}) async {
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
            if (reusedFrom != null) ...[
              (t['screening.paymentStatus']!, t['screening.exemptPrevious']!),
              (t['screening.previousCheckedAt']!, _formatDate(reusedFrom.checkedAt)),
            ] else if (state.labPaid) ...[
              (t['screening.paymentStatus']!, NumberFormat('#,##0.##').format(state.labPaidAmount)),
              (t['screening.statusLabel']!, t['screening.paid']!),
            ],
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
                  // The day is no longer asked (2026-10-12) — shown only on
                  // older registrations that have one.
                  Text(r.registerDayName == null ? (r.serviceName ?? '—') : '${r.serviceName ?? '—'} · ${r.registerDayName}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Lab fee status (2026-10-11, by request) — lab staff can see
          // whether the patient has paid the lab fee before screening.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _state.labPaid ? Colors.blue.shade50 : Colors.grey.shade100,
              border: Border.all(color: _state.labPaid ? Colors.blue.shade200 : Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(_state.labPaid ? Icons.paid : Icons.money_off, color: _state.labPaid ? Colors.blue.shade700 : Colors.grey.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${t['screening.paymentStatus']!}: ${_state.labPaid ? t['screening.paid']! : _feeDue ? t['screening.feeWithResult']! : t['screening.unpaid']!}'
                    '${(_state.labFee ?? 0) > 0 ? ' (${NumberFormat('#,##0.##').format(_state.labFee)})' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _StatusBanner(status: r.screeningStatus),
          // A still-valid earlier clear result (same phone, 2026-10-12):
          // no new test and no lab fee — one tap reuses it and prints the
          // slip. Recording a new result below stays possible.
          if (_state.previousScreening != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                border: Border.all(color: Colors.green.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified_outlined, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trf(t['screening.previousValid']!, {
                            'date': _formatDate(_state.previousScreening!.checkedAt),
                            'days': _state.labValidityDays,
                          }),
                          style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.w600),
                        ),
                        if (_state.previousScreening!.name != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            trf(
                              t[_state.previousScreening!.matchedByPhone
                                  ? 'screening.matchedByPhone'
                                  : 'screening.matchedByName']!,
                              {
                                'name': _state.previousScreening!.name!,
                                'phone': _state.previousScreening!.phone ?? '',
                              },
                            ),
                            style: TextStyle(
                              color: _state.previousScreening!.matchedByPhone
                                  ? Colors.green.shade900
                                  : Colors.amber.shade900,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _reusing || _submitting ? null : _reusePrevious,
              icon: const Icon(Icons.print_outlined),
              label: Text(t['screening.reusePrevious']!),
            ),
          ],
          const SizedBox(height: 24),
          Text(t['screening.labResultHeading']!, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (_feeDue) ...[
            Text(t['screening.payAndPrintHint']!, style: TextStyle(color: Colors.amber.shade900)),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _submitting || _reusing ? null : () => _confirm('clear'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(t['patientRegFlutter.screeningClear']!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _submitting || _reusing ? null : () => _confirm('flagged'),
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
