/// One entry in `dental_charts.tooth_data` — mirrors
/// `Components/ToothOdontogram.vue`'s data shape exactly (verified against
/// real imported rows there, not guessed): only touched teeth appear in
/// the list at all, matching the original.
class ToothEntry {
  const ToothEntry({
    required this.number,
    required this.position,
    required this.notes,
    required this.status,
    required this.toothStatus,
    required this.polygons,
  });

  factory ToothEntry.fromJson(Map<String, dynamic> json) => ToothEntry(
        number: json['number'].toString(),
        position: json['position'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        status: json['status'] as String? ?? 'planned',
        toothStatus: json['toothStatus'] as String? ?? 'present',
        polygons: _decodePolygons(json['polygons']),
      );

  /// PHP's `json_encode` renders an empty associative array as `[]`, not
  /// `{}` — an untouched tooth's `polygons` arrives as a JSON array, not
  /// an object, and must be treated as empty rather than crashing the cast.
  static Map<String, ToothSurface> _decodePolygons(dynamic raw) {
    if (raw is! Map) return {};
    return raw.map(
      (key, value) => MapEntry(key.toString(), ToothSurface.fromJson(Map<String, dynamic>.from(value as Map))),
    );
  }

  final String number;
  final String position;
  final String notes;
  final String status;
  final String toothStatus;
  final Map<String, ToothSurface> polygons;

  Map<String, dynamic> toJson() => {
        'number': number,
        'position': position,
        'notes': notes,
        'status': status,
        'toothStatus': toothStatus,
        'polygons': polygons.map((key, value) => MapEntry(key, value.toJson())),
      };

  ToothEntry copyWith({
    String? notes,
    String? status,
    String? toothStatus,
    Map<String, ToothSurface>? polygons,
  }) =>
      ToothEntry(
        number: number,
        position: position,
        notes: notes ?? this.notes,
        status: status ?? this.status,
        toothStatus: toothStatus ?? this.toothStatus,
        polygons: polygons ?? this.polygons,
      );

  static String positionOf(int number) {
    final quadrant = number ~/ 10;
    return const {1: 'upper_right', 2: 'upper_left', 3: 'lower_left', 4: 'lower_right'}[quadrant] ?? 'upper_right';
  }
}

class ToothSurface {
  const ToothSurface({required this.name, required this.status});

  factory ToothSurface.fromJson(Map<String, dynamic> json) => ToothSurface(
        name: json['name'] as String? ?? '',
        status: json['status'] as String? ?? '',
      );

  final String name;
  final String status;

  Map<String, dynamic> toJson() => {'name': name, 'status': status};
}
