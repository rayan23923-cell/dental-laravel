import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/push/push_notification_service.dart';
import '../../../core/storage/token_storage.dart';
import '../data/auth_repository.dart';
import '../domain/auth_account.dart';
import 'auth_state.dart';

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    // The one place the 401-anywhere -> logout-everywhere wiring happens:
    // set once per ApiClient instance, on the already-built client.
    ref.read(apiClientProvider).onUnauthorized = () async {
      await ref.read(tokenStorageProvider).clear();
      state = const AsyncData(Unauthenticated());
    };

    final storage = ref.read(tokenStorageProvider);
    final token = await storage.readToken();
    final accountType = await storage.readAccountType();

    if (token == null || accountType == null) {
      return const Unauthenticated();
    }

    try {
      final account = await ref.read(authRepositoryProvider).fetchMe(accountType);
      // Fire-and-forget — never block session restore on push registration.
      unawaited(PushNotificationService(ref).init());
      return Authenticated(account);
    } catch (_) {
      // A failed session restore (expired/revoked token, or a transient
      // network hiccup at startup) is a normal "not logged in" outcome the
      // login screen handles — not an app-level error the user can't act on.
      await storage.clear();
      return const Unauthenticated();
    }
  }

  /// `identifier` is either the account's email or its username — the
  /// server figures out which, and whether it belongs to a staff or a
  /// doctor account (see `AuthRepository.login()`'s own doc comment).
  Future<void> login({required String identifier, required String password}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final (token, _, account) = await ref.read(authRepositoryProvider).login(
            identifier: identifier,
            password: password,
          );
      await ref.read(tokenStorageProvider).save(token: token, accountType: account.accountType);
      // Fire-and-forget — never block the login UX on push registration.
      unawaited(PushNotificationService(ref).init());
      return Authenticated(account);
    });
  }

  /// Called after a successful profile edit — the update endpoint already
  /// returns the fresh account, so this just swaps it into state without a
  /// redundant `/me` round-trip.
  void updateAccount(AuthAccount account) {
    state = AsyncData(Authenticated(account));
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    await ref.read(tokenStorageProvider).clear();
    state = const AsyncData(Unauthenticated());
  }
}
