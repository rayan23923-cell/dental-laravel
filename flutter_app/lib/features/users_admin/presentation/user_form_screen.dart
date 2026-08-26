import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إضافة المستخدم. حدد صلاحياته.')));
        context.pushReplacement('/admin/permissions/${user.id}');
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : 'تعذر الحفظ.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مستخدم جديد')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _fullNameController,
              decoration: const InputDecoration(labelText: 'الاسم الكامل', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: 'اسم المستخدم', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'البريد الإلكتروني', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'رقم الهاتف', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'الصلاحية (Role)', border: OutlineInputBorder()),
              items: [for (final r in kAssignableUserRoles) DropdownMenuItem(value: r.$1, child: Text(r.$2))],
              onChanged: (v) => setState(() => _role = v ?? _role),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'كلمة المرور', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.length < 6) ? 'يجب أن تتكون من 6 أحرف على الأقل' : null,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('حفظ ومتابعة للصلاحيات'),
            ),
          ],
        ),
      ),
    );
  }
}
