import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/locale_controller.dart';
import '../../domain/payment.dart';
import '../../domain/payment_stats.dart';
import '../records_providers.dart';

/// The income overview above the payments list (2026-10-17), the same
/// figures as the web `Payments/Index` page: four period cards, the
/// 30-day and monthly bar charts, then the total and per-source split of
/// what the list's filters match. Charts are plain widgets (no chart
/// package) — a row of proportional bars is all the web shows either.
class PaymentStatsOverview extends ConsumerWidget {
  const PaymentStatsOverview({super.key, required this.filters});

  final PaymentFilters filters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final statsAsync = ref.watch(paymentStatsProvider(filters));
    return statsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: LinearProgressIndicator(),
      ),
      error: (_, __) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(t['payments.statsFailed']!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ),
      data: (stats) => _Overview(stats: stats, t: t),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.stats, required this.t});

  final PaymentStats stats;
  final Map<String, String> t;

  @override
  Widget build(BuildContext context) {
    final currency = stats.currency;
    const periodKeys = {
      'today': 'payments.today',
      'week': 'payments.thisWeek',
      'month': 'payments.thisMonth',
      'year': 'payments.thisYear',
    };
    final sourceLabels = {
      'registration': t['recordsHub.sourceRegistration']!,
      'lab': t['payments.labFee']!,
      'appointment': t['recordsHub.sourceAppointment']!,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              // Two per row on a phone, four on a wide screen.
              final perRow = constraints.maxWidth >= 640 ? 4 : 2;
              final width = (constraints.maxWidth - 8 * (perRow - 1)) / perRow;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in periodKeys.entries)
                    SizedBox(
                      width: width,
                      child: _PeriodCard(
                        label: t[entry.value]!,
                        total: stats.periods[entry.key]?.total ?? 0,
                        count: stats.periods[entry.key]?.count ?? 0,
                        currency: currency,
                        countTemplate: t['payments.paymentsCount']!,
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _BarChartCard(title: t['payments.dailyChart']!, points: stats.daily, currency: currency, labelEvery: 5),
          const SizedBox(height: 8),
          _BarChartCard(title: t['payments.monthlyChart']!, points: stats.monthly, currency: currency, labelEvery: 1),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(t['payments.filteredTotal']!, style: Theme.of(context).textTheme.titleSmall)),
                      Text(formatMoney(stats.filteredTotal, currency), style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                  for (final s in stats.bySource) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${sourceLabels[s.source] ?? s.source} · ${trf(t['payments.paymentsCount']!, {'n': s.count})}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        Text(formatMoney(s.total, currency), style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({
    required this.label,
    required this.total,
    required this.count,
    required this.currency,
    required this.countTemplate,
  });

  final String label;
  final double total;
  final int count;
  final String? currency;
  final String countTemplate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(formatMoney(total, currency), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ),
            Text(trf(countTemplate, {'n': count}), style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _BarChartCard extends StatelessWidget {
  const _BarChartCard({required this.title, required this.points, required this.currency, required this.labelEvery});

  final String title;
  final List<ChartPoint> points;
  final String? currency;

  /// Label every Nth bar so 30 daily labels don't collide.
  final int labelEvery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final max = points.fold<double>(0, (m, p) => p.total > m ? p.total : m);
    const chartHeight = 96.0;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            // Oldest first, left to right, in either language.
            Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < points.length; i++)
                    Expanded(
                      child: Tooltip(
                        message: '${points[i].label}: ${formatMoney(points[i].total, currency)}',
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 1),
                              child: Container(
                                height: max == 0 ? 2 : (points[i].total / max * chartHeight).clamp(2, chartHeight).toDouble(),
                                decoration: BoxDecoration(
                                  color: points[i].total == 0 ? theme.colorScheme.outlineVariant : theme.colorScheme.primary,
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              height: 14,
                              child: (i % labelEvery == 0)
                                  ? FittedBox(fit: BoxFit.scaleDown, child: Text(points[i].label, style: theme.textTheme.labelSmall))
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
