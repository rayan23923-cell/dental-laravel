import 'register_day.dart';

/// Mirrors `App\Models\Service` (table `register_services`) /
/// `Api\ServiceController`. `days` is only populated when the API nests it
/// (`GET /services` — the settings screen's service list).
class Service {
  const Service({required this.id, required this.name, this.days = const []});

  factory Service.fromJson(Map<String, dynamic> json) => Service(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        days: (json['days'] as List<dynamic>?)
                ?.map((e) => RegisterDay.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  final int id;
  final String name;
  final List<RegisterDay> days;
}
