import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/auth_state.dart';
import '../data/clinic_settings_repository.dart';
import '../domain/clinic_settings.dart';

/// Gated on being authenticated (`/clinic-settings` requires `auth:sanctum`)
/// and deliberately swallows any failure to `null` — branding/theme is an
/// enhancement, never allowed to block reaching the home screen.
/// `app_theme.dart` treats `null` exactly like the server's own
/// `ThemePalette::resolve(null)`: fall back to `unit-dark`.
final clinicSettingsProvider = FutureProvider<ClinicSettings?>((ref) async {
  final auth = ref.watch(authControllerProvider);
  if (auth.valueOrNull is! Authenticated) return null;

  try {
    return await ref.read(clinicSettingsRepositoryProvider).fetch();
  } catch (_) {
    return null;
  }
});
