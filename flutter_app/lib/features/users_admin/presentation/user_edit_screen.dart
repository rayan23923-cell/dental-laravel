import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/numeric_input.dart';
import '../../../core/widgets/settings_list.dart';
import '../data/users_admin_repository.dart';
import '../domain/user_admin.dart';

final managedUserProvider = FutureProvider.autoDispose.family<ManagedUser, int>((ref, id) {
  return ref.watch(usersAdminRepositoryProvider).fetch(id);
});

/// One account's details and password (2026-10-21, by request), the web's
/// `Users/Edit`. Permissions stay on their own screen, linked at the bottom.
class UserEditScreen extends ConsumerWidget {
  const UserEditScreen({super.key, required this.userId});
  final int userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final userAsync = ref.watch(managedUserProvider(userId));
    return Scaffold(
      appBar: AppBar(title: Text(t['usersAdmin.editTitle']!)),
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text(error is ApiException ? error.userMessage : t['usersAdmin.loadFailed']!),
        ),
        data: (user) => _UserEditForm(user: user),
      ),
    );
  }
}

class _UserEditForm extends ConsumerStatefulWidget {
  const _UserEditForm({required this.user});
  final ManagedUser user;

  @override
  ConsumerState<_UserEditForm> createState() => _UserEditFormState();
}

class _UserEditFormState extends ConsumerState<_UserEditForm> {
  final _formKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();
  late final _fullName = TextEditingController(text: widget.user.fullName);
  late final _username = TextEditingController(text: widget.user.username);
  late final _email = TextEditingController(text: widget.user.email);
  late final _phone = TextEditingController(text: widget.user.phone ?? '');
  late final _notes = TextEditingController(text: widget.user.notes ?? '');
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late String _role = widget.user.role;
  late String _status = widget.user.status;
  bool _sendEmail = false;
  bool _saving = false;
  bool _changingPassword = false;

  @override
  void dispose() {
    for (final c in [_fullName, _username, _email, _phone, _notes, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    final t = ref.read(translationsProvider);
    setState(() => _saving = true);
    try {
      await ref.read(usersAdminRepositoryProvider).update(widget.user.id, {
        'full_name': _fullName.text.trim(),
        'username': _username.text.trim(),
        'email': _email.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'role': _role,
        'status': _status,
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      });
      _snack(t['usersAdmin.savedSuccess']!);
    } catch (e) {
      _snack(e is ApiException ? e.userMessage : t['usersAdmin.saveFailed']!);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePassword({required bool generate}) async {
    if (!generate && !(_passwordFormKey.currentState?.validate() ?? true)) return;
    final t = ref.read(translationsProvider);
    setState(() => _changingPassword = true);
    try {
      final result = await ref.read(usersAdminRepositoryProvider).changePassword(
            widget.user.id,
            password: _password.text,
            generate: generate,
            sendEmail: _sendEmail,
          );
      _password.clear();
      _confirm.clear();
      _snack(result.emailed ? t['usersAdmin.passwordEmailed']! : t['usersAdmin.passwordChanged']!);
      if (result.password != null && mounted) await _showGenerated(result.password!);
    } catch (e) {
      _snack(e is ApiException ? e.userMessage : t['usersAdmin.saveFailed']!);
    } finally {
      if (mounted) setState(() => _changingPassword = false);
    }
  }

  Future<void> _showGenerated(String password) {
    final t = ref.read(translationsProvider);
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t['usersAdmin.generatedTitle']!),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText(password,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 2)),
            const SizedBox(height: 12),
            Text(t['usersAdmin.generatedHint']!, style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy),
            label: Text(t['usersAdmin.copy']!),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: password));
              _snack(t['usersAdmin.copied']!);
            },
          ),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t['usersAdmin.close']!)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final user = widget.user;
    final roles = user.roles.isEmpty ? [user.role] : user.roles;
    final lockedRole = user.isSelf || user.role == 'super_admin';
    String? required(String? v) => (v == null || v.trim().isEmpty) ? t['usersAdmin.requiredField'] : null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (user.isSelf)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(t['usersAdmin.selfHint']!, style: const TextStyle(fontSize: 12, color: Colors.indigo)),
          ),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsGroupHeader(t['usersAdmin.accountSection']!),
              const SizedBox(height: 8),
              TextFormField(
                controller: _fullName,
                decoration: InputDecoration(labelText: t['usersAdmin.fullNameLabel'], border: const OutlineInputBorder()),
                validator: required,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _username,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: t['usersAdmin.usernameLabel'], border: const OutlineInputBorder()),
                validator: required,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _email,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: t['usersAdmin.emailLabel'], border: const OutlineInputBorder()),
                validator: required,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phone,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.phone,
                inputFormatters: phoneOnly,
                decoration: InputDecoration(labelText: t['usersAdmin.phoneLabel'], border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: InputDecoration(labelText: t['usersAdmin.roleLabel'], border: const OutlineInputBorder()),
                items: [for (final r in roles) DropdownMenuItem(value: r, child: Text(userRoleLabel(r)))],
                onChanged: lockedRole ? null : (v) => setState(() => _role = v ?? _role),
              ),
              const SizedBox(height: 16),
              Text(t['usersAdmin.statusLabel']!, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'active', icon: const Icon(Icons.check_circle_outline), label: Text(t['usersAdmin.active']!)),
                  ButtonSegment(value: 'inactive', icon: const Icon(Icons.block), label: Text(t['usersAdmin.inactive']!)),
                ],
                selected: {_status},
                onSelectionChanged: user.isSelf ? null : (s) => setState(() => _status = s.first),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4, top: 6),
                child: Text(t['usersAdmin.inactiveHint']!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notes,
                maxLines: 3,
                decoration: InputDecoration(labelText: t['usersAdmin.notesLabel'], border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: Text(t['usersAdmin.saveInfo']!),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Form(
          key: _passwordFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsGroupHeader(t['usersAdmin.passwordSection']!),
              const SizedBox(height: 8),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(labelText: t['usersAdmin.newPassword'], border: const OutlineInputBorder()),
                validator: (v) => (v == null || v.length < 6) ? t['usersAdmin.passwordTooShort'] : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirm,
                obscureText: true,
                decoration: InputDecoration(labelText: t['usersAdmin.confirmPassword'], border: const OutlineInputBorder()),
                validator: (v) => v != _password.text ? t['usersAdmin.passwordMismatch'] : null,
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _sendEmail,
                onChanged: (v) => setState(() => _sendEmail = v ?? false),
                title: Text(t['usersAdmin.sendByEmail']!, style: const TextStyle(fontSize: 14)),
              ),
              if (!user.isSelf)
                Text(t['usersAdmin.passwordSignOutHint']!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _changingPassword ? null : () => _changePassword(generate: false),
                icon: const Icon(Icons.lock_reset),
                label: Text(t['usersAdmin.changePassword']!),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _changingPassword ? null : () => _changePassword(generate: true),
                icon: const Icon(Icons.key),
                label: Text(t['usersAdmin.generatePassword']!),
              ),
            ],
          ),
        ),
        if (user.role != 'super_admin') ...[
          const SizedBox(height: 28),
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(t['usersAdmin.permissionsLink']!),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => context.push('/admin/permissions/${user.id}'),
            ),
          ),
        ],
      ],
    );
  }
}
