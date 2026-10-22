/// The general settings' forms and task progress switches (2026-10-22).
const kTaskSwitchKeys = ['electronic_forms_enabled', 'paper_forms_enabled', 'task_start_enabled', 'task_finish_enabled', 'task_lists_enabled', 'grade_entry_enabled', 'step_add_enabled'];

/// `Api\ClinicSettingController::show()`'s response shape. `theme` is
/// deliberately left out (the Flutter app uses a fixed theme, not the web
/// app's selectable one, per `flutter_app/README.md` §7). The SMTP
/// `mail_*` fields (2026-10-17) are editable here as on the web; the
/// stored password itself never comes back, only [mailPasswordSet].
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
    this.taskSwitches = const {},
    required this.logoUrl,
    required this.universityLogoUrl,
    this.mailHost,
    this.mailPort,
    this.mailUsername,
    this.mailEncryption,
    this.mailFromAddress,
    this.mailFromName,
    this.mailPasswordSet = false,
    this.mailConfigured = false,
    this.mailDriver,
    this.mailVisible = false,
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
        taskSwitches: {for (final key in kTaskSwitchKeys) key: json[key] as bool? ?? true},
        logoUrl: json['logo_url'] as String?,
        universityLogoUrl: json['university_logo_url'] as String?,
        mailHost: json['mail_host'] as String?,
        mailPort: (json['mail_port'] as num?)?.toInt(),
        mailUsername: json['mail_username'] as String?,
        mailEncryption: json['mail_encryption'] as String?,
        mailFromAddress: json['mail_from_address'] as String?,
        mailFromName: json['mail_from_name'] as String?,
        mailPasswordSet: json['mail_password_set'] as bool? ?? false,
        mailConfigured: json['mail_configured'] as bool? ?? false,
        mailDriver: json['mail_driver'] as String?,
        mailVisible: json.containsKey('mail_password_set'),
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

  /// Forms and task progress switched on/off for the whole system
  /// (2026-10-22, by request), keyed like the server's columns.
  final Map<String, bool> taskSwitches;
  final String? logoUrl;
  final String? universityLogoUrl;

  final String? mailHost;
  final int? mailPort;
  final String? mailUsername;

  /// `tls`, `ssl`, or null for none.
  final String? mailEncryption;
  final String? mailFromAddress;
  final String? mailFromName;

  /// Whether a password is stored — the form leaves its field blank to keep it.
  final bool mailPasswordSet;

  /// Host and sender address are saved, so mail is really sent.
  final bool mailConfigured;

  /// The server's fallback mailer (e.g. `log`) while SMTP is not set up.
  final String? mailDriver;

  /// The server only sends the mail settings to whoever may view
  /// settings; without them the form neither shows nor sends them (so a
  /// save can't blank settings it never saw).
  final bool mailVisible;
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
