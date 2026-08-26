/// The three simple, near-identical lookup tables `Api\LookupController`
/// now manages (2026-08-21) — one model/repository/pair of screens for
/// all three rather than three near-duplicate sets, since the only real
/// difference between them is which optional parent FK each carries.
enum TaxonomyKind { educationType, stage, department }

extension TaxonomyKindX on TaxonomyKind {
  String get endpoint => switch (this) {
        TaxonomyKind.educationType => 'education-types',
        TaxonomyKind.stage => 'stages',
        TaxonomyKind.department => 'departments',
      };

  String get title => switch (this) {
        TaxonomyKind.educationType => 'أنواع التعليم',
        TaxonomyKind.stage => 'المراحل',
        TaxonomyKind.department => 'الأقسام',
      };

  String get singularTitle => switch (this) {
        TaxonomyKind.educationType => 'نوع التعليم',
        TaxonomyKind.stage => 'المرحلة',
        TaxonomyKind.department => 'القسم',
      };

  bool get hasEducationType => this != TaxonomyKind.educationType;
  bool get hasStage => this == TaxonomyKind.department;
}

/// Mirrors the raw model JSON `Api\LookupController`'s write endpoints
/// return (`response()->json($model)` — no `{data: ...}` envelope and no
/// nested parent objects, matching its existing read endpoints' shape,
/// unlike the rest of this API's Resource-wrapped conventions).
class TaxonomyItem {
  const TaxonomyItem({required this.id, required this.name, required this.educationTypeId, required this.stageId});

  factory TaxonomyItem.fromJson(Map<String, dynamic> json) => TaxonomyItem(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        educationTypeId: json['education_type_id'] as int?,
        stageId: json['stage_id'] as int?,
      );

  final int id;
  final String name;
  final int? educationTypeId;
  final int? stageId;
}
