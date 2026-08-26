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

/// `Api\UserPermissionController::show()`'s response shape. Scope
/// restrictions (departments/stages/education types/academic sessions —
/// `App\Services\ScopeHelper`) are a separate feature the API doesn't
/// expose here at all; this only carries module/action grants.
class PermissionsDetail {
  const PermissionsDetail({required this.modules, required this.granted});

  factory PermissionsDetail.fromJson(Map<String, dynamic> json) => PermissionsDetail(
        modules:
            (json['modules'] as List<dynamic>).map((e) => PermissionModule.fromJson(e as Map<String, dynamic>)).toList(),
        granted: (json['granted'] as List<dynamic>).map((e) => e as String).toSet(),
      );

  final List<PermissionModule> modules;
  final Set<String> granted;
}
