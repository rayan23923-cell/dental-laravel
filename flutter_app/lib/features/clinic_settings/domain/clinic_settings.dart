/// Only the fields Phase 1 needs from `GET /clinic-settings` — theming plus
/// a nicer login-screen header. The full response has many more columns
/// (address, phone, working hours, mail settings, …), out of scope here.
class ClinicSettings {
  const ClinicSettings({
    required this.theme,
    required this.clinicName,
    required this.logoUrl,
    required this.universityLogoUrl,
    required this.universityName,
    required this.collegeName,
  });

  factory ClinicSettings.fromJson(Map<String, dynamic> json) => ClinicSettings(
        theme: json['theme'] as String?,
        clinicName: json['clinic_name'] as String? ?? '',
        logoUrl: json['logo_url'] as String?,
        universityLogoUrl: json['university_logo_url'] as String?,
        universityName: json['university_name'] as String?,
        collegeName: json['college_name'] as String?,
      );

  final String? theme;
  final String clinicName;
  final String? logoUrl;
  final String? universityLogoUrl;
  // Only used by the PDF letterhead (core/pdf/pdf_letterhead.dart) today.
  final String? universityName;
  final String? collegeName;

  /// Same precedence as `print.layout.blade.php`'s letterhead: the
  /// university logo if one's uploaded, the clinic logo otherwise — used
  /// for the printed ticket's logo (`TicketWidget`), not the login-screen
  /// header (which keeps using [logoUrl] alone, unchanged).
  String? get ticketLogoUrl => universityLogoUrl ?? logoUrl;
}
