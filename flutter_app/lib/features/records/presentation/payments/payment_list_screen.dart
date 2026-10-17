import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/i18n/locale_controller.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/widgets/chat_list_tile.dart';
import '../../domain/payment.dart';
import '../records_providers.dart';
import '../../../clinic_settings/presentation/clinic_settings_providers.dart';
import 'payment_stats_overview.dart';

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
      builder: (context) => _PaymentFilterSheet(initialFrom: _from, initialTo: _to, initialSource: _source),
    );
    if (result != null) {
      setState(() {
        _from = result.from;
        _to = result.to;
        _source = result.source;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final paymentsAsync = ref.watch(paymentListProvider(_filters));
    final t = ref.watch(translationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(t['recordsHub.paymentsTitle']!),
        actions: [
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
              loading: () => const Center(child: CircularProgressIndicator()),
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
  const _PaymentFilterSheet({required this.initialFrom, required this.initialTo, required this.initialSource});
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
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            initialValue: _source,
            decoration: InputDecoration(labelText: t['recordsHub.sourceLabel'], border: const OutlineInputBorder(), isDense: true),
            items: [
              DropdownMenuItem(value: null, child: Text(t['recordsHub.sourceAll']!)),
              // Appointments dropped from payments (2026-10-14, by request).
              DropdownMenuItem(value: 'registration', child: Text(t['recordsHub.sourceRegistration']!)),
              DropdownMenuItem(value: 'lab', child: Text(t['payments.labFee']!)),
            ],
            onChanged: (v) => setState(() => _source = v),
          ),
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
    return ChatListTile(
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
      onTap: () => context.push('/records/payments/${payment.id}'),
    );
  }
}
