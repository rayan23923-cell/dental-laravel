/// Laravel's standard `->paginate()->response()` envelope
/// (`{data: [...], meta: {current_page, last_page, ...}}`) — shared by
/// every paginated list endpoint in this API, not just task instances.
class Paginated<T> {
  Paginated({required this.items, required this.currentPage, required this.lastPage, int? total})
      : total = total ?? items.length;

  factory Paginated.fromJson(Map<String, dynamic> json, T Function(Map<String, dynamic>) fromJson) {
    final meta = json['meta'] as Map<String, dynamic>?;
    return Paginated(
      items: (json['data'] as List).map((e) => fromJson(e as Map<String, dynamic>)).toList(),
      currentPage: meta?['current_page'] as int? ?? 1,
      lastPage: meta?['last_page'] as int? ?? 1,
      total: (meta?['total'] as num?)?.toInt(),
    );
  }

  final List<T> items;
  final int currentPage;
  final int lastPage;

  /// Matching rows across every page (`meta.total`); the page's own count
  /// when the response has none.
  final int total;

  bool get hasMore => currentPage < lastPage;
}
