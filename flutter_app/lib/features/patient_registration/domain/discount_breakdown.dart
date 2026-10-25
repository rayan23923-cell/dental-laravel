/// A student/employee discount as separate amounts (2026-10-25, by
/// request: "1000, خصم 50%, 500"), the server's `discount` /
/// `lab_discount` object. [percent] and [full] are null when nothing was
/// taken off.
class DiscountBreakdown {
  const DiscountBreakdown({required this.who, this.percent, this.full, required this.paid});

  final String who;
  final String? percent;
  final double? full;
  final double paid;

  bool get isDiscounted => percent != null && full != null;

  /// Null for a patient who is not eligible, or from an older server.
  static DiscountBreakdown? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return DiscountBreakdown(
      who: json['who'] as String? ?? '',
      percent: json['percent']?.toString(),
      full: json['full'] == null ? null : double.tryParse(json['full'].toString()),
      paid: double.tryParse('${json['paid'] ?? 0}') ?? 0,
    );
  }
}

/// A slip's amount rows, as the web `print/partials/amount-rows`: the
/// amount, the discount and the amount after it when discounted; otherwise
/// one [label] row with [amountText], then [fallbackLine] (an older
/// server's single discount line) when given.
List<(String, String)> discountAmountRows(
  DiscountBreakdown? discount, {
  required String label,
  required String amountText,
  required String Function(double) money,
  String fullLabel = 'المبلغ',
  String? fallbackLine,
}) {
  if (discount != null && discount.isDiscounted) {
    return [
      (fullLabel, money(discount.full!)),
      ('التخفيض', '${discount.percent}% — ${discount.who}'),
      ('المبلغ بعد التخفيض', money(discount.paid)),
    ];
  }
  return [
    (label, amountText),
    if (discount != null && discount.who.isNotEmpty)
      ('التخفيض', discount.who)
    else if (fallbackLine != null)
      ('التخفيض', fallbackLine),
  ];
}
