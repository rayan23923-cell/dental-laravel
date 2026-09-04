import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../data/users_admin_repository.dart';
import '../domain/user_admin.dart';

/// Create-only — see `UsersAdminRepository`'s docblock. On success, goes
/// straight to `permissions_admin`'s existing edit screen for the new
/// user (`pushReplacement`, not `push`: the create form shouldn't sit on
/// the back stack behind the permission editor).
class UserFormScreen extends ConsumerStatefulWidget {
  const UserFormScreen({super.key});

  @override
  ConsumerState<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends ConsumerState<UserFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  String _role = 'editor';
  bool _submitting = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    setState(() => _submitting = true);

    final payload = {
      'full_name': _fullNameController.text.trim(),
      'username': _usernameController.text.trim(),
      'email': _emailController.text.trim(),
      'phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      'password': _passwordController.text,
      'role': _role,
    };

    try {
      final UserAdmin user = await ref.read(usersAdminRepositoryProvider).create(payload);
      if (mounted) {
        final t = ref.read(translationsProvider);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['usersAdmin.addedSuccess']!)));
        context.pushReplacement('/admin/permissions/${user.id}');
      }
    } catch (e) {
      if (mounted) {
        final t = ref.read(translationsProvider);
        final message = e is ApiException ? e.userMessage : t['usersAdmin.saveFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t['usersAdmin.newUserTitle']!)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _fullNameController,
              decoration: InputDecoration(labelText: t['usersAdmin.fullNameLabel'], border: const OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? t['usersAdmin.requiredField'] : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _usernameController,
              decoration: InputDecoration(labelText: t['usersAdmin.usernameLabel'], border: const OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? t['usersAdmin.requiredField'] : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: t['usersAdmin.emailLabel'], border: const OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? t['usersAdmin.requiredField'] : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: t['usersAdmin.phoneLabel'], border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: InputDecoration(labelText: t['usersAdmin.roleLabel'], border: const OutlineInputBorder()),
              items: [for (final r in kAssignableUserRoles) DropdownMenuItem(value: r.$1, child: Text(r.$2))],
              onChanged: (v) => setState(() => _role = v ?? _role),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(labelText: t['usersAdmin.passwordLabel'], border: const OutlineInputBorder()),
              validator: (v) => (v == null || v.length < 6) ? t['usersAdmin.passwordTooShort'] : null,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(t['usersAdmin.saveAndContinue']!),
            ),
          ],
        ),
      ),
    );
  }
}
