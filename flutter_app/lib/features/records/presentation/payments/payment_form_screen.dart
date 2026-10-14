import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/i18n/locale_controller.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/widgets/registration_status_banners.dart';
import '../../../patient_registration/data/patient_registration_repository.dart';
import '../../../patient_registration/domain/patient_registration.dart';
import '../../../patient_registration/domain/registration_payment_state.dart';
import '../../../patient_registration/presentation/patient_registration_list_screen.dart';
import '../../data/records_repository.dart';
import '../../domain/payment.dart';
import '../records_providers.dart';
import '../../../../core/widgets/numeric_input.dart';

class PaymentFormScreen extends ConsumerStatefulWidget {
  const PaymentFormScreen({super.key, this.paymentId});
  final int? paymentId;

  @override
  ConsumerState<PaymentFormScreen> createState() => _PaymentFormScreenState();
}

class _PaymentFormScreenState extends ConsumerState<PaymentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  PatientRegistration? _registration;
  // Full payment/screening state for the currently-picked registration —
  // only populated (and only gates anything) while *creating* a new
  // payment; editing an existing one never fetches or checks this (see
  // `_applyPaymentState()`/`build()`'s `_isCreate` guards) — the payment
  // being edited already happened, so "already paid"/screening gating on
  // *today's* status would be wrong, and could block fixing a typo in an
  // old record. `PatientScreeningGate` still enforces screening
  // server-side on create regardless of any of this — this is purely
  // earlier, clearer client-side feedback (2026-08-29, by request: the
  // user hit a real case where neither the screening result nor an
  // existing payment were shown before submitting).
  RegistrationPaymentState? _paymentState;
  bool _scanningRegistration = false;
  // Appointment-sourced payments removed from this form (2026-08-29, by
  // request) — this screen now always settles a reception-desk
  // registration. The backend (`Payment.appointment_id`, both
  // controllers' `validatePayment()`) is untouched — only web
  // `Payments/Create.vue` still offers that source — but editing a
  // pre-existing appointment-sourced payment here now seeds an empty
  // registration picker rather than showing its appointment (see
  // `_seed()`, which no longer has an `appointmentId` branch); saving
  // such an edit would re-point it at whatever registration gets picked.
  // Accepted trade-off for the simplification, per the user's own request
  // — this form's `appointment_id` payload key was removed too, so
  // submitting without picking a registration is blocked the same way an
  // unpicked registration already was.
  //
  // `paid_at` removed from this screen entirely (2026-08-29, by request)
  // — never shown, never sent on create (the `payments` table's own
  // `DEFAULT current_timestamp()` fills it in), and never touched on
  // update (the `sometimes` partial-update rule leaves an edited
  // payment's original date alone).
  bool _seeded = false;
  bool _submitting = false;

  bool get _isCreate => widget.paymentId == null;
  bool get _blocked => _isCreate && _paymentState != null && !_paymentState!.registration.isScreeningClear;
  bool get _alreadyPaid => _isCreate && _paymentState != null && _paymentState!.isPaid;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _seed(Payment payment) {
    if (_seeded) return;
    _seeded = true;
    _amountController.text = payment.amount.toStringAsFixed(2);
    if (payment.patientRegistrationId != null) {
      final t = ref.read(translationsProvider);
      _registration = PatientRegistration(
        id: payment.patientRegistrationId!,
        name: payment.patientRegistrationName ?? trf(t['recordsHub.registrationFallbackTemplate']!, {'id': '${payment.patientRegistrationId}'}),
        phone: payment.patientRegistrationPhone ?? '',
        age: null,
        sex: null,
        address: null,
        occupation: null,
        serviceId: null,
        registerDayId: null,
        serviceName: null,
        registerDayName: null,
        createdAt: null,
        taskId: null,
        taskTitle: null,
        stageName: null,
        educationTypeName: null,
        // Unknown here — this seed comes from `Payment`'s denormalized
        // fields, not a fresh fetch, and this manual-entry form doesn't
        // gate on screening status anyway (only the QR desk flow does).
        screeningStatus: 'pending',
      );
    }
  }

  Future<void> _pickRegistration() async {
    final picked = await Navigator.of(context).push<PatientRegistration>(
      MaterialPageRoute(builder: (_) => const PatientRegistrationListScreen(pickMode: true)),
    );
    if (picked == null) return;

    // The list-picker only returns the bare registration, not its
    // payment/screening state (unlike a scan, which already carries both)
    // — fetch it separately so the picker path shows the identical
    // "already paid"/"screening clear" feedback the scan path does. Only
    // needed while creating — see `_paymentState`'s doc comment.
    if (_isCreate) {
      setState(() => _scanningRegistration = true);
      try {
        final state = await ref.read(patientRegistrationRepositoryProvider).status(picked.id);
        _applyPaymentState(state);
      } catch (e) {
        if (mounted) {
          final t = ref.read(translationsProvider);
          final message = e is ApiException ? e.userMessage : t['recordsHub.checkStatusFailedMsg']!;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        }
      } finally {
        if (mounted) setState(() => _scanningRegistration = false);
      }
    } else {
      setState(() => _registration = picked);
    }
  }

  /// "مسح رمز المريض" (2026-08-29) — scans the same reception-desk ticket
  /// QR used elsewhere, resolving it to a registration the same way
  /// `_pickRegistration()`'s list-picker does, just faster than typing a
  /// search. Reuses the staff-gated `patient-registrations/scan` endpoint
  /// (this whole screen is staff-only — see `RecordsHubScreen`), unlike
  /// the doctor-only case-sheet autofill scan.
  Future<void> _scanRegistration() async {
    setState(() => _scanningRegistration = true);
    try {
      final result = await context.push<RegistrationPaymentState>('/records/patient-registrations/scan-for-payment');
      if (result != null) _applyPaymentState(result);
    } finally {
      if (mounted) setState(() => _scanningRegistration = false);
    }
  }

  /// Shared by both resolution paths (scan and list-pick, when creating).
  /// Always sets `_registration` (what actually gets submitted); also
  /// keeps the full state for the paid/screening banners below, per
  /// `_paymentState`'s doc comment.
  void _applyPaymentState(RegistrationPaymentState state) {
    setState(() {
      _registration = state.registration;
      _paymentState = state;
    });
  }

  // Quick-digit amount entry (2026-08-29) — matches the reception-desk
  // `PatientRegistrationPaymentScreen` and web `Payments/Create.vue`'s
  // identical "0"/"00"/"000" append buttons, for consistent, fast amount
  // entry across every platform this app ships on.
  void _appendDigits(String digits) {
    setState(() {
      _amountController.text += digits;
      _amountController.selection = TextSelection.collapsed(offset: _amountController.text.length);
    });
  }

  void _clearAmount() => setState(() => _amountController.clear());

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    if (_registration == null) {
      final t = ref.read(translationsProvider);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['recordsHub.pleaseSelectRegisteredPatientMsg']!)));
      return;
    }
    // Belt-and-suspenders — the amount/submit section is already hidden
    // whenever either of these is true, so this should be unreachable in
    // practice; kept anyway in case state goes stale between a render and
    // a tap. `PatientScreeningGate` enforces the first server-side too.
    if (_blocked || _alreadyPaid) return;

    setState(() => _submitting = true);

    final payload = {
      'patient_registration_id': _registration!.id,
      // Explicit null (not just omitted) — required when *editing* a
      // payment that was previously appointment-sourced: `update()` is a
      // partial update (`sometimes` rules), so an omitted key would leave
      // the DB's old `appointment_id` in place, and the row would end up
      // with both FKs set at once, breaking the "never both" invariant
      // (`validatePayment()`'s required_without/prohibits pair) the rest
      // of the app relies on (list source badges, the new source filter).
      'appointment_id': null,
      'amount': double.tryParse(_amountController.text.trim()) ?? 0,
      // `paid_at` deliberately never sent — see its doc comment above.
    };

    try {
      final repo = ref.read(recordsRepositoryProvider);
      if (_isCreate) {
        await repo.createPayment(payload);
      } else {
        await repo.updatePayment(widget.paymentId!, payload);
      }
      ref.invalidate(paymentListProvider);
      if (mounted) {
        final t = ref.read(translationsProvider);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isCreate ? t['recordsHub.paymentAddedSuccess']! : t['recordsHub.savedSuccess']!)));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        final t = ref.read(translationsProvider);
        final message = e is ApiException ? e.userMessage : t['recordsHub.saveFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _delete() async {
    final t = ref.read(translationsProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t['recordsHub.deletePaymentTitle']!),
        content: Text(t['recordsHub.deletePaymentConfirm']!),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t['recordsHub.cancelAction']!)),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(t['recordsHub.deleteAction']!)),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(recordsRepositoryProvider).deletePayment(widget.paymentId!);
      ref.invalidate(paymentListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['recordsHub.deletedSuccess']!)));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : t['recordsHub.deleteFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final paymentAsync = _isCreate ? null : ref.watch(paymentProvider(widget.paymentId!));
    final t = ref.watch(translationsProvider);

    if (paymentAsync != null) {
      switch (paymentAsync) {
        case AsyncError(:final error):
          return Scaffold(
            appBar: AppBar(title: Text(t['recordsHub.paymentTitle']!)),
            body: Center(child: Text(error is ApiException ? error.userMessage : t['recordsHub.loadFailed']!)),
          );
        case AsyncData(:final value):
          _seed(value);
        default:
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isCreate ? t['recordsHub.newPaymentTitle']! : t['recordsHub.editPaymentTitle']!),
        actions: [
          if (!_isCreate) IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickRegistration,
                    child: InputDecorator(
                      decoration: InputDecoration(labelText: t['recordsHub.registeredPatientLabel'], border: const OutlineInputBorder(), isDense: true),
                      child: Text(_registration?.name ?? t['recordsHub.selectRegisteredPatientPlaceholder']!),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _scanningRegistration
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton.filledTonal(
                        onPressed: _scanRegistration,
                        icon: const Icon(Icons.qr_code_scanner),
                        tooltip: t['recordsHub.scanPatientTooltip'],
                      ),
              ],
            ),
            // Paid/screening feedback (2026-08-29, by request) — only
            // while creating; see `_paymentState`'s doc comment for why
            // editing skips all of this. Answers both of the user's
            // complaints in one place: whether this patient already paid,
            // and whether their screening is clear — neither was shown
            // before, so a clerk could try to charge an already-paid or
            // not-yet-clear patient with no feedback until submit failed.
            if (_isCreate && _paymentState != null) ...[
              const SizedBox(height: 8),
              PaidBanner(state: _paymentState!),
            ],
            if (_blocked) ...[
              const SizedBox(height: 8),
              ScreeningBlockedBanner(registration: _paymentState!.registration),
            ] else if (_alreadyPaid) ...[
              const SizedBox(height: 16),
              Text(t['recordsHub.paymentsTitle']!, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final p in _paymentState!.payments)
                Card(
                  child: ListTile(
                    title: Text(NumberFormat('#,##0.##').format(p.amount)),
                    subtitle: Text(p.paidAt ?? '—'),
                  ),
                ),
            ] else ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: decimalOnly,
                decoration: InputDecoration(labelText: t['recordsHub.amountLabel'], border: const OutlineInputBorder()),
                validator: (v) => (v == null || double.tryParse(v.trim()) == null) ? t['recordsHub.invalidAmountMsg'] : null,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final digits in const ['0', '00', '000'])
                    OutlinedButton(onPressed: () => _appendDigits(digits), child: Text(digits)),
                  OutlinedButton.icon(
                    onPressed: _clearAmount,
                    icon: const Icon(Icons.backspace_outlined),
                    label: Text(t['recordsHub.clearButton']!),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(t['recordsHub.saveButton']!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
