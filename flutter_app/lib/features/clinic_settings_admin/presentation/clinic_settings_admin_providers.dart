import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/clinic_settings_admin_repository.dart';
import '../domain/clinic_settings_admin.dart';

final clinicSettingsAdminProvider = FutureProvider.autoDispose<ClinicSettingsAdmin>((ref) {
  return ref.watch(clinicSettingsAdminRepositoryProvider).fetch();
});
