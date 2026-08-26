import '../domain/auth_account.dart';

/// Only two variants on purpose — "is a request in flight" / "did the last
/// attempt fail" are Riverpod's `AsyncValue<AuthState>` concerns (loading/
/// error), not modeled twice here.
sealed class AuthState {
  const AuthState();
}

final class Unauthenticated extends AuthState {
  const Unauthenticated();
}

final class Authenticated extends AuthState {
  const Authenticated(this.account);
  final AuthAccount account;
}
