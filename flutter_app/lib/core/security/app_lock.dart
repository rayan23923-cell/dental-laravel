import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/auth_state.dart';
import '../i18n/locale_controller.dart';
import '../theme/app_theme.dart';

/// Optional fingerprint / Face ID lock (2026-10-28, by request: "دخول
/// بالبصمة أو بالوجه"). The session already survives restarts (the token is
/// kept), so instead of a password the app asks for the fingerprint or face
/// when it opens, or returns after [_relockAfter] in the background. Phones
/// only; the device PIN is accepted when no biometric is enrolled or it
/// fails. Turned on from the profile page.
class AppLockState {
  const AppLockState({this.enabled = false, this.locked = false});
  final bool enabled;
  final bool locked;
}

final appLockProvider = NotifierProvider<AppLockController, AppLockState>(AppLockController.new);

class AppLockController extends Notifier<AppLockState> {
  static const _key = 'app_lock_enabled';
  static const _relockAfter = Duration(minutes: 1);

  static bool get isSupportedPlatform =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  final _auth = LocalAuthentication();
  DateTime? _pausedAt;

  @override
  AppLockState build() {
    if (isSupportedPlatform) _load();
    return const AppLockState();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_key) ?? false;
    // Locked from a cold start.
    state = AppLockState(enabled: enabled, locked: enabled);
  }

  /// Whether this phone can lock at all (a fingerprint, face or PIN set up).
  Future<bool> deviceSupported() async {
    if (!isSupportedPlatform) return false;
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(stickyAuth: true),
      );
    } catch (_) {
      return false;
    }
  }

  /// Turning it on asks once first, so a lock that can't be opened is never set.
  Future<bool> setEnabled(bool enabled, String reason) async {
    if (enabled && !await _authenticate(reason)) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
    state = AppLockState(enabled: enabled);
    return true;
  }

  Future<void> unlock(String reason) async {
    if (await _authenticate(reason)) state = AppLockState(enabled: state.enabled);
  }

  void onLifecycle(AppLifecycleState lifecycle) {
    if (!state.enabled) return;
    if (lifecycle == AppLifecycleState.paused) {
      _pausedAt ??= DateTime.now();
    } else if (lifecycle == AppLifecycleState.resumed) {
      final pausedAt = _pausedAt;
      _pausedAt = null;
      if (pausedAt != null && DateTime.now().difference(pausedAt) >= _relockAfter) {
        state = AppLockState(enabled: true, locked: true);
      }
    }
  }
}

/// Covers the app while [appLockProvider] is locked and someone is signed
/// in; the screens underneath stay mounted, so nothing is lost.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> with WidgetsBindingObserver {
  bool _prompting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      ref.read(appLockProvider.notifier).onLifecycle(state);

  Future<void> _unlock() async {
    if (_prompting) return;
    _prompting = true;
    await ref.read(appLockProvider.notifier).unlock(ref.read(translationsProvider)['appLock.reason']!);
    _prompting = false;
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    final signedIn = ref.watch(authControllerProvider).valueOrNull is Authenticated;
    final show = lock.locked && signedIn;
    if (show) {
      // Asks straight away; the button is there if it was dismissed.
      WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
    }
    return Stack(
      children: [
        widget.child,
        if (show) _LockScreen(onUnlock: _unlock),
      ],
    );
  }
}

class _LockScreen extends ConsumerWidget {
  const _LockScreen({required this.onUnlock});
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final theme = Theme.of(context);
    return Positioned.fill(
      child: Material(
        color: theme.scaffoldBackgroundColor,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: InstagramColors.gradient,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.lock_outline, color: Colors.white, size: 36),
                  ),
                  const SizedBox(height: 20),
                  Text(t['appLock.locked']!, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size(200, 48)),
                    onPressed: onUnlock,
                    icon: const Icon(Icons.fingerprint),
                    label: Text(t['appLock.unlock']!),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
