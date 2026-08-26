/// `icon`/`color`/`page_url` are deliberately not exposed here — the web
/// form (`CaseSheetTypes/Index.vue`) never surfaces them either; the
/// controller defaults `icon`/`color` on create and never touches
/// `page_url` at all. Mirrors that scope rather than adding fields the
/// web admin itself doesn't manage.
class CaseSheetTypeAdmin {
  const CaseSheetTypeAdmin({
    required this.id,
    required this.typeCode,
    required this.nameAr,
    required this.nameEn,
    required this.description,
    required this.isActive,
    required this.tasksCount,
  });

  factory CaseSheetTypeAdmin.fromJson(Map<String, dynamic> json) => CaseSheetTypeAdmin(
        id: json['id'] as int,
        typeCode: json['type_code'] as String,
        nameAr: json['name_ar'] as String,
        nameEn: json['name_en'] as String,
        description: json['description'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        tasksCount: json['tasks_count'] as int? ?? 0,
      );

  final int id;
  final String typeCode;
  final String nameAr;
  final String nameEn;
  final String? description;
  final bool isActive;
  final int tasksCount;
}
