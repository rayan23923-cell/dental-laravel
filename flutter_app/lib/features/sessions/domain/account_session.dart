/// Mirrors `App\Http\Resources\SessionResource` — one Sanctum personal
/// access token, i.e. one device/app install this account is logged in
/// from. See `Api\SessionController`'s own docblock for why the web app's
/// own session-cookie login is never one of these rows.
class AccountSession {
  const AccountSession({
    required this.id,
    required this.deviceName,
    required this.deviceType,
    required this.ipAddress,
    required this.location,
    required this.createdAt,
    required this.lastUsedAt,
    required this.isCurrent,
  });

  factory AccountSession.fromJson(Map<String, dynamic> json) => AccountSession(
        id: json['id'] as int,
        deviceName: json['device_name'] as String? ?? '',
        deviceType: json['device_type'] as String? ?? 'other',
        ipAddress: json['ip_address'] as String?,
        location: json['location'] as String?,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
        lastUsedAt: json['last_used_at'] != null ? DateTime.tryParse(json['last_used_at'] as String) : null,
        isCurrent: json['is_current'] as bool? ?? false,
      );

  final int id;
  final String deviceName;
  final String deviceType;
  final String? ipAddress;
  final String? location;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final bool isCurrent;
}
