import 'account_type.dart';

/// Either shape `POST /login`, `POST /doctor/login` or `GET /me` can return.
sealed class AuthAccount {
  const AuthAccount();

  AccountType get accountType;
  String get displayName;
  // null = "follow system/device language" — see LocaleController's own
  // doc comment (2026-09-04, by request — same feature as the web's
  // ResolveLocale, ported here).
  String? get locale;
}

/// Mirrors `App\Http\Resources\UserResource`.
final class StaffAccount extends AuthAccount {
  const StaffAccount({
    required this.id,
    required this.fullName,
    required this.username,
    required this.email,
    required this.phone,
    required this.role,
    required this.status,
    required this.profileImage,
    required this.profileImageUrl,
    required this.locale,
    this.permissions,
  });

  factory StaffAccount.fromJson(Map<String, dynamic> json) => StaffAccount(
        id: json['id'] as int,
        fullName: json['full_name'] as String? ?? '',
        username: json['username'] as String? ?? '',
        email: json['email'] as String? ?? '',
        phone: json['phone'] as String?,
        role: json['role'] as String? ?? '',
        status: json['status'] as String? ?? '',
        profileImage: json['profile_image'] as String?,
        // Added alongside UserResource's new `profile_image_url` key
        // (2026-08-21) — was previously only the raw storage path
        // (`profileImage`), unlike DoctorAccount which already had a
        // ready-to-use URL.
        profileImageUrl: json['profile_image_url'] as String?,
        locale: json['locale'] as String?,
        permissions: (json['permissions'] as List<dynamic>?)?.map((e) => e as String).toSet(),
      );

  final int id;
  final String fullName;
  final String username;
  final String email;
  final String? phone;
  final String role;
  final String status;
  final String? profileImage;
  final String? profileImageUrl;
  @override
  final String? locale;

  /// Granted "module.permission" pairs (2026-10-18); null from a server
  /// older than that, which the app then treats as granting everything.
  final Set<String>? permissions;

  bool can(String module, String permission) =>
      role == 'super_admin' || permissions == null || permissions!.contains('$module.$permission');

  @override
  AccountType get accountType => AccountType.staff;

  @override
  String get displayName => fullName;
}

/// Mirrors `App\Http\Resources\DoctorResource`.
final class DoctorAccount extends AuthAccount {
  const DoctorAccount({
    required this.id,
    required this.name,
    required this.username,
    required this.email,
    required this.phone,
    required this.profileImageUrl,
    required this.educationTypeId,
    required this.stageId,
    required this.educationTypeName,
    required this.stageName,
    required this.academicSessionId,
    required this.academicSessionName,
    required this.locale,
  });

  factory DoctorAccount.fromJson(Map<String, dynamic> json) {
    final educationType = json['education_type'] as Map<String, dynamic>?;
    final stage = json['stage'] as Map<String, dynamic>?;
    final academicSession = json['academic_session'] as Map<String, dynamic>?;

    return DoctorAccount(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      username: json['username'] as String? ?? '',
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      profileImageUrl: json['profile_image_url'] as String?,
      educationTypeId: json['education_type_id'] as int?,
      stageId: json['stage_id'] as int?,
      educationTypeName: educationType?['name'] as String?,
      stageName: stage?['name'] as String?,
      academicSessionId: json['academic_session_id'] as int?,
      academicSessionName: academicSession?['name'] as String?,
      locale: json['locale'] as String?,
    );
  }

  final int id;
  final String name;
  final String username;
  final String? email;
  final String? phone;
  final String? profileImageUrl;
  final int? educationTypeId;
  final int? stageId;
  final String? educationTypeName;
  final String? stageName;
  final int? academicSessionId;
  final String? academicSessionName;
  @override
  final String? locale;

  @override
  AccountType get accountType => AccountType.doctor;

  @override
  String get displayName => name;
}
