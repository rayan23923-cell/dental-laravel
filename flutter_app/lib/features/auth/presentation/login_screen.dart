import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../data/auth_repository.dart';
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
/// Redesigned (2026-08-27) to actually use the app's ambient Instagram
/// theme (`app_theme.dart`) instead of a one-off hardcoded navy/gold
/// palette layered on top of it. That mismatch was more than cosmetic: the
/// old version hardcoded each field's `fillColor` to a near-white grey but
/// left the typed text's color unset, so it fell through to the ambient
/// theme's default — which is near-white in dark mode. White text on a
/// near-white field is how a user ends up unable to see anything they
/// type. Using the theme's own `inputDecorationTheme` (already
/// light/dark-correct, already Instagram-accurate) fixes that at the root
/// instead of hand-picking one more hardcoded color that could drift out
/// of sync with the theme again later.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
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

  /// "نسيت كلمة المرور؟" — a 2-step dialog (2026-08-29, replacing the old
  /// single "enter email" step, by request): step 1 requests a 5-minute
  /// one-time code (`AuthRepository.sendPasswordResetCode`); step 2 asks
  /// for that code plus a new password and completes the reset natively
  /// in-app (`resetPasswordWithOtp`) — unlike the old link-based flow,
  /// which handed off to a browser to finish on the web reset-password
  /// page, a typed code has nowhere else to go.
  Future<void> _showForgotPasswordDialog() async {
    final emailController = TextEditingController();
    final otpController = TextEditingController();
    final passwordController = TextEditingController();
    final passwordConfirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var sending = false;
    var step = 1;
    var obscurePassword = true;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(step == 1 ? 'نسيت كلمة المرور؟' : 'أدخل رمز التحقق'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: step == 1
                  ? [
                      TextFormField(
                        controller: emailController,
                        autofocus: true,
                        enabled: !sending,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(labelText: 'البريد الإلكتروني'),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return 'هذا الحقل مطلوب';
                          if (!value.contains('@')) return 'بريد إلكتروني غير صالح';
                          return null;
                        },
                      ),
                    ]
                  : [
                      Text(
                        'إذا كان هذا البريد مسجلاً لدينا، فقد وصلك رمز تحقق صالح لمدة 5 دقائق.',
                        style: Theme.of(dialogContext).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: otpController,
                        autofocus: true,
                        enabled: !sending,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: const InputDecoration(labelText: 'رمز التحقق', counterText: ''),
                        validator: (value) {
                          if (value == null || value.trim().length != 6) return 'أدخل رمزاً مكوناً من 6 أرقام';
                          return null;
                        },
                      ),
                      TextFormField(
                        controller: passwordController,
                        enabled: !sending,
                        obscureText: obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'كلمة المرور الجديدة',
                          suffixIcon: IconButton(
                            icon: Icon(obscurePassword ? Icons.visibility : Icons.visibility_off),
                            onPressed: () => setDialogState(() => obscurePassword = !obscurePassword),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.length < 6) return 'كلمة المرور قصيرة جداً (6 أحرف على الأقل)';
                          return null;
                        },
                      ),
                      TextFormField(
                        controller: passwordConfirmController,
                        enabled: !sending,
                        obscureText: obscurePassword,
                        decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور'),
                        validator: (value) {
                          if (value != passwordController.text) return 'كلمتا المرور غير متطابقتين';
                          return null;
                        },
                      ),
                    ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: sending ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: sending
                  ? null
                  : () async {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      setDialogState(() => sending = true);
                      try {
                        if (step == 1) {
                          final message = await ref
                              .read(authRepositoryProvider)
                              .sendPasswordResetCode(emailController.text.trim());
                          setDialogState(() {
                            sending = false;
                            step = 2;
                          });
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
                          }
                        } else {
                          await ref.read(authRepositoryProvider).resetPasswordWithOtp(
                                email: emailController.text.trim(),
                                otp: otpController.text.trim(),
                                password: passwordController.text,
                                passwordConfirmation: passwordConfirmController.text,
                              );
                          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('تم تغيير كلمة المرور بنجاح، يمكنك تسجيل الدخول الآن.')),
                            );
                          }
                        }
                      } catch (e) {
                        setDialogState(() => sending = false);
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text(e is ApiException ? e.userMessage : 'تعذر إتمام الطلب.')),
                          );
                        }
                      }
                    },
              child: sending
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(step == 1 ? 'إرسال الرمز' : 'حفظ كلمة المرور'),
            ),
          ],
        ),
      ),
    );

    emailController.dispose();
    otpController.dispose();
    passwordController.dispose();
    passwordConfirmController.dispose();
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
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    Center(child: _Logo(logoUrl: branding?.logoUrl)),
                    const SizedBox(height: 16),
                    Text(
                      'المستشفى التعليمي لكلية طب الأسنان',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      'جامعة تكريت',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 40),
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
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return 'هذا الحقل مطلوب';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      enabled: !isLoading,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'كلمة المرور',
                        errorText: _fieldErrors['password'],
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            color: InstagramColors.gray,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'هذا الحقل مطلوب';
                        return null;
                      },
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(
                        onPressed: isLoading ? null : _showForgotPasswordDialog,
                        child: const Text('نسيت كلمة المرور؟'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: isLoading ? null : _submit,
                      child: isLoading
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.onPrimary),
                            )
                          : const Text('تسجيل الدخول'),
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

/// The clinic logo, sized and framed the way Instagram's own login screen
/// treats its wordmark — a plain, un-boxed mark sitting directly on the
/// scaffold background, no shadow/tinted disc behind it (that treatment
/// belonged to `SplashScreen`'s navy backdrop, which this screen no longer
/// shares). Same admin-configured-logo-with-bundled-fallback contract as
/// before.
class _Logo extends StatelessWidget {
  const _Logo({required this.logoUrl});

  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 96,
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
