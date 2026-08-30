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
/// data visibility is confined to. A `null` list on any dimension means
/// unrestricted (sees everything) — `ScopeHelper`'s own "zero rows"
/// convention, not "nothing selected". Independent of the module/action
/// grants above: this restricts what data the account can see at all,
/// not any single create/edit/delete action.
class PermissionScope {
  const PermissionScope({this.departmentIds, this.stageIds, this.educationTypeIds, this.academicSessionIds});

  factory PermissionScope.fromJson(Map<String, dynamic> json) => PermissionScope(
        departmentIds: _ids(json['departments']),
        stageIds: _ids(json['stages']),
        educationTypeIds: _ids(json['education_types']),
        academicSessionIds: _ids(json['academic_sessions']),
      );

  static List<int>? _ids(dynamic raw) => raw == null ? null : (raw as List<dynamic>).map((e) => e as int).toList();

  final List<int>? departmentIds;
  final List<int>? stageIds;
  final List<int>? educationTypeIds;
  final List<int>? academicSessionIds;
}

/// Mutable, always-non-null counterpart to [PermissionScope] for the edit
/// screen's live form state. An empty list on any dimension means
/// unrestricted — same convention as [PermissionScope.fromJson], just
/// normalized to `[]` instead of `null` since UI checkboxes need a concrete
/// list to check membership against either way.
class PermissionScopeSelection {
  PermissionScopeSelection({
    List<int>? departmentIds,
    List<int>? stageIds,
    List<int>? educationTypeIds,
    List<int>? academicSessionIds,
  })  : departmentIds = List.of(departmentIds ?? const []),
        stageIds = List.of(stageIds ?? const []),
        educationTypeIds = List.of(educationTypeIds ?? const []),
        academicSessionIds = List.of(academicSessionIds ?? const []);

  factory PermissionScopeSelection.fromScope(PermissionScope scope) => PermissionScopeSelection(
        departmentIds: scope.departmentIds,
        stageIds: scope.stageIds,
        educationTypeIds: scope.educationTypeIds,
        academicSessionIds: scope.academicSessionIds,
      );

  final List<int> departmentIds;
  final List<int> stageIds;
  final List<int> educationTypeIds;
  final List<int> academicSessionIds;

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
