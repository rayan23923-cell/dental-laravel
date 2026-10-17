import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/platform_support.dart';
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
import '../../records/domain/payment.dart';
import '../data/patient_registration_repository.dart';
import '../domain/registration_payment_state.dart';

/// The payment-desk screen reached after scanning a registration's ticket
/// QR (or its on-screen equivalent) — shows whether it's paid, and if
/// not, takes the service's price and prints a receipt.
///
/// Mirrors the web since 2026-10-17: the amount is the service's fixed
/// price (no typed amount — the web's registration charges exactly that),
/// and the lab fee is not taken here but at the lab, with the screening
/// result (`LabFeeGate::chargeIfDue()` in `confirmScreening()`).
class PatientRegistrationPaymentScreen extends ConsumerStatefulWidget {
  const PatientRegistrationPaymentScreen({super.key, required this.initial});

  final RegistrationPaymentState initial;

  @override
  ConsumerState<PatientRegistrationPaymentScreen> createState() => _PatientRegistrationPaymentScreenState();
}

class _PatientRegistrationPaymentScreenState extends ConsumerState<PatientRegistrationPaymentScreen> {
  late RegistrationPaymentState _state;
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    _state = widget.initial;
  }

  /// The service's price, or null when the service has none (the web
  /// can't pick such a service either; it has to be priced first).
  double? get _amount {
    final price = _state.registration.servicePrice;
    return (price != null && price > 0) ? price : null;
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
      setState(() => _state = updated);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['payments.paymentRecorded']!)));

      await _printReceipt(updated, amount);
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : t['payments.recordPaymentFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  /// Prints the payment receipt on the POS printer (mobile only). The
  /// payment already succeeded — a print failure is reported, not treated
  /// as the operation having failed (same convention as the registration
  /// ticket in `patient_registration_form_screen.dart`).
  Future<void> _printReceipt(RegistrationPaymentState updated, double amount) async {
    if (!canPrintTickets || !mounted) return;
    final t = ref.read(translationsProvider);
    try {
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
          title: 'وصل دفع',
          amountLabel: 'المبلغ المدفوع',
          showTotal: true,
          logoBytes: logoBytes,
          headerTitle: settings?.universityName ?? settings?.clinicName,
          headerSubtitle: settings?.collegeName,
          widthDots: printerSettings.dotsPerLine,
        ),
      );
      await ref.read(posPrinterServiceProvider).printTicket(pngBytes);
    } catch (e) {
      if (mounted) {
        showPrinterErrorSnackBar(context, t['payments.paidPrintFailed']!, error: e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _state.registration;
    final t = ref.watch(translationsProvider);
    final currency = ref.watch(clinicSettingsProvider).valueOrNull?.currency;

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
          if (_state.labFee != null) ...[
            Card(
              color: _state.labPaid ? Colors.blue.shade50 : Colors.amber.shade50,
              child: ListTile(
                leading: Icon(Icons.science_outlined, color: _state.labPaid ? Colors.blue.shade700 : Colors.amber.shade800),
                title: Text('${t['payments.labFee']!}: ${formatMoney(_state.labFee!, currency)}'),
                subtitle: Text(_state.labPaid ? t['payments.labFeePaid']! : t['payments.labFeeWithResult']!),
                trailing: _state.labPaid ? Icon(Icons.check_circle, color: Colors.blue.shade700) : null,
              ),
            ),
            const SizedBox(height: 16),
          ],
          PaidBanner(state: _state),
          const SizedBox(height: 16),
          if (!r.isScreeningClear) ...[
            ScreeningBlockedBanner(registration: r),
          ] else if (_state.isPaid) ...[
            Text(t['labels.payments']!, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final p in _state.payments.where((p) => !p.isLabFee))
              Card(
                child: ListTile(
                  title: Text(formatMoney(p.amount, currency)),
                  subtitle: Text(p.paidAt ?? '—'),
                ),
              ),
          ] else ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.sell_outlined),
                title: Text(t['payments.servicePriceLabel']!),
                subtitle: _amount == null
                    ? Text(t['payments.noServicePrice']!, style: TextStyle(color: Theme.of(context).colorScheme.error))
                    : null,
                trailing: _amount == null
                    ? null
                    : Text(formatMoney(_amount!, currency), style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: (_paying || _amount == null) ? null : _confirmPayment,
              child: _paying
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(t['payments.takeServicePrice']!),
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
