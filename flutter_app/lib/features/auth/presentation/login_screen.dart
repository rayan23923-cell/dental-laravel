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

  Future<void> _showForgotPasswordDialog() async {
    final emailController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var sending = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('نسيت كلمة المرور؟'),
          content: Form(
            key: formKey,
            child: TextFormField(
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
                        final message = await ref
                            .read(authRepositoryProvider)
                            .sendPasswordResetLink(emailController.text.trim());
                        if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
                        }
                      } catch (e) {
                        setDialogState(() => sending = false);
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text(e is ApiException ? e.userMessage : 'تعذر إرسال الطلب.')),
                          );
                        }
                      }
                    },
              child: sending
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('إرسال'),
            ),
          ],
        ),
      ),
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
