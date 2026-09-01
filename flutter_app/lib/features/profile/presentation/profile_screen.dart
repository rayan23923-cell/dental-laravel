import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

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
    };

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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث الملف الشخصي.')));
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : 'تعذر الحفظ.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _savingInfo = false);
    }
  }

  Future<void> _savePassword() async {
    if (!(_passwordFormKey.currentState?.validate() ?? true)) return;
    setState(() => _savingPassword = true);

    try {
      await ref.read(profileRepositoryProvider).updatePassword(
            oldPassword: _oldPasswordController.text,
            newPassword: _newPasswordController.text,
          );
      if (mounted) {
        _oldPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تغيير كلمة المرور.')));
      }
    } catch (e) {
      if (mounted) {
        // `old_password` comes back field-keyed on a wrong-current-password
        // attempt (Api\ProfileController::updatePassword) — shown inline
        // via the field's validator re-running would need extra state, so
        // a snackbar with the real server message is simpler and still
        // accurate (matches this app's existing non-login-form convention).
        final message = e is ApiException ? e.userMessage : 'تعذر تغيير كلمة المرور.';
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

    return Scaffold(
      appBar: AppBar(title: const Text('الملف الشخصي')),
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
              label: const Text('تغيير الصورة'),
            ),
          ),
          const SizedBox(height: 16),
          Text('المعلومات الشخصية', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Form(
            key: _infoFormKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'الاسم', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null,
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
                  decoration: const InputDecoration(labelText: 'البريد الإلكتروني', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'رقم الهاتف', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _savingInfo ? null : () => _saveInfo(account.accountType),
                  child: _savingInfo
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('حفظ التغييرات'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          Text('تغيير كلمة المرور', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Form(
            key: _passwordFormKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _oldPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'كلمة المرور الحالية', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.isEmpty) ? 'هذا الحقل مطلوب' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _newPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.length < 6) ? 'يجب أن تتكون من 6 أحرف على الأقل' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور', border: OutlineInputBorder()),
                  validator: (v) => (v != _newPasswordController.text) ? 'كلمتا المرور غير متطابقتين' : null,
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _savingPassword ? null : _savePassword,
                  child: _savingPassword
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('تغيير كلمة المرور'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          Card(
            child: ListTile(
              leading: const Icon(Icons.devices_outlined),
              title: const Text('الأجهزة النشطة'),
              subtitle: const Text('إدارة الأجهزة المسجّل الدخول منها إلى هذا الحساب'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => context.push('/sessions'),
            ),
          ),
        ],
      ),
    );
  }
}
