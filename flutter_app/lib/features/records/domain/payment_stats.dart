/// Mirrors `Api\PaymentController::stats()` — the income overview the web
/// `Payments/Index` page shows (2026-10-17, see `App\Support\PaymentStats`).
class PaymentStats {
  const PaymentStats({
    required this.periods,
    required this.daily,
    required this.monthly,
    required this.filteredTotal,
    required this.bySource,
    this.currency,
  });

  factory PaymentStats.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    final periods = data['periods'] as Map<String, dynamic>? ?? const {};
    List<ChartPoint> series(String key) => ((data[key] as List<dynamic>?) ?? const [])
        .map((e) => ChartPoint.fromJson(e as Map<String, dynamic>))
        .toList();
    return PaymentStats(
      periods: {
        for (final entry in periods.entries) entry.key: PeriodTotal.fromJson(entry.value as Map<String, dynamic>),
      },
      daily: series('daily'),
      monthly: series('monthly'),
      filteredTotal: _toDouble(data['filtered_total']),
      bySource: ((data['by_source'] as List<dynamic>?) ?? const [])
          .map((e) => SourceTotal.fromJson(e as Map<String, dynamic>))
          .toList(),
      currency: data['currency'] as String?,
    );
  }

  /// Keyed 'today' / 'week' / 'month' / 'year' (the week starts Saturday,
  /// Baghdad time). These ignore the list's filters.
  final Map<String, PeriodTotal> periods;

  /// Last 30 days and this year's 12 months, zero-filled, oldest first.
  final List<ChartPoint> daily;
  final List<ChartPoint> monthly;

  /// Total and per-source split of what the filters match.
  final double filteredTotal;
  final List<SourceTotal> bySource;
  final String? currency;
}

class PeriodTotal {
  const PeriodTotal({required this.total, required this.count});

  factory PeriodTotal.fromJson(Map<String, dynamic> json) =>
      PeriodTotal(total: _toDouble(json['total']), count: (json['count'] as num?)?.toInt() ?? 0);

  final double total;
  final int count;
}

class ChartPoint {
  const ChartPoint({required this.label, required this.total});

  factory ChartPoint.fromJson(Map<String, dynamic> json) =>
      ChartPoint(label: '${json['label'] ?? ''}', total: _toDouble(json['total']));

  final String label;
  final double total;
}

class SourceTotal {
  const SourceTotal({required this.source, required this.total, required this.count});

  factory SourceTotal.fromJson(Map<String, dynamic> json) => SourceTotal(
        source: json['source'] as String? ?? '',
        total: _toDouble(json['total']),
        count: (json['count'] as num?)?.toInt() ?? 0,
      );

  /// 'registration' or 'lab'.
  final String source;
  final double total;
  final int count;
}

double _toDouble(Object? value) => double.tryParse('${value ?? 0}') ?? 0;
