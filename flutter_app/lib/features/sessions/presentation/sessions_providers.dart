import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/sessions_repository.dart';
import '../domain/account_session.dart';

/// The current principal's active sessions (Sanctum tokens), newest-used
/// first — see `SessionsRepository`.
final accountSessionsProvider = FutureProvider.autoDispose<List<AccountSession>>((ref) async {
  return ref.watch(sessionsRepositoryProvider).list();
});
