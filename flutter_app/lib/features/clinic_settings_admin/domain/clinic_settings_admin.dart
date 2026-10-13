/// `Api\ClinicSettingController::show()`'s response shape. `theme` and the
/// SMTP `mail_*` fields are deliberately left out of this model — the
/// Api controller's own `update()` validation doesn't accept them either
/// (the Flutter app uses a fixed theme, not the web app's selectable one,
/// per `flutter_app/README.md` §7; SMTP credentials editable from a phone
/// admin screen is a scope cut, not an oversight — see that pass's
/// README entry).
class ClinicSettingsAdmin {
  const ClinicSettingsAdmin({
    required this.clinicName,
    required this.clinicDescription,
    required this.clinicAddress,
    required this.clinicPhone,
    required this.clinicEmail,
    required this.clinicWebsite,
    required this.clinicWorkingHours,
    required this.clinicCurrency,
    required this.clinicTimezone,
    required this.baseUrl,
    required this.universityName,
    required this.collegeName,
    required this.enableNotifications,
    required this.enableSms,
    required this.enableEmail,
    this.groupsEnabled = true,
    required this.logoUrl,
    required this.universityLogoUrl,
  });

  factory ClinicSettingsAdmin.fromJson(Map<String, dynamic> json) => ClinicSettingsAdmin(
        clinicName: json['clinic_name'] as String? ?? '',
        clinicDescription: json['clinic_description'] as String?,
        clinicAddress: json['clinic_address'] as String?,
        clinicPhone: json['clinic_phone'] as String?,
        clinicEmail: json['clinic_email'] as String?,
        clinicWebsite: json['clinic_website'] as String?,
        clinicWorkingHours: json['clinic_working_hours'] as String?,
        clinicCurrency: json['clinic_currency'] as String?,
        clinicTimezone: json['clinic_timezone'] as String?,
        baseUrl: json['base_url'] as String?,
        universityName: json['university_name'] as String?,
        collegeName: json['college_name'] as String?,
        enableNotifications: json['enable_notifications'] as bool? ?? false,
        enableSms: json['enable_sms'] as bool? ?? false,
        enableEmail: json['enable_email'] as bool? ?? false,
        groupsEnabled: json['groups_enabled'] as bool? ?? true,
        logoUrl: json['logo_url'] as String?,
        universityLogoUrl: json['university_logo_url'] as String?,
      );

  final String clinicName;
  final String? clinicDescription;
  final String? clinicAddress;
  final String? clinicPhone;
  final String? clinicEmail;
  final String? clinicWebsite;
  final String? clinicWorkingHours;
  final String? clinicCurrency;
  final String? clinicTimezone;
  final String? baseUrl;
  final String? universityName;
  final String? collegeName;
  final bool enableNotifications;
  final bool enableSms;
  final bool enableEmail;

  /// Groups on/off (2026-10-13) — see `ClinicSettings.groupsEnabled`.
  final bool groupsEnabled;
  final String? logoUrl;
  final String? universityLogoUrl;
}

/// The fixed timezone choices `ClinicSettings/Edit.vue` offers — ported
/// verbatim rather than a free-text field, matching that page's own
/// choice to list a short curated set instead of every IANA zone.
const kClinicTimezones = [
  ('Asia/Baghdad', 'العراق — بغداد (GMT+3)'),
  ('Asia/Riyadh', 'السعودية — الرياض (GMT+3)'),
  ('Asia/Kuwait', 'الكويت (GMT+3)'),
  ('Asia/Qatar', 'قطر (GMT+3)'),
  ('Asia/Dubai', 'الإمارات — دبي (GMT+4)'),
];
