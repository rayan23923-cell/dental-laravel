import '../../permissions_admin/domain/permission_admin.dart';

/// Mirrors `App\Http\Resources\UserResource`, the shape
/// `Api\UserController::store()` returns.
class UserAdmin {
  const UserAdmin({
    required this.id,
    required this.fullName,
    required this.username,
    required this.email,
    required this.phone,
    required this.role,
    required this.status,
  });

  factory UserAdmin.fromJson(Map<String, dynamic> json) => UserAdmin(
        id: json['id'] as int,
        fullName: json['full_name'] as String? ?? '',
        username: json['username'] as String? ?? '',
        email: json['email'] as String? ?? '',
        phone: json['phone'] as String?,
        role: json['role'] as String? ?? '',
        status: json['status'] as String? ?? '',
      );

  final int id;
  final String fullName;
  final String username;
  final String email;
  final String? phone;
  final String role;
  final String status;
}

/// A row of `GET /users` / `GET /users/{id}` — users management
/// (2026-10-21, by request). `isSelf` and `roles` come with the single user.
class ManagedUser {
  const ManagedUser({
    required this.id,
    required this.fullName,
    required this.username,
    required this.email,
    required this.phone,
    required this.role,
    required this.status,
    required this.notes,
    required this.lastLogin,
    this.isSelf = false,
    this.roles = const [],
  });

  factory ManagedUser.fromJson(Map<String, dynamic> json) => ManagedUser(
        id: json['id'] as int,
        fullName: json['full_name'] as String? ?? '',
        username: json['username'] as String? ?? '',
        email: json['email'] as String? ?? '',
        phone: json['phone'] as String?,
        role: json['role'] as String? ?? '',
        status: json['status'] as String? ?? 'active',
        notes: json['notes'] as String?,
        lastLogin: json['last_login'] as String?,
        isSelf: json['is_self'] as bool? ?? false,
        roles: (json['roles'] as List<dynamic>? ?? const []).map((e) => e as String).toList(),
      );

  final int id;
  final String fullName;
  final String username;
  final String email;
  final String? phone;
  final String role;
  final String status;
  final String? notes;
  final String? lastLogin;
  final bool isSelf;

  /// The roles this account may be given (only `super_admin` for one).
  final List<String> roles;

  bool get active => status != 'inactive';
}

/// Mirrors `App\Models\User::ROLES` minus `super_admin` — see
/// `Api\UserController`'s docblock for why that one role can never be
/// assigned through this creation form.
const List<(String value, String label)> kAssignableUserRoles = [
  ('admin', 'مدير'),
  ('editor', 'محرر'),
  ('doctor', 'طبيب (حساب موظف)'),
  ('accountant', 'محاسب'),
  ('senior', 'مسؤول قسم'),
  ('hr', 'موارد بشرية'),
  ('reception', 'موظف التذاكر'),
  ('lab', 'مختبري'),
];

/// `GET /users/form-options`: what the add-user form needs to show the
/// permissions editor before the account exists (2026-10-14, by request).
class UserFormOptions {
  const UserFormOptions({required this.modules, required this.scopeOptions, required this.roleDefaults});

  factory UserFormOptions.fromJson(Map<String, dynamic> json) => UserFormOptions(
        modules:
            (json['modules'] as List<dynamic>).map((e) => PermissionModule.fromJson(e as Map<String, dynamic>)).toList(),
        scopeOptions: PermissionScopeOptions.fromJson(json['scope_options'] as Map<String, dynamic>? ?? const {}),
        roleDefaults: {
          for (final e in (json['role_defaults'] as Map<String, dynamic>? ?? const {}).entries)
            e.key: (e.value as List<dynamic>).map((x) => x as String).toList(),
        },
      );

  final List<PermissionModule> modules;
  final PermissionScopeOptions scopeOptions;

  /// Role → its ready-made "module.permission" grants.
  final Map<String, List<String>> roleDefaults;
}

String userRoleLabel(String role) => role == 'super_admin'
    ? 'مدير النظام'
    : kAssignableUserRoles.firstWhere((r) => r.$1 == role, orElse: () => (role, role)).$2;
