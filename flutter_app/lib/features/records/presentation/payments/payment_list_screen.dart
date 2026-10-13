import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/i18n/locale_controller.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/widgets/chat_list_tile.dart';
import '../../domain/payment.dart';
import '../records_providers.dart';

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
  String? _source; // null (all) | 'appointment' | 'registration'

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
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/records/payments/new'),
        child: const Icon(Icons.add_card),
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
              data: (page) {
                if (page.items.isEmpty) {
                  return Center(child: Text(t['recordsHub.paymentsEmptyList']!));
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(paymentListProvider(_filters)),
                  child: ListView.separated(
                    padding: const EdgeInsets.only(top: 4, bottom: 88),
                    itemCount: page.items.length,
                    separatorBuilder: (_, __) => chatDivider,
                    itemBuilder: (context, i) => _PaymentTile(payment: page.items[i]),
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
              DropdownMenuItem(value: 'appointment', child: Text(t['recordsHub.sourceAppointment']!)),
              DropdownMenuItem(value: 'registration', child: Text(t['recordsHub.sourceRegistration']!)),
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
/// subtitle, and source / paid-by / date chips.
class _PaymentTile extends ConsumerWidget {
  const _PaymentTile({required this.payment});
  final Payment payment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final fromRegistration = payment.patientRegistrationName != null;
    return ChatListTile(
      title: payment.personName,
      color: Colors.green,
      icon: Icons.payments_outlined,
      // LTR isolate so the number keeps its order inside RTL text.
      subtitle: '\u2066${payment.amount.toStringAsFixed(2)}\u2069',
      chips: [
        fromRegistration
            ? ChatChip(label: t['recordsHub.sourceRegistration']!, icon: Icons.how_to_reg_outlined, color: Colors.teal)
            : ChatChip(label: t['recordsHub.sourceAppointment']!, icon: Icons.event_outlined, color: Colors.indigo),
        if (payment.paidBy != null && payment.paidBy!.isNotEmpty)
          ChatChip(label: payment.paidBy!, icon: Icons.person_outline, color: Colors.blueGrey),
        if (payment.paidAt != null)
          ChatChip(label: payment.paidAt!.split('T').first, icon: Icons.calendar_today_outlined, color: Colors.blueGrey),
      ],
      onTap: () => context.push('/records/payments/${payment.id}'),
    );
  }
}
