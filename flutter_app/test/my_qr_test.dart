import 'dart:convert';

import 'package:dental_clinic_app/core/i18n/app_translations.dart';
import 'package:dental_clinic_app/core/router/nav_destinations.dart';
import 'package:dental_clinic_app/features/auth/domain/account_type.dart';
import 'package:dental_clinic_app/features/doctor_qr/my_qr_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('doctor QR carries the ID-card payload the supervisor scanner reads', () {
    expect(jsonDecode(doctorQrPayload(42)), {'type': 'doctor', 'id': 42});
  });

  test('doctors get their own QR tab instead of the scanner', () {
    final routes = navDestinationsFor(AccountType.doctor, unreadNotifications: 0, t: kTranslationsAr).map((d) => d.route);
    expect(routes, contains('/my-qr'));
    expect(routes, isNot(contains('/scan')));
  });
}
