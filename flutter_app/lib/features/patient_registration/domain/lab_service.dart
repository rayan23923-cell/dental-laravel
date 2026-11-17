/// One of the lab's own priced services (2026-11-17, by request) —
/// `GET /lab/services`, see `App\Models\LabService`. Only the lab sees
/// them: a patient who came for the test only is registered against one,
/// and its price is booked as a lab payment.
class LabService {
  const LabService({required this.id, required this.name, required this.price, this.active = true, this.patients = 0});

  factory LabService.fromJson(Map<String, dynamic> json) => LabService(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        price: double.tryParse(json['price'].toString()) ?? 0,
        active: json['active'] as bool? ?? true,
        patients: (json['patients'] as num?)?.toInt() ?? 0,
      );

  final int id;
  final String name;
  final double price;
  final bool active;

  /// Patients registered against it; such a service is switched off
  /// instead of deleted.
  final int patients;
}

/// What the account may do with lab services (`lab_services` grants).
class LabServiceAbilities {
  const LabServiceAbilities({this.view = false, this.manage = false, this.register = false});

  factory LabServiceAbilities.fromJson(Map<String, dynamic>? json) => LabServiceAbilities(
        view: json?['view'] as bool? ?? false,
        manage: json?['manage'] as bool? ?? false,
        register: json?['register'] as bool? ?? false,
      );

  final bool view;
  final bool manage;
  final bool register;
}
