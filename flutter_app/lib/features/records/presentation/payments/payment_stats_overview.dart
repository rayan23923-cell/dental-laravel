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
    final range = stats.range;
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
                  // With a date filter (2026-11-04, by request): the
                  // filtered period's own figures, as on the web.
                  if (range != null) ...[
                    for (final card in [
                      (t['payments.rangeTotal']!, formatMoney(range.total, currency), trf(t['payments.paymentsCount']!, {'n': range.count})),
                      (t['payments.rangeAverage']!, formatMoney(range.average, currency), range.days > 1 ? trf(t['payments.rangeDaysOf']!, {'n': range.days}) : ''),
                      (
                        t['payments.rangeBestDay']!,
                        range.bestTotal == null ? t['payments.rangeNoBest']! : formatMoney(range.bestTotal!, currency),
                        range.bestDate ?? '—',
                      ),
                      (t['payments.rangePaidDays']!, '${range.paidDays}', trf(t['payments.rangeDaysOf']!, {'n': range.days})),
                    ])
                      SizedBox(width: width, child: _StatCard(label: card.$1, value: card.$2, sub: card.$3)),
                  ] else
                    for (final entry in periodKeys.entries)
                      SizedBox(
                        width: width,
                        child: _StatCard(
                          label: t[entry.value]!,
                          value: formatMoney(stats.periods[entry.key]?.total ?? 0, currency),
                          sub: trf(t['payments.paymentsCount']!, {'n': stats.periods[entry.key]?.count ?? 0}),
                        ),
                      ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          if (stats.daily.isNotEmpty)
            _BarChartCard(
              title: range == null ? t['payments.dailyChart']! : trf(t['payments.rangeDailyChart']!, {'from': range.from, 'to': range.to}),
              points: stats.daily,
              currency: currency,
              labelEvery: (stats.daily.length / 6).ceil(),
            )
          else if (range != null)
            Text(t['payments.rangeTooLong']!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          if (stats.monthly.isNotEmpty) ...[
            const SizedBox(height: 8),
            _BarChartCard(
              title: range == null ? t['payments.monthlyChart']! : t['payments.rangeMonthlyChart']!,
              points: stats.monthly,
              currency: currency,
              labelEvery: (stats.monthly.length / 12).ceil(),
            ),
          ],
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
          // By department: the case sheet the patient was linked to (2026-11-04).
          if (stats.byDepartment.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(t['payments.byDepartment']!, style: Theme.of(context).textTheme.titleSmall),
                    Text(t['payments.byDepartmentHint']!, style: Theme.of(context).textTheme.bodySmall),
                    for (final d in stats.byDepartment) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${d.name} · ${trf(t['payments.paymentsCount']!, {'n': d.count})}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: d.key == 'unlinked' ? Theme.of(context).disabledColor : null,
                                  ),
                            ),
                          ),
                          Text(formatMoney(d.total, currency), style: Theme.of(context).textTheme.bodyMedium),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _share(d.total, stats.byDepartment),
                          minHeight: 6,
                          color: d.key == 'lab'
                              ? Colors.amber
                              : d.key == 'unlinked'
                                  ? Colors.grey
                                  : Colors.teal,
                          backgroundColor: Colors.grey.withValues(alpha: 0.15),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// [total] against the biggest department row, for the bars.
double _share(double total, List<DepartmentTotal> rows) {
  final max = rows.fold<double>(0, (m, r) => r.total > m ? r.total : m);
  return max <= 0 ? 0 : (total / max).clamp(0, 1).toDouble();
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.sub});

  final String label;
  final String value;
  final String sub;

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
              child: Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ),
            Text(sub, style: theme.textTheme.bodySmall),
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
