import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../auth/domain/account_type.dart';
import '../../auth/domain/auth_account.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/auth_state.dart';
import '../data/profile_repository.dart';

/// Self-service profile + settings, for both account types — mirrors the
/// web app's `ProfileController`/`Doctor\ProfileController`, which each
/// have **two separate forms** (edit-info, change-password). Kept as two
/// forms here too, rather than merging them into one, matching that
/// separation and its current-password check on the password form.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _infoFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  XFile? _photoPick;
  Uint8List? _photoPreview;
  bool _seeded = false;
  bool _savingInfo = false;
  bool _savingPassword = false;
  // '' = "follow system language" (stored as null server-side) — same
  // convention the web's Profile/Edit.vue language select uses.
  String _locale = '';

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _seed(AuthAccount account) {
    if (_seeded) return;
    _seeded = true;
    _nameController.text = account.displayName;
    _phoneController.text = switch (account) {
      StaffAccount(:final phone) => phone ?? '',
      DoctorAccount(:final phone) => phone ?? '',
    };
    _emailController.text = switch (account) {
      StaffAccount(:final email) => email,
      DoctorAccount(:final email) => email ?? '',
    };
    _locale = account.locale ?? '';
  }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _photoPick = file;
      _photoPreview = bytes;
    });
  }

  Future<void> _saveInfo(AccountType accountType) async {
    if (!(_infoFormKey.currentState?.validate() ?? true)) return;
    setState(() => _savingInfo = true);

    final fields = {
      if (accountType == AccountType.doctor) 'name': _nameController.text.trim(),
      if (accountType == AccountType.staff) 'full_name': _nameController.text.trim(),
      'email': _emailController.text.trim(),
      'phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      // Always sent, even '' (never skipped as null) — ProfileRepository.update()
      // drops null fields entirely, and '' is exactly how "reset to follow
      // system language" gets communicated to Api\ProfileController.
      'locale': _locale,
    };

    final t = ref.read(translationsProvider);
    try {
      final account = await ref.read(profileRepositoryProvider).update(
            accountType: accountType,
            fields: fields,
            photo: _photoPick,
          );
      ref.read(authControllerProvider.notifier).updateAccount(account);
      if (mounted) {
        setState(() {
          _photoPick = null;
          _photoPreview = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['profile.updatedSuccess']!)));
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : t['profile.saveFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _savingInfo = false);
    }
  }

  Future<void> _savePassword() async {
    if (!(_passwordFormKey.currentState?.validate() ?? true)) return;
    setState(() => _savingPassword = true);
    final t = ref.read(translationsProvider);

    try {
      await ref.read(profileRepositoryProvider).updatePassword(
            oldPassword: _oldPasswordController.text,
            newPassword: _newPasswordController.text,
          );
      if (mounted) {
        _oldPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['profile.passwordChangedSuccess']!)));
      }
    } catch (e) {
      if (mounted) {
        // `old_password` comes back field-keyed on a wrong-current-password
        // attempt (Api\ProfileController::updatePassword) — shown inline
        // via the field's validator re-running would need extra state, so
        // a snackbar with the real server message is simpler and still
        // accurate (matches this app's existing non-login-form convention).
        final message = e is ApiException ? e.userMessage : t['profile.passwordChangeFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider).valueOrNull;
    if (authState is! Authenticated) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final account = authState.account;
    _seed(account);

    final currentPhotoUrl = switch (account) {
      StaffAccount(:final profileImageUrl) => profileImageUrl,
      DoctorAccount(:final profileImageUrl) => profileImageUrl,
    };
    final t = ref.watch(translationsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t['profile.title']!)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: GestureDetector(
              onTap: _pickPhoto,
              child: CircleAvatar(
                radius: 48,
                backgroundImage: _photoPreview != null
                    ? MemoryImage(_photoPreview!)
                    : (currentPhotoUrl != null ? NetworkImage(currentPhotoUrl) : null) as ImageProvider?,
                child: (_photoPreview == null && currentPhotoUrl == null)
                    ? const Icon(Icons.person, size: 40)
                    : null,
              ),
            ),
          ),
          Center(
            child: TextButton.icon(
              onPressed: _pickPhoto,
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(t['profile.changePhoto']!),
            ),
          ),
          const SizedBox(height: 16),
          Text(t['profile.personalInfo']!, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Form(
            key: _infoFormKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(labelText: t['profile.name']!, border: const OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? t['profile.requiredField']! : null,
                ),
                const SizedBox(height: 12),
                // Forced LTR — same RTL-bidi-reordering class already found
                // and fixed on the clinic-settings email/phone fields
                // (`ClinicSettingsEditScreen`): a value mixing strong-LTR
                // characters with bidi-neutral separators (`@`, digits with
                // no separator here, but the risk is the same shape) gets
                // visually reordered inside an RTL ancestor otherwise.
                TextFormField(
                  controller: _emailController,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(labelText: t['profile.email']!, border: const OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? t['profile.requiredField']! : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: t['profile.phone']!, border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _locale,
                  decoration: InputDecoration(labelText: t['profile.language']!, border: const OutlineInputBorder()),
                  items: [
                    DropdownMenuItem(value: '', child: Text(t['profile.languageSystem']!)),
                    DropdownMenuItem(value: 'ar', child: Text(t['profile.languageAr']!)),
                    DropdownMenuItem(value: 'en', child: Text(t['profile.languageEn']!)),
                  ],
                  onChanged: (value) => setState(() => _locale = value ?? ''),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _savingInfo ? null : () => _saveInfo(account.accountType),
                  child: _savingInfo
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(t['profile.saveChanges']!),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          Text(t['profile.changePassword']!, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Form(
            key: _passwordFormKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _oldPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(labelText: t['profile.currentPassword']!, border: const OutlineInputBorder()),
                  validator: (v) => (v == null || v.isEmpty) ? t['profile.requiredField']! : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _newPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(labelText: t['profile.newPassword']!, border: const OutlineInputBorder()),
                  validator: (v) => (v == null || v.length < 6) ? t['profile.passwordTooShort']! : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(labelText: t['profile.confirmPassword']!, border: const OutlineInputBorder()),
                  validator: (v) => (v != _newPasswordController.text) ? t['profile.passwordMismatch']! : null,
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _savingPassword ? null : _savePassword,
                  child: _savingPassword
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(t['profile.changePassword']!),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          Card(
            child: ListTile(
              leading: const Icon(Icons.devices_outlined),
              title: Text(t['profile.activeSessions']!),
              subtitle: Text(t['profile.activeSessionsSubtitle']!),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => context.push('/sessions'),
            ),
          ),
        ],
      ),
    );
  }
}
