import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Best-effort: throws until a real Firebase project (google-services.json
  // + backend credentials) is configured — see flutter_app/README.md's
  // Firebase section. Push notifications simply stay inactive until then;
  // nothing else in the app depends on this succeeding.
  try {
    await Firebase.initializeApp().timeout(const Duration(seconds: 3));
  } catch (_) {
    // Not configured yet — fine, PushNotificationService no-ops too.
  }
  runApp(const ProviderScope(child: App()));
}
