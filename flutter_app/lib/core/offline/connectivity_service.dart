import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `true` once the device reports any network path (wifi/cellular/etc.) —
/// not a guarantee the *server* is reachable (a captive portal can report
/// "connected" with no real internet), just the signal used to trigger a
/// sync *attempt*. Whether that attempt actually succeeds is always
/// decided by the real API call's own result (`NetworkException` vs not —
/// see `ApiException.fromDioException`), never by this stream alone.
final connectivityStreamProvider = StreamProvider<bool>((ref) {
  return Connectivity().onConnectivityChanged.map(
        (results) => !results.contains(ConnectivityResult.none),
      );
});
