import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/clinic_chairs_admin_repository.dart';
import '../domain/clinic_chair_admin.dart';

final clinicChairsBoardProvider = FutureProvider.autoDispose<ClinicChairsBoard>((ref) {
  return ref.watch(clinicChairsAdminRepositoryProvider).fetchBoard();
});
