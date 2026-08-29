/// One field from `App\Support\*Form::sections()`, exactly as
/// `SectionedForm.vue` already consumes it — kept close to the raw JSON
/// shape (`Map<String, dynamic>` typed accessors) rather than a fully
/// closed model, since new field types are added on the PHP side
/// incrementally (this session alone added `checkboxes`,
/// `teeth_squares_grid`, `quadrant_repeater`, and Oral Medicine's six
/// composite types) and a field the mobile renderer doesn't support yet
/// should still round-trip its raw attributes rather than needing a model
/// change first.
class CaseSheetField {
  const CaseSheetField(this.raw);

  factory CaseSheetField.fromJson(Map<String, dynamic> json) => CaseSheetField(json);

  final Map<String, dynamic> raw;

  String get key => raw['key'] as String? ?? '';
  String? get group => raw['group'] as String?;
  String get label => raw['label'] as String? ?? key;
  String get type => raw['type'] as String? ?? 'text';
  bool get required => raw['required'] as bool? ?? false;
  String? get width => raw['width'] as String?;
  String? get help => raw['help'] as String?;
  String? get itemLabel => raw['itemLabel'] as String?;
  String? get infoLabel => raw['infoLabel'] as String?;

  /// The key this field is actually stored under in a flat form-values
  /// map — namespaced for grouped fields so two groups can share a subkey
  /// name without colliding, mirroring `SectionedForm.vue`'s `formKey()`.
  String get formKey => group != null ? '${group}__$key' : key;

  List<CaseSheetFieldOption> get options => (raw['options'] as List<dynamic>? ?? [])
      .whereType<Map<String, dynamic>>()
      .map(CaseSheetFieldOption.fromJson)
      .toList();

  /// Whether this field is one this session's `DynamicSectionForm` can
  /// actually render as an editable control yet.
  bool get isSupported => const {
        'text', 'textarea', 'number', 'decimal', 'date', 'time',
        'select', 'radio', 'checkboxes', 'boolean', 'teeth', 'dental_chart',
        'endodontics', 'extraoral_exam', 'history_complaint', 'pmh_checklist',
        'surgical_history', 'family_history', 'social_history',
        'teeth_squares_grid', 'quadrant_repeater',
      }.contains(type);
}

class CaseSheetFieldOption {
  const CaseSheetFieldOption({required this.value, required this.label});

  factory CaseSheetFieldOption.fromJson(Map<String, dynamic> json) => CaseSheetFieldOption(
        value: json['value'].toString(),
        label: json['label'] as String? ?? json['value'].toString(),
      );

  final String value;
  final String label;
}
