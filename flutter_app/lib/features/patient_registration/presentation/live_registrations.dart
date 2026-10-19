import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/patient_registration_repository.dart';

/// Reloads a registrations screen when a patient is registered or changed
/// on another device (2026-10-19, by request: the ticket desk and the lab
/// update by themselves). Asks the server for a small fingerprint every few
/// seconds and calls [onRegistrationsChanged] only when it changes.
mixin LiveRegistrations<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  Timer? _liveTimer;
  String? _lastStamp;
  bool _checking = false;

  void onRegistrationsChanged();

  @override
  void initState() {
    super.initState();
    _check();
    _liveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _check());
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final stamp = await ref.read(patientRegistrationRepositoryProvider).stamp();
      if (!mounted) return;
      if (_lastStamp != null && stamp != null && stamp != _lastStamp) onRegistrationsChanged();
      _lastStamp = stamp ?? _lastStamp;
    } catch (_) {
      // An older server or a dropped connection: try again next time.
    } finally {
      _checking = false;
    }
  }
}
