import 'service.dart';

/// Mirrors `App\Models\RegisterDay` / `Api\RegisterDayController`.
/// `services`/`taskIds` are only populated when the API nests them (`GET
/// /register-days` — used by both the day-first cascading picker and the
/// settings screen). `taskIds` (not full `Task` objects — the
/// registration form already has the full task list from
/// `tasksLookupProvider`, this just says which of them this day allows;
/// empty means "no rule configured for this day", not "no tasks
/// allowed" — see `RegisterDay::tasks()`'s docblock).
class RegisterDay {
  const RegisterDay({
    required this.id,
    required this.name,
    required this.sortOrder,
    this.services = const [],
    this.taskIds = const [],
  });

  factory RegisterDay.fromJson(Map<String, dynamic> json) => RegisterDay(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        sortOrder: json['sort_order'] as int? ?? 0,
        services: (json['services'] as List<dynamic>?)
                ?.map((e) => Service.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        taskIds: (json['tasks'] as List<dynamic>?)
                ?.map((e) => (e as Map<String, dynamic>)['id'] as int)
                .toList() ??
            const [],
      );

  final int id;
  final String name;
  final int sortOrder;
  final List<Service> services;
  final List<int> taskIds;
}
