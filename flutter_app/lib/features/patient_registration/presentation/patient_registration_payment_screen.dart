import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/registration_status_banners.dart';
import '../../clinic_settings/domain/clinic_settings.dart';
import '../../clinic_settings/presentation/clinic_settings_providers.dart';
import '../../printing/data/pos_printer_service.dart';
import '../../printing/presentation/printer_error_snackbar.dart';
import '../../printing/presentation/printer_settings_providers.dart';
import '../../printing/presentation/receipt_widget.dart';
import '../../printing/presentation/ticket_renderer.dart';
import '../../records/data/records_repository.dart';
import '../data/patient_registration_repository.dart';
import '../domain/registration_payment_state.dart';

/// The payment-desk screen reached after scanning a registration's ticket
/// QR (or its on-screen equivalent) — shows whether it's paid, and if
/// not, takes a payment via quick-digit amount entry and prints a
/// receipt. See Phase 5's plan, Step 5.
class PatientRegistrationPaymentScreen extends ConsumerStatefulWidget {
  const PatientRegistrationPaymentScreen({super.key, required this.initial});

  final RegistrationPaymentState initial;

  @override
  ConsumerState<PatientRegistrationPaymentScreen> createState() => _PatientRegistrationPaymentScreenState();
}

class _PatientRegistrationPaymentScreenState extends ConsumerState<PatientRegistrationPaymentScreen> {
  late RegistrationPaymentState _state;
  final _amountController = TextEditingController();
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    _state = widget.initial;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  /// Quick-digit entry: `0`/`00`/`000` append to whatever's already
  /// typed, so a clerk types "5" then taps `000` for 5000 — exactly the
  /// flow described when this was planned. A bare `TextField` still
  /// allows typing any digits directly for anything the quick buttons
  /// don't cover.
  void _appendDigits(String digits) {
    setState(() {
      _amountController.text += digits;
      _amountController.selection = TextSelection.collapsed(offset: _amountController.text.length);
    });
  }

  void _clearAmount() => setState(() => _amountController.clear());

  double? get _amount {
    final value = double.tryParse(_amountController.text);
    return (value != null && value > 0) ? value : null;
  }

  Future<void> _confirmPayment() async {
    final amount = _amount;
    if (amount == null) return;
    setState(() => _paying = true);
    final t = ref.read(translationsProvider);

    try {
      // `patient_registration_id` (not `appointment_id`) — the desk-payment
      // flow this screen implements; see `Api\PaymentController::validatePayment()`.
      await ref.read(recordsRepositoryProvider).createPayment({
        'patient_registration_id': _state.registration.id,
        'amount': amount,
      });
      final updated = await ref.read(patientRegistrationRepositoryProvider).status(_state.registration.id);
      if (!mounted) return;
      setState(() {
        _state = updated;
        _amountController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['payments.paymentRecorded']!)));

      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS) && mounted) {
        try {
          // Same fetch-before-capture, fail-open pattern as the
          // registration ticket in `patient_registration_form_screen.dart`
          // — this receipt printed with no logo and hard-coded header
          // text at all before (2026-08-29 fix).
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
          await precacheTicketImages(context, [logoBytes]);
          if (!mounted) return;
          final printerSettings = await ref.read(printerSettingsProvider.future);
          if (!mounted) return;
          final pngBytes = await renderWidgetToPng(
            context,
            ReceiptWidget(
              registration: updated.registration,
              amountPaid: amount,
              totalPaid: updated.totalPaid,
              logoBytes: logoBytes,
              headerTitle: settings?.universityName ?? settings?.clinicName,
              headerSubtitle: settings?.collegeName,
              widthDots: printerSettings.dotsPerLine,
            ),
          );
          await ref.read(posPrinterServiceProvider).printTicket(pngBytes);
        } catch (e) {
          // The payment already succeeded — a print failure is reported,
          // not treated as the operation having failed (same convention
          // as the registration ticket in `patient_registration_form_screen.dart`).
          if (mounted) {
            showPrinterErrorSnackBar(context, t['payments.paidPrintFailed']!, error: e);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : t['payments.recordPaymentFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _state.registration;
    final t = ref.watch(translationsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t['payments.registrationPaymentTitle']!)),
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
          PaidBanner(state: _state),
          const SizedBox(height: 16),
          if (!r.isScreeningClear) ...[
            ScreeningBlockedBanner(registration: r),
          ] else if (_state.isPaid) ...[
            Text(t['labels.payments']!, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final p in _state.payments)
              Card(
                child: ListTile(
                  title: Text(NumberFormat('#,##0.##').format(p.amount)),
                  subtitle: Text(p.paidAt ?? '—'),
                ),
              ),
          ] else ...[
            Text(t['payments.enterAmount']!, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              decoration: InputDecoration(labelText: t['payments.amountLabel']!, border: const OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final digits in const ['0', '00', '000'])
                  OutlinedButton(onPressed: () => _appendDigits(digits), child: Text(digits)),
                OutlinedButton.icon(
                  onPressed: _clearAmount,
                  icon: const Icon(Icons.backspace_outlined),
                  label: Text(t['payments.clear']!),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: (_paying || _amount == null) ? null : _confirmPayment,
              child: _paying
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(t['payments.confirmAndPrint']!),
            ),
          ],
        ],
      ),
    );
  }
}

// `_ScreeningBlockedBanner`/`_PaidBanner` extracted (2026-08-29) to
// `core/widgets/registration_status_banners.dart` as `ScreeningBlockedBanner`/
// `PaidBanner` — `PaymentFormScreen` needed the identical banners, and a
// second drifting copy wasn't worth it for something this small.
