/// Mirrors `Api\PaymentController::stats()` — the web payments page's
/// income overview (2026-10-17): today / week / month / year, the daily
/// and monthly series behind its charts, and the current filters' total by
/// source.
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
    final periods = data['periods'] as Map<String, dynamic>;
    List<PaymentSeriesPoint> series(String key) => (data[key] as List<dynamic>)
        .map((e) => PaymentSeriesPoint.fromJson(e as Map<String, dynamic>))
        .toList();
    return PaymentStats(
      periods: {
        for (final key in const ['today', 'week', 'month', 'year'])
          if (periods[key] != null) key: PaymentPeriod.fromJson(periods[key] as Map<String, dynamic>),
      },
      daily: series('daily'),
      monthly: series('monthly'),
      filteredTotal: _toDouble(data['filtered_total']),
      bySource: (data['by_source'] as List<dynamic>)
          .map((e) => PaymentSourceTotal.fromJson(e as Map<String, dynamic>))
          .toList(),
      currency: data['currency'] as String?,
    );
  }

  /// 'today', 'week', 'month', 'year'.
  final Map<String, PaymentPeriod> periods;
  final List<PaymentSeriesPoint> daily;
  final List<PaymentSeriesPoint> monthly;
  final double filteredTotal;
  final List<PaymentSourceTotal> bySource;
  final String? currency;
}

class PaymentPeriod {
  const PaymentPeriod({required this.total, required this.count});

  factory PaymentPeriod.fromJson(Map<String, dynamic> json) =>
      PaymentPeriod(total: _toDouble(json['total']), count: (json['count'] as num?)?.toInt() ?? 0);

  final double total;
  final int count;
}

class PaymentSeriesPoint {
  const PaymentSeriesPoint({required this.label, required this.total});

  factory PaymentSeriesPoint.fromJson(Map<String, dynamic> json) =>
      PaymentSeriesPoint(label: '${json['label'] ?? ''}', total: _toDouble(json['total']));

  final String label;
  final double total;
}

class PaymentSourceTotal {
  const PaymentSourceTotal({required this.source, required this.total, required this.count});

  factory PaymentSourceTotal.fromJson(Map<String, dynamic> json) => PaymentSourceTotal(
        source: json['source'] as String,
        total: _toDouble(json['total']),
        count: (json['count'] as num?)?.toInt() ?? 0,
      );

  /// 'registration' or 'lab'.
  final String source;
  final double total;
  final int count;
}

double _toDouble(Object? value) => double.tryParse('${value ?? 0}') ?? 0;
