import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/api_exception.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('الدفعات'),
        actions: [
          IconButton(
            icon: Icon(_hasActiveFilters ? Icons.filter_alt : Icons.filter_alt_outlined),
            tooltip: 'فلترة',
            onPressed: _openFilters,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/records/payments/new'),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'ابحث عن شخص لعرض كل مدفوعاته',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (v) => setState(() => _search = v.trim().isEmpty ? null : v.trim()),
            ),
          ),
          Expanded(
            child: paymentsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Center(
                child: Text(error is ApiException ? error.userMessage : 'تعذر التحميل.'),
              ),
              data: (page) {
                if (page.items.isEmpty) {
                  return const Center(child: Text('لا توجد دفعات بعد.'));
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(paymentListProvider(_filters)),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: page.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
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

class _PaymentFilterSheet extends StatefulWidget {
  const _PaymentFilterSheet({required this.initialFrom, required this.initialTo, required this.initialSource});
  final DateTime? initialFrom;
  final DateTime? initialTo;
  final String? initialSource;

  @override
  State<_PaymentFilterSheet> createState() => _PaymentFilterSheetState();
}

class _PaymentFilterSheetState extends State<_PaymentFilterSheet> {
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
          Text('فلترة الدفعات', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _pickDate(isFrom: true),
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'من تاريخ', border: OutlineInputBorder(), isDense: true),
                    child: Text(_from == null ? '—' : dateFormat.format(_from!)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () => _pickDate(isFrom: false),
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'إلى تاريخ', border: OutlineInputBorder(), isDense: true),
                    child: Text(_to == null ? '—' : dateFormat.format(_to!)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            initialValue: _source,
            decoration: const InputDecoration(labelText: 'المصدر', border: OutlineInputBorder(), isDense: true),
            items: const [
              DropdownMenuItem(value: null, child: Text('الكل')),
              DropdownMenuItem(value: 'appointment', child: Text('موعد')),
              DropdownMenuItem(value: 'registration', child: Text('تسجيل مريض')),
            ],
            onChanged: (v) => setState(() => _source = v),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop((from: null, to: null, source: null)),
                  child: const Text('مسح الفلاتر'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop((from: _from, to: _to, source: _source)),
                  child: const Text('تطبيق'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.payment});
  final Payment payment;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(payment.personName),
        subtitle: Text([
          payment.patientRegistrationName != null ? 'تسجيل مريض' : 'موعد',
          payment.amount.toStringAsFixed(2),
          if (payment.paidBy != null && payment.paidBy!.isNotEmpty) payment.paidBy!,
          if (payment.paidAt != null) payment.paidAt!.split('T').first,
        ].join(' · ')),
        trailing: const Icon(Icons.chevron_left),
        onTap: () => context.push('/records/payments/${payment.id}'),
      ),
    );
  }
}
