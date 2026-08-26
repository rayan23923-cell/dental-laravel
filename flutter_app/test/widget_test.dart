// Smoke test for this slice: full-app widget tests need a mocked network
// layer (TokenStorage/ApiClient hit real platform channels/HTTP), which is
// out of scope for this foundation slice — see flutter_app/README.md and
// the verification steps in the plan for the real, live-API checks this
// slice was tested against. This keeps `flutter test` passing with a real,
// non-trivial assertion instead of the stale counter-app template test
// (which referenced `MyApp`, removed in this slice).

import 'package:dental_clinic_app/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppConfig.baseUrl points at the api/v1 prefix', () {
    expect(AppConfig.baseUrl, endsWith('/api/v1'));
  });
}
