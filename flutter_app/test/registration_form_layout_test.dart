// The registration form under the app's real theme, at a computer's
// window size (2026-10-21).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dental_clinic_app/core/theme/app_theme.dart';
import 'package:dental_clinic_app/features/patient_registration/data/patient_registration_repository.dart';
import 'package:dental_clinic_app/features/patient_registration/presentation/patient_registration_form_screen.dart';
import 'package:dental_clinic_app/features/patient_registration/presentation/patient_registration_providers.dart';
import 'package:dental_clinic_app/features/patient_registration/domain/service.dart';
import 'package:dental_clinic_app/features/clinic_settings/presentation/clinic_settings_providers.dart';

class _Repo implements PatientRegistrationRepository {
  @override
  Future<String?> stamp() async => 'a';
  @override
  dynamic noSuchMethod(Invocation i) => Future.value(null);
}

void main() {
  for (final dark in [false, true]) {
    testWidgets('registration form lays out with the app theme (dark: $dark)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      final repo = _Repo();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            patientRegistrationRepositoryProvider.overrideWithValue(repo),
            servicesProvider.overrideWith(
              (ref) async => const [
                Service(id: 1, name: 'test', price: 2000),
                Service(id: 2, name: 'Second', price: 5000),
              ],
            ),
            clinicSettingsProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            theme: dark ? instagramDarkTheme : instagramLightTheme,
            home: const Directionality(textDirection: TextDirection.rtl, child: PatientRegistrationFormScreen()),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.tap(find.text('test'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(tester.takeException(), isNull);
      // The register button lays out inside its row (2026-10-21: the
      // theme's full-width buttons left the whole card blank on Windows).
      expect(tester.getSize(find.byType(FilledButton)).width, lessThan(400));
      await tester.pumpWidget(const SizedBox());
    });
  }
}
