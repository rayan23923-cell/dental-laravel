/// Laravel's standard `->paginate()->response()` envelope
/// (`{data: [...], meta: {current_page, last_page, ...}}`) — shared by
/// every paginated list endpoint in this API, not just task instances.
class Paginated<T> {
  const Paginated({required this.items, required this.currentPage, required this.lastPage});

  factory Paginated.fromJson(Map<String, dynamic> json, T Function(Map<String, dynamic>) fromJson) {
    final meta = json['meta'] as Map<String, dynamic>?;
    return Paginated(
      items: (json['data'] as List).map((e) => fromJson(e as Map<String, dynamic>)).toList(),
      currentPage: meta?['current_page'] as int? ?? 1,
      lastPage: meta?['last_page'] as int? ?? 1,
    );
  }

  final List<T> items;
  final int currentPage;
  final int lastPage;

  bool get hasMore => currentPage < lastPage;
}
