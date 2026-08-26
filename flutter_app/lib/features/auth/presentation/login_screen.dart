import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../data/branding_repository.dart';
import 'auth_controller.dart';
import 'auth_state.dart';

/// One field, either the account's email or its username, and a password —
/// no staff/doctor toggle. The server (`Api\AuthController::login()`)
/// tries a staff match first, then a doctor match, and tells the client
/// back which one it was — matching the web app's own unified `/login`
/// form (see `App\Http\Requests\Auth\LoginRequest`). Never navigates
/// itself on success — `AppRouter`'s redirect reacts to
/// `authControllerProvider` becoming `Authenticated` instead, keeping
/// "where am I" single-sourced.
///
/// Visuals deliberately mirror `SplashScreen`'s branded navy/gold look
/// (same color values, same circular logo-frame language) rather than the
/// app's ambient Instagram-style light/dark theme, so the splash → login
/// hand-off reads as one continuous brand experience instead of two
/// unrelated screens back to back. The colors are duplicated here rather
/// than extracted into a shared file, to avoid touching the already-
/// verified `splash_screen.dart` for a four-constant DRY gain.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  static const _navyDark = Color(0xFF0A1128);
  static const _navyMid = Color(0xFF13224A);
  static const _gold = Color(0xFFD4AF37);
  static const _goldSoft = Color(0xFFF4E3B2);

  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  Map<String, String> _fieldErrors = {};
  String? _networkErrorMessage;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    await ref.read(authControllerProvider.notifier).login(
          identifier: _identifierController.text.trim(),
          password: _passwordController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AuthState>>(authControllerProvider, (previous, next) {
      next.whenOrNull(
        error: (error, stackTrace) {
          setState(() {
            _fieldErrors = {};
            _networkErrorMessage = null;
          });

          if (error is ValidationException) {
            setState(() {
              _fieldErrors = {
                for (final key in error.errors.keys)
                  key: error.errors[key]!.first,
              };
            });
          } else if (error is NetworkException) {
            setState(() => _networkErrorMessage = error.userMessage);
          } else if (error is ApiException) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.userMessage)));
          }
        },
      );
    });

    final isLoading = ref.watch(authControllerProvider).isLoading;
    final branding = ref.watch(publicBrandingProvider).valueOrNull;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_navyDark, _navyMid, _navyDark],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _LogoFrame(logoUrl: branding?.logoUrl),
                    const SizedBox(height: 20),
                    const Text(
                      'المستشفى التعليمي لكلية طب الأسنان',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _goldSoft,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                    const Text(
                      'جامعة تكريت',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 28),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'تسجيل الدخول',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _navyDark,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 20),
                            if (_networkErrorMessage != null) ...[
                              MaterialBanner(
                                content: Text(_networkErrorMessage!),
                                actions: [
                                  TextButton(
                                    onPressed: () => setState(() => _networkErrorMessage = null),
                                    child: const Text('إغلاق'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                            ],
                            TextFormField(
                              controller: _identifierController,
                              enabled: !isLoading,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.username, AutofillHints.email],
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: 'البريد الإلكتروني أو اسم المستخدم',
                                errorText: _fieldErrors['login'],
                                filled: true,
                                fillColor: const Color(0xFFF5F6FA),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: _navyMid, width: 1.5),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) return 'هذا الحقل مطلوب';
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _passwordController,
                              enabled: !isLoading,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _submit(),
                              decoration: InputDecoration(
                                labelText: 'كلمة المرور',
                                errorText: _fieldErrors['password'],
                                filled: true,
                                fillColor: const Color(0xFFF5F6FA),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: _navyMid, width: 1.5),
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) return 'هذا الحقل مطلوب';
                                return null;
                              },
                            ),
                            const SizedBox(height: 24),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: _navyDark,
                                foregroundColor: _gold,
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: isLoading ? null : _submit,
                              child: isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: _gold),
                                    )
                                  : const Text(
                                      'تسجيل الدخول',
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// White circular disc behind the clinic logo — same visual language as
/// `SplashScreen`'s logo frame, minus the entrance/pulse animation (this is
/// a persistent screen, not a transient splash). Uses the admin-configured
/// logo (`publicBrandingProvider`) when available, falling back to the
/// bundled brand asset otherwise — the same fail-open contract every other
/// logo/QR image in this app already follows.
class _LogoFrame extends StatelessWidget {
  const _LogoFrame({required this.logoUrl});

  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 130,
      height: 130,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Color(0x33D4AF37), blurRadius: 20, spreadRadius: 2),
        ],
      ),
      padding: const EdgeInsets.all(6),
      child: ClipOval(
        child: logoUrl != null
            ? Image.network(
                logoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Image.asset(
                  'assets/branding/app_logo.png',
                  fit: BoxFit.cover,
                ),
              )
            : Image.asset('assets/branding/app_logo.png', fit: BoxFit.cover),
      ),
    );
  }
}
