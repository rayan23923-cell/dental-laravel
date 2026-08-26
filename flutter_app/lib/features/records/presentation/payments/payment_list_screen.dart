import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paymentsAsync = ref.watch(paymentListProvider(_search));

    return Scaffold(
      appBar: AppBar(title: const Text('الدفعات')),
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
                  onRefresh: () async => ref.invalidate(paymentListProvider(_search)),
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
