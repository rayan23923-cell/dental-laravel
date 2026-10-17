import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final academicSessionSelectionProvider = Provider<AcademicSessionSelection>((ref) => AcademicSessionSelection());

/// Which academic year this app is viewing (2026-10-17) — the web's
/// `academic-sessions.select`, which keeps the choice in the browser
/// session. The API is stateless, so the app keeps the id here and
/// `ApiClient` sends it on every request as the `X-Academic-Session`
/// header (see the server's `AcademicSessionHelper`). Null means "the
/// current year", as on a fresh web session. Cleared on logout.
class AcademicSessionSelection {
  static const header = 'X-Academic-Session';
  static const _kSelected = 'academic_session_selected';

  int? _id;
  bool _loaded = false;

  Future<int?> read() async {
    if (_loaded) return _id;
    try {
      final prefs = await SharedPreferences.getInstance();
      _id = prefs.getInt(_kSelected);
    } catch (_) {
      // No preferences store (tests): behave as "no choice made".
      _id = null;
    }
    _loaded = true;
    return _id;
  }

  Future<void> write(int? id) async {
    _id = id;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (id == null) {
        await prefs.remove(_kSelected);
      } else {
        await prefs.setInt(_kSelected, id);
      }
    } catch (_) {
      // Kept in memory for this run only.
    }
  }

  Future<void> clear() => write(null);
}
