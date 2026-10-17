import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final departmentRolesRepositoryProvider = Provider<DepartmentRolesRepository>((ref) {
  return DepartmentRolesRepository(ref.watch(apiClientProvider));
});

/// One row of `Api\DepartmentRoleAssignmentController`.
class DepartmentRoleAssignment {
  const DepartmentRoleAssignment({
    required this.id,
    required this.userName,
    required this.stageName,
    required this.departmentName,
    required this.roleType,
    required this.active,
    this.notes,
  });

  factory DepartmentRoleAssignment.fromJson(Map<String, dynamic> json) => DepartmentRoleAssignment(
        id: json['id'] as int,
        userName: json['user_name'] as String? ?? '-',
        stageName: json['stage_name'] as String?,
        departmentName: json['department_name'] as String?,
        roleType: json['role_type'] as String? ?? '',
        active: json['status'] == 'active',
        notes: json['notes'] as String?,
      );

  final int id;
  final String userName;
  final String? stageName;
  final String? departmentName;

  /// `senior` (كبير القسم) or `hr` (الموارد البشرية).
  final String roleType;
  final bool active;
  final String? notes;
}

class DepartmentRoleOption {
  const DepartmentRoleOption({required this.id, required this.name, this.stageId});
  final int id;
  final String name;
  final int? stageId;
}

class DepartmentRolesPage {
  const DepartmentRolesPage({required this.assignments, required this.users, required this.departments, required this.stages});
  final List<DepartmentRoleAssignment> assignments;
  final List<DepartmentRoleOption> users;
  final List<DepartmentRoleOption> departments;
  final List<DepartmentRoleOption> stages;
}

/// `/department-roles` (2026-10-17) — the web's `DepartmentRoles/Index`:
/// list, assign, switch off/on, remove.
class DepartmentRolesRepository {
  DepartmentRolesRepository(this._client);
  final ApiClient _client;

  Future<DepartmentRolesPage> fetch() async {
    final data = (await _client.getJson('/department-roles') as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    List<DepartmentRoleOption> options(String key, String nameKey) => [
          for (final e in data[key] as List<dynamic>)
            DepartmentRoleOption(
              id: (e as Map<String, dynamic>)['id'] as int,
              name: e[nameKey] as String? ?? '',
              stageId: e['stage_id'] as int?,
            ),
        ];
    return DepartmentRolesPage(
      assignments: [
        for (final e in data['assignments'] as List<dynamic>) DepartmentRoleAssignment.fromJson(e as Map<String, dynamic>),
      ],
      users: options('users', 'full_name'),
      departments: options('departments', 'name'),
      stages: options('stages', 'name'),
    );
  }

  Future<void> assign({
    required int userId,
    required int stageId,
    required int departmentId,
    required String roleType,
    String? notes,
  }) =>
      _client.postJson('/department-roles', body: {
        'user_id': userId,
        'stage_id': stageId,
        'department_id': departmentId,
        'role_type': roleType,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      });

  Future<void> toggle(int id) => _client.putJson('/department-roles/$id/toggle');

  Future<void> remove(int id) => _client.deleteJson('/department-roles/$id');
}
