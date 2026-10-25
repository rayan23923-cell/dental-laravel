import 'register_day.dart';

/// Mirrors `App\Models\Service` (table `register_services`) /
/// `Api\ServiceController`. `days` is only populated when the API nests it
/// (`GET /services` — the settings screen's service list).
class Service {
  const Service({
    required this.id,
    required this.name,
    this.price,
    this.studentDiscountPercent = 50,
    this.days = const [],
  });

  factory Service.fromJson(Map<String, dynamic> json) => Service(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        // A decimal column, so the API may send it as a string ("15000.00").
        price: json['price'] == null ? null : double.tryParse(json['price'].toString()),
        studentDiscountPercent: double.tryParse(json['student_discount_percent']?.toString() ?? '') ?? 50,
        days: (json['days'] as List<dynamic>?)
                ?.map((e) => RegisterDay.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  final int id;
  final String name;

  /// The service's price (2026-10-12) — pre-fills the registration form's
  /// amount paid. Null when not set.
  final double? price;

  /// Taken off [price] for a patient registered as eligible for the
  /// student discount (2026-10-25); 50 by default.
  final double studentDiscountPercent;

  /// What a patient pays: [price], less the student discount when
  /// [eligible]. Same rounding as `App\Support\StudentDiscount::apply()`.
  double? priceFor({required bool eligible}) {
    final p = price;
    if (p == null || !eligible) return p;
    final percent = studentDiscountPercent.clamp(0, 100);
    return (p * (100 - percent)).round() / 100;
  }
  final List<RegisterDay> days;
}
