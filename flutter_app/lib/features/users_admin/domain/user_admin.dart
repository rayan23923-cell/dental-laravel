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
