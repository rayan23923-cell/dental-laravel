import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

/// The clinic name/logo shown on the login screen — fetched via the public
/// `GET /branding` endpoint (`Api\BrandingController`), unlike
/// `clinicSettingsProvider` which requires an authenticated session and so
/// can't be used pre-login.
class PublicBranding {
  const PublicBranding({required this.clinicName, required this.logoUrl});

  factory PublicBranding.fromJson(Map<String, dynamic> json) => PublicBranding(
        clinicName: json['clinic_name'] as String? ?? '',
        logoUrl: json['logo_url'] as String?,
      );

  final String clinicName;
  final String? logoUrl;
}

/// Fail-open by design — the login screen must render (with its bundled
/// fallback logo) even if this fetch fails or the server has nothing
/// configured yet.
final publicBrandingProvider = FutureProvider<PublicBranding?>((ref) async {
  try {
    final data = await ref.watch(apiClientProvider).getJson('/branding') as Map<String, dynamic>;
    return PublicBranding.fromJson(data);
  } catch (_) {
    return null;
  }
});
