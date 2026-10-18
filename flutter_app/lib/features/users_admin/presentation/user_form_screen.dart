import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/settings_list.dart';
import '../../permissions_admin/domain/permission_admin.dart';
import '../../permissions_admin/presentation/permissions_admin_providers.dart';
import '../../permissions_admin/presentation/permissions_editor.dart';
import '../data/users_admin_repository.dart';
import '../domain/user_admin.dart';
import '../../../core/widgets/numeric_input.dart';

final userFormOptionsProvider = FutureProvider.autoDispose<UserFormOptions>((ref) {
  return ref.watch(usersAdminRepositoryProvider).formOptions();
});

/// Create-only — see `UsersAdminRepository`'s docblock. The account's
/// permissions and access scope are picked on the same screen with the
/// shared [PermissionsEditor] (2026-10-14, by request): picking a role
/// ticks its ready-made grants, which can be changed before saving.
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
  Set<String> _grants = {};
  final PermissionScopeSelection _scope = PermissionScopeSelection();
  UserFormOptions? _options;

  void _applyRoleDefaults() => _grants = Set.of(_options?.roleDefaults[_role] ?? const <String>[]);

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
      // Only once the editor has loaded; otherwise the role preset applies.
      if (_options != null) 'grants': _grants.toList(),
      if (_options != null) 'scope': _scope.toJson(),
    };

    try {
      await ref.read(usersAdminRepositoryProvider).create(payload);
      ref.invalidate(permissionUserListProvider);
      if (mounted) {
        final t = ref.read(translationsProvider);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['usersAdmin.addedSuccess']!)));
        context.pop();
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
    final optionsAsync = ref.watch(userFormOptionsProvider);
    final options = optionsAsync.valueOrNull;
    if (options != null && _options == null) {
      _options = options;
      _applyRoleDefaults();
    }
    return Scaffold(
      appBar: AppBar(title: Text(t['usersAdmin.newUserTitle']!)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SettingsGroupHeader(t['usersAdmin.accountSection']!),
            const SizedBox(height: 8),
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
              inputFormatters: phoneOnly,
              decoration: InputDecoration(labelText: t['usersAdmin.phoneLabel'], border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: InputDecoration(labelText: t['usersAdmin.roleLabel'], border: const OutlineInputBorder()),
              items: [for (final r in kAssignableUserRoles) DropdownMenuItem(value: r.$1, child: Text(r.$2))],
              onChanged: (v) => setState(() {
                _role = v ?? _role;
                _applyRoleDefaults();
              }),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4, top: 6),
              child: Text(t['usersAdmin.roleDefaultsHint']!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(labelText: t['usersAdmin.passwordLabel'], border: const OutlineInputBorder()),
              validator: (v) => (v == null || v.length < 6) ? t['usersAdmin.passwordTooShort'] : null,
            ),
            const SizedBox(height: 24),
            optionsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stackTrace) => Text(
                error is ApiException ? error.userMessage : t['permissionsAdmin.loadFailed']!,
                style: const TextStyle(color: Colors.grey),
              ),
              data: (o) => PermissionsEditor(
                modules: o.modules,
                scopeOptions: o.scopeOptions,
                grants: _grants,
                scope: _scope,
                onChanged: () => setState(() {}),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: Text(t['usersAdmin.saveAndContinue']!),
          ),
        ),
      ),
    );
  }
}
