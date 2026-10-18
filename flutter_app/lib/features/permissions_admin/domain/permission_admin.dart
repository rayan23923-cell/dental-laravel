import '../../../core/data/lookup_repository.dart';

class PermissionUser {
  const PermissionUser({required this.id, required this.fullName, required this.username, required this.role});

  factory PermissionUser.fromJson(Map<String, dynamic> json) => PermissionUser(
        id: json['id'] as int,
        fullName: json['full_name'] as String,
        username: json['username'] as String,
        role: json['role'] as String,
      );

  final int id;
  final String fullName;
  final String username;
  final String role;
}

class PermissionAction {
  const PermissionAction({required this.key, required this.label});

  factory PermissionAction.fromJson(Map<String, dynamic> json) =>
      PermissionAction(key: json['key'] as String, label: json['label'] as String);

  final String key;
  final String label;
}

class PermissionModule {
  const PermissionModule({required this.key, required this.name, required this.permissions});

  factory PermissionModule.fromJson(Map<String, dynamic> json) => PermissionModule(
        key: json['key'] as String,
        name: json['name'] as String,
        permissions: (json['permissions'] as List<dynamic>)
            .map((e) => PermissionAction.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final String key;
  final String name;
  final List<PermissionAction> permissions;
}

/// The option lists for `PermissionScope`'s four dimensions — mirrors
/// `Api\UserPermissionController::show()`'s `scope_options` key, itself a
/// straight port of the web `Permissions/Edit` page's `scopeOptions` prop.
class PermissionScopeOptions {
  const PermissionScopeOptions({
    required this.departments,
    required this.stages,
    required this.educationTypes,
    required this.academicSessions,
  });

  factory PermissionScopeOptions.fromJson(Map<String, dynamic> json) => PermissionScopeOptions(
        departments: _items(json['departments']),
        stages: _items(json['stages']),
        educationTypes: _items(json['education_types']),
        academicSessions: _items(json['academic_sessions']),
      );

  static List<LookupItem> _items(dynamic raw) =>
      (raw as List<dynamic>? ?? []).map((e) => LookupItem.fromJson(e as Map<String, dynamic>)).toList();

  final List<LookupItem> departments;
  final List<LookupItem> stages;
  final List<LookupItem> educationTypes;
  final List<LookupItem> academicSessions;
}

/// "نطاق الوصول" (Access Scope, `App\Services\ScopeHelper`) — which
/// departments/stages/education types/academic sessions this account's
/// data visibility is confined to. A `null` list means nothing picked. On
/// the top levels (education types, academic sessions) that means nothing
/// is visible unless the `all*` flag ("الكل") is on (2026-10-18); stages and
/// departments with nothing picked follow the level above. Independent of
/// the module/action grants above: this restricts what data the account
/// can see at all, not any single create/edit/delete action.
class PermissionScope {
  const PermissionScope({
    this.departmentIds,
    this.stageIds,
    this.educationTypeIds,
    this.academicSessionIds,
    this.allEducationTypes = false,
    this.allAcademicSessions = false,
  });

  // A server older than the flags sends none; there nothing picked meant
  // everything.
  factory PermissionScope.fromJson(Map<String, dynamic> json) => PermissionScope(
        departmentIds: _ids(json['departments']),
        stageIds: _ids(json['stages']),
        educationTypeIds: _ids(json['education_types']),
        academicSessionIds: _ids(json['academic_sessions']),
        allEducationTypes: json['all_education_types'] as bool? ?? json['education_types'] == null,
        allAcademicSessions: json['all_academic_sessions'] as bool? ?? json['academic_sessions'] == null,
      );

  static List<int>? _ids(dynamic raw) => raw == null ? null : (raw as List<dynamic>).map((e) => e as int).toList();

  final List<int>? departmentIds;
  final List<int>? stageIds;
  final List<int>? educationTypeIds;
  final List<int>? academicSessionIds;
  final bool allEducationTypes;
  final bool allAcademicSessions;
}

/// Mutable, always-non-null counterpart to [PermissionScope] for the edit
/// screen's live form state. An empty list means nothing picked — same
/// convention as [PermissionScope.fromJson], just normalized to `[]`
/// instead of `null` since UI checkboxes need a concrete list to check
/// membership against either way.
class PermissionScopeSelection {
  PermissionScopeSelection({
    List<int>? departmentIds,
    List<int>? stageIds,
    List<int>? educationTypeIds,
    List<int>? academicSessionIds,
    this.allEducationTypes = false,
    this.allAcademicSessions = false,
  })  : departmentIds = List.of(departmentIds ?? const []),
        stageIds = List.of(stageIds ?? const []),
        educationTypeIds = List.of(educationTypeIds ?? const []),
        academicSessionIds = List.of(academicSessionIds ?? const []);

  factory PermissionScopeSelection.fromScope(PermissionScope scope) => PermissionScopeSelection(
        departmentIds: scope.departmentIds,
        stageIds: scope.stageIds,
        educationTypeIds: scope.educationTypeIds,
        academicSessionIds: scope.academicSessionIds,
        allEducationTypes: scope.allEducationTypes,
        allAcademicSessions: scope.allAcademicSessions,
      );

  final List<int> departmentIds;
  final List<int> stageIds;
  final List<int> educationTypeIds;
  final List<int> academicSessionIds;

  /// "الكل" on the top levels; nothing picked without it means nothing.
  bool allEducationTypes;
  bool allAcademicSessions;

  bool? allFor(String dimension) => switch (dimension) {
        'education_types' => allEducationTypes,
        'academic_sessions' => allAcademicSessions,
        _ => null,
      };

  void setAll(String dimension, bool on) {
    if (dimension == 'education_types') allEducationTypes = on;
    if (dimension == 'academic_sessions') allAcademicSessions = on;
  }

  Map<String, dynamic> toJson() => {
        'departments': departmentIds,
        'stages': stageIds,
        'education_types': educationTypeIds,
        'academic_sessions': academicSessionIds,
        'all_education_types': allEducationTypes,
        'all_academic_sessions': allAcademicSessions,
      };

  List<int> listFor(String dimension) {
    switch (dimension) {
      case 'departments':
        return departmentIds;
      case 'stages':
        return stageIds;
      case 'education_types':
        return educationTypeIds;
      case 'academic_sessions':
        return academicSessionIds;
      default:
        throw ArgumentError('Unknown scope dimension: $dimension');
    }
  }
}

/// `Api\UserPermissionController::show()`'s response shape.
class PermissionsDetail {
  const PermissionsDetail({
    required this.modules,
    required this.granted,
    required this.scopeOptions,
    required this.scope,
  });

  factory PermissionsDetail.fromJson(Map<String, dynamic> json) => PermissionsDetail(
        modules:
            (json['modules'] as List<dynamic>).map((e) => PermissionModule.fromJson(e as Map<String, dynamic>)).toList(),
        granted: (json['granted'] as List<dynamic>).map((e) => e as String).toSet(),
        scopeOptions: PermissionScopeOptions.fromJson(json['scope_options'] as Map<String, dynamic>? ?? const {}),
        scope: PermissionScope.fromJson(json['scope'] as Map<String, dynamic>? ?? const {}),
      );

  final List<PermissionModule> modules;
  final Set<String> granted;
  final PermissionScopeOptions scopeOptions;
  final PermissionScope scope;
}
