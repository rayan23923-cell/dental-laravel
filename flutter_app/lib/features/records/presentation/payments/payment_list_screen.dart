import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../../core/auth/staff_access.dart';
import '../../../../core/i18n/locale_controller.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/widgets/swipe_actions.dart';
import '../../../../core/pdf/pdf_letterhead.dart';
import '../../../../core/platform/platform_support.dart';
import '../../../../core/widgets/chat_list_tile.dart';
import '../../../printing/data/pos_printer_service.dart';
import '../../../printing/presentation/payment_receipt_widget.dart';
import '../../../printing/presentation/printer_error_snackbar.dart';
import '../../../printing/presentation/printer_settings_providers.dart';
import '../../../printing/presentation/ticket_print_animation.dart';
import '../../../printing/presentation/ticket_renderer.dart';
import '../../data/records_repository.dart';
import '../../domain/payment.dart';
import '../records_providers.dart';
import '../../../clinic_settings/presentation/clinic_settings_providers.dart';
import 'payment_stats_overview.dart';
import 'payments_pdf.dart';
import '../../../../core/widgets/tg_spinner.dart';

class PaymentListScreen extends ConsumerStatefulWidget {
  const PaymentListScreen({super.key});

  @override
  ConsumerState<PaymentListScreen> createState() => _PaymentListScreenState();
}

class _PaymentListScreenState extends ConsumerState<PaymentListScreen> {
  final _searchController = TextEditingController();
  String? _search;

  // Filtering (2026-08-29) — date range on `paid_at` (the only date this
  // table has) and which of the two mutually-exclusive sources a payment
  // settled; see `Api\PaymentController::index()`'s matching comment for
  // why no doctor or paid/unpaid filter exists.
  DateTime? _from;
  DateTime? _to;
  String? _source; // null (all) | 'registration' | 'lab'

  bool get _hasActiveFilters => _from != null || _to != null || _source != null;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  PaymentFilters get _filters => (
        search: _search,
        from: _from == null ? null : DateFormat('yyyy-MM-dd').format(_from!),
        to: _to == null ? null : DateFormat('yyyy-MM-dd').format(_to!),
        source: _source,
      );

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<({DateTime? from, DateTime? to, String? source})>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PaymentFilterSheet(
        initialFrom: _from,
        initialTo: _to,
        initialSource: _source,
        sources: staffPaymentSources(ref, listen: false),
      ),
    );
    if (result != null) {
      setState(() {
        _from = result.from;
        _to = result.to;
        _source = result.source;
      });
    }
  }

  bool _printingReport = false;

  /// The payments report as a PDF (2026-10-17), the web `payments.report`
  /// page: every payment matching the current filters, with the overview.
  Future<void> _printReport() async {
    final t = ref.read(translationsProvider);
    final f = _filters;
    final sources = staffPaymentSources(ref, report: true, listen: false);
    setState(() => _printingReport = true);
    try {
      final report = await ref.read(recordsRepositoryProvider).fetchPaymentReport(
            search: f.search,
            from: f.from,
            to: f.to,
            source: f.source,
          );
      final settings = await ref.read(clinicSettingsProvider.future);
      final logo = await loadLetterheadLogo(ref, settings);
      await Printing.layoutPdf(
        name: '${sources?.length == 1 ? t[paymentsTitleKey(sources)]! : t['payments.reportTitle']!}.pdf',
        onLayout: (format) => buildPaymentsReportPdf(
          report: report,
          settings: settings,
          search: f.search,
          from: f.from,
          to: f.to,
          // A single fixed source is the title, not a filter (2026-10-26).
          source: sources?.length == 1 ? null : f.source,
          title: sources?.length == 1 ? 'تقرير ${t[paymentsTitleKey(sources)]!}' : null,
          format: format,
          logo: logo,
        ),
      );
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : '${t['payments.reportFailed']!} ($e)';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _printingReport = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final paymentsAsync = ref.watch(paymentListProvider(_filters));
    final t = ref.watch(translationsProvider);
    final sources = staffPaymentSources(ref);

    return Scaffold(
      appBar: AppBar(
        title: Text(t[paymentsTitleKey(sources)]!),
        actions: [
          // The lab / ticket desk grants include printing their report.
          if (staffPaymentSources(ref, report: true)?.isNotEmpty ?? true)
            IconButton(
              icon: _printingReport
                  ? const SizedBox(width: 20, height: 20, child: TgSpinner(strokeWidth: 2))
                  : const Icon(Icons.picture_as_pdf_outlined),
              tooltip: t['payments.printReport']!,
              onPressed: _printingReport ? null : _printReport,
            ),
          IconButton(
            icon: Icon(_hasActiveFilters ? Icons.filter_alt : Icons.filter_alt_outlined),
            tooltip: t['recordsHub.filterTooltip'],
            onPressed: _openFilters,
          ),
        ],
      ),
      body: Column(
        children: [
          // Chat-list style (2026-10-13, by request): search pill.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: ChatSearchField(
              controller: _searchController,
              hintText: t['recordsHub.searchPersonHint']!,
              onSubmitted: (v) => setState(() => _search = v.trim().isEmpty ? null : v.trim()),
            ),
          ),
          Expanded(
            child: paymentsAsync.when(
              loading: () => const Center(child: TgSpinner()),
              error: (error, stackTrace) => Center(
                child: Text(error is ApiException ? error.userMessage : t['recordsHub.loadFailed']!),
              ),
              // The income overview scrolls with the list as its first row
              // (2026-10-17), so a phone isn't left with a sliver of list.
              data: (page) {
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(paymentListProvider(_filters));
                    ref.invalidate(paymentStatsProvider(_filters));
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.only(top: 4, bottom: 88),
                    itemCount: page.items.length + 1 + (page.items.isEmpty ? 1 : 0),
                    separatorBuilder: (_, i) => i == 0 ? const SizedBox.shrink() : chatDivider,
                    itemBuilder: (context, i) {
                      if (i == 0) return PaymentStatsOverview(filters: _filters);
                      if (page.items.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(child: Text(t['recordsHub.paymentsEmptyList']!)),
                        );
                      }
                      return _PaymentTile(payment: page.items[i - 1]);
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
}

class _PaymentFilterSheet extends ConsumerStatefulWidget {
  const _PaymentFilterSheet({required this.initialFrom, required this.initialTo, required this.initialSource, this.sources});
  /// The account's payment sources (null: all); one source has no choice.
  final List<String>? sources;
  final DateTime? initialFrom;
  final DateTime? initialTo;
  final String? initialSource;

  @override
  ConsumerState<_PaymentFilterSheet> createState() => _PaymentFilterSheetState();
}

class _PaymentFilterSheetState extends ConsumerState<_PaymentFilterSheet> {
  late DateTime? _from = widget.initialFrom;
  late DateTime? _to = widget.initialTo;
  late String? _source = widget.initialSource;

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _from : _to) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => isFrom ? _from = picked : _to = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy-MM-dd');
    final t = ref.watch(translationsProvider);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t['recordsHub.filterSheetTitle']!, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _pickDate(isFrom: true),
                  child: InputDecorator(
                    decoration: InputDecoration(labelText: t['recordsHub.fromDateLabel'], border: const OutlineInputBorder(), isDense: true),
                    child: Text(_from == null ? '—' : dateFormat.format(_from!)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () => _pickDate(isFrom: false),
                  child: InputDecorator(
                    decoration: InputDecoration(labelText: t['recordsHub.toDateLabel'], border: const OutlineInputBorder(), isDense: true),
                    child: Text(_to == null ? '—' : dateFormat.format(_to!)),
                  ),
                ),
              ),
            ],
          ),
          if (widget.sources == null || widget.sources!.length > 1) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            initialValue: _source,
            decoration: InputDecoration(labelText: t['recordsHub.sourceLabel'], border: const OutlineInputBorder(), isDense: true),
            items: [
              DropdownMenuItem(value: null, child: Text(t['recordsHub.sourceAll']!)),
              // Appointments dropped from payments (2026-10-14, by request).
              if (widget.sources?.contains('registration') ?? true)
                DropdownMenuItem(value: 'registration', child: Text(t['recordsHub.sourceRegistration']!)),
              if (widget.sources?.contains('lab') ?? true) DropdownMenuItem(value: 'lab', child: Text(t['payments.labFee']!)),
            ],
            onChanged: (v) => setState(() => _source = v),
          ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop((from: null, to: null, source: null)),
                  child: Text(t['recordsHub.clearFiltersButton']!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop((from: _from, to: _to, source: _source)),
                  child: Text(t['recordsHub.applyButton']!),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Chat-list row (2026-10-13, by request): payer name, the amount as the
/// subtitle, and source / paid-by / date chips. Since 2026-10-17 the
/// source follows `type` (a lab fee is no longer shown as a registration
/// payment), archived patients are marked, and the amount is formatted
/// with the clinic's currency as on the web.
class _PaymentTile extends ConsumerWidget {
  const _PaymentTile({required this.payment});
  final Payment payment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final currency = ref.watch(clinicSettingsProvider).valueOrNull?.currency;
    // Swipe to print the receipt (2026-10-28, by request).
    return SwipeActions(
      rowKey: ValueKey('payment-${payment.id}'),
      start: SwipeAction(
        icon: Icons.receipt_long_outlined,
        label: t['payments.printReceipt']!,
        color: Colors.green,
        onTriggered: () => showPaymentReceiptOptions(context, ref, payment),
      ),
      child: ChatListTile(
      title: payment.personName,
      color: payment.isLabFee ? Colors.purple : Colors.green,
      icon: payment.isLabFee ? Icons.biotech_outlined : Icons.payments_outlined,
      subtitle: formatMoney(payment.amount, currency),
      chips: [
        switch (payment.source) {
          'lab' => ChatChip(label: t['payments.labFee']!, icon: Icons.biotech_outlined, color: Colors.purple),
          'appointment' => ChatChip(label: t['recordsHub.sourceAppointment']!, icon: Icons.event_outlined, color: Colors.indigo),
          _ => ChatChip(label: t['recordsHub.sourceRegistration']!, icon: Icons.how_to_reg_outlined, color: Colors.teal),
        },
        if (payment.isArchivedPatient)
          ChatChip(label: t['payments.archivedPatient']!, icon: Icons.archive_outlined, color: Colors.orange),
        if (payment.paidBy != null && payment.paidBy!.isNotEmpty)
          ChatChip(label: payment.paidBy!, icon: Icons.person_outline, color: Colors.blueGrey),
        if (payment.paidAt != null)
          ChatChip(label: payment.paidAt!.split('T').first, icon: Icons.calendar_today_outlined, color: Colors.blueGrey),
      ],
      actions: [
        ChatAction(
          icon: Icons.receipt_long_outlined,
          tooltip: t['payments.printReceipt']!,
          onPressed: () => showPaymentReceiptOptions(context, ref, payment),
        ),
      ],
      onTap: () => context.push('/records/payments/${payment.id}'),
      ),
    );
  }
}

/// "طباعة الوصل" for one recorded payment (2026-10-17), the web
/// `payments.receipt`: on the thermal printer where the app can print
/// tickets, and as a PDF everywhere.
Future<void> showPaymentReceiptOptions(BuildContext context, WidgetRef ref, Payment payment) async {
  final t = ref.read(translationsProvider);
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text(t['payments.printReceipt']!, style: Theme.of(context).textTheme.titleMedium)),
          if (canPrintTickets)
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: Text(t['payments.printReceiptThermal']!),
              onTap: () => Navigator.of(context).pop('thermal'),
            ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: Text(t['payments.printReceiptPdf']!),
            onTap: () => Navigator.of(context).pop('pdf'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'thermal') {
    await printPaymentReceiptTicket(context, ref, payment);
  } else {
    await printPaymentReceiptPdf(context, ref, payment);
  }
}

/// The receipt on the POS/desktop printer — same path as the
/// registration ticket (`renderWidgetToPng` + `PosPrinterService`).
Future<void> printPaymentReceiptTicket(BuildContext context, WidgetRef ref, Payment payment) async {
  final t = ref.read(translationsProvider);
  Uint8List? logoBytes;
  String? headerTitle;
  String? headerSubtitle;
  String? currency;
  try {
    final settings = await ref.read(clinicSettingsProvider.future);
    headerTitle = settings?.universityName ?? settings?.clinicName;
    headerSubtitle = settings?.collegeName;
    currency = settings?.currency;
    final logoUrl = settings?.ticketLogoUrl;
    if (logoUrl != null) {
      logoBytes = Uint8List.fromList(await ref.read(apiClientProvider).getBytes(logoUrl));
    }
  } catch (_) {
    logoBytes = null;
  }
  if (!context.mounted) return;
  try {
    await precacheTicketImages(context, [logoBytes]);
    if (!context.mounted) return;
    final printerSettings = await ref.read(printerSettingsProvider.future);
    if (!context.mounted) return;
    final pngBytes = await renderWidgetToPng(
      context,
      PaymentReceiptWidget(
        payment: payment,
        currency: currency,
        logoBytes: logoBytes,
        headerTitle: headerTitle,
        headerSubtitle: headerSubtitle,
        widthDots: printerSettings.dotsPerLine,
      ),
    );
    if (!context.mounted) return;
    await showTicketPrintAnimation<void>(
      context: context,
      ticketPngBytes: pngBytes,
      task: () => ref.read(posPrinterServiceProvider).printTicket(pngBytes),
    );
  } catch (e) {
    if (context.mounted) showPrinterErrorSnackBar(context, t['payments.receiptPrintFailed']!, error: e);
  }
}

/// The receipt as a PDF through the system print dialog.
Future<void> printPaymentReceiptPdf(BuildContext context, WidgetRef ref, Payment payment) async {
  final t = ref.read(translationsProvider);
  try {
    final settings = await ref.read(clinicSettingsProvider.future);
    final logo = await loadLetterheadLogo(ref, settings);
    await Printing.layoutPdf(
      name: '${t['payments.printReceipt']!} #${payment.id}.pdf',
      onLayout: (format) => buildPaymentReceiptPdf(payment: payment, settings: settings, format: format, logo: logo),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t['payments.receiptPrintFailed']!} ($e)')));
    }
  }
}
