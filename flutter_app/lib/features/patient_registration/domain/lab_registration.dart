import 'patient_registration.dart';
import 'registration_payment_state.dart';

/// One row of `GET /lab` (`Api\LabController::index()`, 2026-10-17): the
/// registration plus whether its lab fee is paid and, while it is still
/// pending, the earlier valid clear result it can reuse.
class LabRegistration {
  const LabRegistration({required this.registration, required this.labPaid, this.previousScreening});

  factory LabRegistration.fromJson(Map<String, dynamic> json) => LabRegistration(
        registration: PatientRegistration.fromJson(json),
        labPaid: json['lab_paid'] as bool? ?? false,
        previousScreening: json['previous_screening'] == null
            ? null
            : PreviousScreening.fromJson(json['previous_screening'] as Map<String, dynamic>),
      );

  final PatientRegistration registration;
  final bool labPaid;
  final PreviousScreening? previousScreening;

  /// Same rule as the web `Lab/Index.vue`'s `canReuse()`.
  bool get canReuse => registration.screeningStatus == 'pending' && previousScreening != null;
}

/// `GET /lab`'s page: the rows plus the web page's other props (status
/// counts, lab fee, currency, validity days, whether results can be
/// recorded).
class LabPage {
  const LabPage({
    required this.items,
    required this.currentPage,
    required this.lastPage,
    required this.counts,
    this.labFee,
    this.currency,
    this.validityDays = 0,
    this.canConfirm = false,
  });

  factory LabPage.fromJson(Map<String, dynamic> json) {
    final meta = json['meta'] as Map<String, dynamic>? ?? const {};
    final counts = meta['counts'] as Map<String, dynamic>? ?? const {};
    return LabPage(
      items: ((json['data'] as List<dynamic>?) ?? const [])
          .map((e) => LabRegistration.fromJson(e as Map<String, dynamic>))
          .toList(),
      currentPage: (meta['current_page'] as num?)?.toInt() ?? 1,
      lastPage: (meta['last_page'] as num?)?.toInt() ?? 1,
      counts: {for (final e in counts.entries) e.key: (e.value as num?)?.toInt() ?? 0},
      labFee: meta['lab_fee'] == null ? null : double.tryParse(meta['lab_fee'].toString()),
      currency: meta['currency'] as String?,
      validityDays: (meta['validity_days'] as num?)?.toInt() ?? 0,
      canConfirm: meta['can_confirm'] as bool? ?? false,
    );
  }

  final List<LabRegistration> items;
  final int currentPage;
  final int lastPage;

  /// Registrations per screening status ('pending' / 'flagged' / 'clear').
  final Map<String, int> counts;

  /// A positive configured fee, else null (no fee is taken).
  final double? labFee;
  final String? currency;
  final int validityDays;
  final bool canConfirm;

  int countFor(String status) =>
      status == 'all' ? counts.values.fold(0, (a, b) => a + b) : (counts[status] ?? 0);
}
