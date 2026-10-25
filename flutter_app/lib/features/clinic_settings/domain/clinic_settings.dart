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
    this.labFee,
    this.labValidityDays = 0,
    this.labStudentDiscountPercent = 50,
    this.groupsEnabled = true,
    this.currency,
  });

  factory ClinicSettings.fromJson(Map<String, dynamic> json) => ClinicSettings(
        theme: json['theme'] as String?,
        clinicName: json['clinic_name'] as String? ?? '',
        logoUrl: json['logo_url'] as String?,
        universityLogoUrl: json['university_logo_url'] as String?,
        universityName: json['university_name'] as String?,
        collegeName: json['college_name'] as String?,
        // Decimal column — may arrive as a string ("5000.00").
        labFee: json['lab_fee'] == null ? null : double.tryParse(json['lab_fee'].toString()),
        labValidityDays: int.tryParse('${json['lab_validity_days'] ?? 0}') ?? 0,
        labStudentDiscountPercent: double.tryParse('${json['lab_student_discount_percent'] ?? ''}') ?? 50,
        groupsEnabled: json['groups_enabled'] as bool? ?? true,
        currency: json['clinic_currency'] as String?,
      );

  final String? theme;
  final String clinicName;
  final String? logoUrl;
  final String? universityLogoUrl;
  // Used by the PDF letterhead (core/pdf/pdf_letterhead.dart) and, since
  // 2026-08-29, the thermal ticket/receipt headers (TicketWidget/
  // TaskInstanceTicketWidget/ReceiptWidget's headerTitle/headerSubtitle) —
  // same `universityName ?: clinicName` / `collegeName` precedence
  // `print/layout.blade.php`'s letterhead already uses.
  final String? universityName;
  final String? collegeName;

  /// Lab screening fee (null = none) and how many days a clear result
  /// stays valid (0 = off) — edited from the registration settings screen
  /// (2026-10-12), see `LabFeeGate` on the backend.
  final double? labFee;
  final int labValidityDays;

  /// Taken off [labFee] for a patient eligible for the student discount
  /// (2026-10-25); 50 by default.
  final double labStudentDiscountPercent;

  /// Groups on/off from clinic settings (2026-10-13), the same switch as
  /// the web's: off hides groups everywhere and task progress lists a
  /// stage's doctors directly.
  final bool groupsEnabled;

  /// The clinic's currency label (e.g. "دينار عراقي"), shown after amounts
  /// the way the web's payments page does (2026-10-17). Null = none.
  final String? currency;

  /// Same precedence as `print.layout.blade.php`'s letterhead: the
  /// university logo if one's uploaded, the clinic logo otherwise — used
  /// for the printed ticket's logo (`TicketWidget`), not the login-screen
  /// header (which keeps using [logoUrl] alone, unchanged).
  String? get ticketLogoUrl => universityLogoUrl ?? logoUrl;
}
