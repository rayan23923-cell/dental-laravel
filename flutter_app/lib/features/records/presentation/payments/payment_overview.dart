import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/i18n/locale_controller.dart';
import '../../domain/payment_stats.dart';

/// The web payments page's income overview, in the app (2026-10-17, by
/// request): today / week / month / year, the filtered total by source,
/// and the daily (last 30 days) and monthly (this year) bar charts.
class PaymentOverview extends ConsumerStatefulWidget {
  const PaymentOverview({super.key, required this.stats});

  final PaymentStats stats;

  @override
  ConsumerState<PaymentOverview> createState() => _PaymentOverviewState();
}

class _PaymentOverviewState extends ConsumerState<PaymentOverview> {
  bool _monthly = false;

  static final _money = NumberFormat('#,##0.##');

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final stats = widget.stats;
    final currency = stats.currency ?? '';
    String money(double v) => '⁦${_money.format(v)}⁩';

    final periods = [
      ('today', t['payments.periodToday']!),
      ('week', t['payments.periodWeek']!),
      ('month', t['payments.periodMonth']!),
      ('year', t['payments.periodYear']!),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 600 ? 4 : 2;
              const gap = 8.0;
              final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final (key, label) in periods)
                    SizedBox(
                      width: width,
                      child: _PeriodCard(
                        label: label,
                        total: money(stats.periods[key]?.total ?? 0),
                        detail: trf(t['payments.periodDetail']!, {
                          'currency': currency,
                          'count': stats.periods[key]?.count ?? 0,
                        }),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(t['payments.filteredTotal']!, style: Theme.of(context).textTheme.labelLarge)),
                      Text('${money(stats.filteredTotal)} $currency', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      for (final s in stats.bySource)
                        Text(
                          '${s.source == 'lab' ? t['payments.labFee']! : t['recordsHub.sourceRegistration']!}: '
                          '${money(s.total)} (${s.count})',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(value: false, label: Text(t['payments.chartDaily']!), icon: const Icon(Icons.bar_chart)),
                      ButtonSegment(value: true, label: Text(t['payments.chartMonthly']!), icon: const Icon(Icons.calendar_month)),
                    ],
                    selected: {_monthly},
                    onSelectionChanged: (v) => setState(() => _monthly = v.first),
                  ),
                  const SizedBox(height: 12),
                  _BarChart(points: _monthly ? stats.monthly : stats.daily, labelEvery: _monthly ? 1 : 5),
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
  const _PeriodCard({required this.label, required this.total, required this.detail});

  final String label;
  final String total;
  final String detail;

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
            Text(label, style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(total, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(detail, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Plain bars, no chart package: one per point, scaled to the largest,
/// with every [labelEvery]-th label under it. Read left to right like the
/// web chart, whatever the text direction.
class _BarChart extends StatelessWidget {
  const _BarChart({required this.points, required this.labelEvery});

  final List<PaymentSeriesPoint> points;
  final int labelEvery;

  static final _compact = NumberFormat.compact();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    final top = points.fold<double>(0, (m, p) => math.max(m, p.total));
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        height: 160,
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(top > 0 ? _compact.format(top) : '0', style: TextStyle(fontSize: 10, color: muted)),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final p in points)
                    Expanded(
                      child: Tooltip(
                        message: '${p.label}: ${NumberFormat('#,##0.##').format(p.total)}',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1),
                          child: FractionallySizedBox(
                            heightFactor: top > 0 ? math.max(p.total / top, p.total > 0 ? 0.02 : 0) : 0,
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                for (var i = 0; i < points.length; i++)
                  Expanded(
                    child: Text(
                      i % labelEvery == 0 ? points[i].label : '',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.visible,
                      softWrap: false,
                      style: TextStyle(fontSize: 9, color: muted),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
