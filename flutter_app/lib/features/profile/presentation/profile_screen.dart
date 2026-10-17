import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/config/server_settings_controller.dart';
import '../../../core/i18n/locale_controller.dart';
import '../../../core/updater/desktop_update_checker.dart';
import '../../../core/updater/desktop_update_gate.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/settings_list.dart';
import '../../auth/domain/account_type.dart';
import '../../auth/domain/auth_account.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/auth_state.dart';
import '../data/profile_repository.dart';
import '../../../core/widgets/numeric_input.dart';

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
  // Telegram-style list (2026-10-14, by request): the open section, if any.
  String? _open;
  // In-app updates (2026-10-17).
  String? _version;
  bool _autoUpdate = true;
  bool _checkingUpdates = false;

  @override
  void initState() {
    super.initState();
    if (DesktopUpdateChecker.isSupported) {
      PackageInfo.fromPlatform().then((info) {
        if (mounted) setState(() => _version = info.version);
      });
      DesktopUpdateChecker.autoCheckEnabled().then((v) {
        if (mounted) setState(() => _autoUpdate = v);
      });
    }
  }

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

  /// Picking a photo saves it straight away, like Instagram.
  Future<void> _pickPhoto(AccountType accountType) async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _photoPick = file;
      _photoPreview = bytes;
    });
    await _saveInfo(accountType);
  }

  void _toggle(String key) => setState(() => _open = _open == key ? null : key);

  Future<void> _saveInfo(AccountType accountType) async {
    if (!(_infoFormKey.currentState?.validate() ?? true)) {
      setState(() => _open = 'personal');
      return;
    }
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
      final account = await ref.read(profileRepositoryProvider).update(accountType: accountType, fields: fields, photo: _photoPick);
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
    if (!(_passwordFormKey.currentState?.validate() ?? true)) {
      setState(() => _open = 'password');
      return;
    }
    setState(() => _savingPassword = true);
    final t = ref.read(translationsProvider);

    try {
      await ref
          .read(profileRepositoryProvider)
          .updatePassword(oldPassword: _oldPasswordController.text, newPassword: _newPasswordController.text);
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

    final scheme = Theme.of(context).colorScheme;
    final server = ref.watch(serverSettingsProvider);
    final chips = switch (account) {
      StaffAccount(:final role) => [t['roles.$role'] ?? role],
      DoctorAccount(:final educationTypeName, :final stageName) => [?educationTypeName, ?stageName],
    };
    final username = switch (account) {
      StaffAccount(:final username) => username,
      DoctorAccount(:final username) => username,
    };
    final photo = _photoPreview != null
        ? MemoryImage(_photoPreview!)
        : (currentPhotoUrl != null ? NetworkImage(currentPhotoUrl) : null) as ImageProvider?;
    final languageLabel = switch (_locale) {
      'ar' => t['profile.languageAr']!,
      'en' => t['profile.languageEn']!,
      _ => t['profile.languageSystem']!,
    };

    Widget saveButton(String label, bool busy, VoidCallback onPressed) => Align(
      alignment: AlignmentDirectional.centerEnd,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        child: busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(label),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(t['profile.title']!)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          // Instagram-style header: big photo with a camera badge, name,
          // @username and role / stage chips.
          Center(
            child: GestureDetector(
              onTap: _savingInfo ? null : () => _pickPhoto(account.accountType),
              child: Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.primaryContainer),
                    child: CircleAvatar(
                      radius: 54,
                      backgroundColor: scheme.primary,
                      backgroundImage: photo,
                      child: photo == null ? const Icon(Icons.person, size: 54, color: Colors.white) : null,
                    ),
                  ),
                  PositionedDirectional(
                    end: 2,
                    bottom: 2,
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.primary,
                        border: Border.all(color: scheme.surface, width: 2),
                      ),
                      child: _savingInfo && _photoPick != null
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.photo_camera, size: 18, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(account.displayName, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
          Text(
            '@$username',
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final chip in chips)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(20)),
                    child: Text(chip, style: TextStyle(fontSize: 12, color: scheme.onPrimaryContainer)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Form(
            key: _infoFormKey,
            child: SettingsGroupCard(
              children: [
                SettingsSection(
                  icon: Icons.person_outline,
                  color: const Color(0xFF6366F1),
                  title: t['profile.personalInfo']!,
                  summary: [_emailController.text, _phoneController.text].where((v) => v.trim().isNotEmpty).join(' · '),
                  open: _open == 'personal',
                  onToggle: () => _toggle('personal'),
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(labelText: t['profile.name']!, border: const OutlineInputBorder()),
                      validator: (v) => (v == null || v.trim().isEmpty) ? t['profile.requiredField']! : null,
                    ),
                    const SizedBox(height: 12),
                    // Forced LTR: an email mixes strong-LTR letters with
                    // bidi-neutral `@`/`.`, which an RTL field reorders.
                    TextFormField(
                      controller: _emailController,
                      textDirection: TextDirection.ltr,
                      keyboardType: TextInputType.emailAddress,
                      inputFormatters: digitsOnly,
                      decoration: InputDecoration(labelText: t['profile.email']!, border: const OutlineInputBorder()),
                      validator: (v) => (v == null || v.trim().isEmpty) ? t['profile.requiredField']! : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneController,
                      textDirection: TextDirection.ltr,
                      keyboardType: TextInputType.phone,
                      inputFormatters: phoneOnly,
                      decoration: InputDecoration(labelText: t['profile.phone']!, border: const OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    saveButton(t['profile.saveChanges']!, _savingInfo, () => _saveInfo(account.accountType)),
                  ],
                ),
                SettingsSection(
                  icon: Icons.translate,
                  color: const Color(0xFF0EA5E9),
                  title: t['profile.language']!,
                  summary: languageLabel,
                  open: _open == 'language',
                  onToggle: () => _toggle('language'),
                  children: [
                    RadioGroup<String>(
                      groupValue: _locale,
                      onChanged: (v) => setState(() => _locale = v ?? ''),
                      child: Column(
                        children: [
                          for (final (value, label) in [
                            ('', t['profile.languageSystem']!),
                            ('ar', t['profile.languageAr']!),
                            ('en', t['profile.languageEn']!),
                          ])
                            RadioListTile<String>(contentPadding: EdgeInsets.zero, value: value, title: Text(label)),
                        ],
                      ),
                    ),
                    saveButton(t['profile.saveChanges']!, _savingInfo, () => _saveInfo(account.accountType)),
                  ],
                ),
                SettingsSection(
                  icon: Icons.lock_outline,
                  color: const Color(0xFFF59E0B),
                  title: t['profile.changePassword']!,
                  summary: '',
                  open: _open == 'password',
                  onToggle: () => _toggle('password'),
                  children: [
                    Form(
                      key: _passwordFormKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                          const SizedBox(height: 12),
                          saveButton(t['profile.changePassword']!, _savingPassword, _savePassword),
                        ],
                      ),
                    ),
                  ],
                ),
                // In-app updates (2026-10-17, by request): Windows and
                // Android install from the clinic server, no store needed.
                if (DesktopUpdateChecker.isSupported)
                  SettingsSection(
                    icon: Icons.system_update_outlined,
                    color: const Color(0xFF6366F1),
                    title: t['profile.updates']!,
                    summary: _version == null ? '' : trf(t['profile.currentVersion']!, {'version': _version!}),
                    open: _open == 'updates',
                    onToggle: () => _toggle('updates'),
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _autoUpdate,
                        title: Text(t['profile.autoUpdate']!),
                        onChanged: (v) {
                          setState(() => _autoUpdate = v);
                          DesktopUpdateChecker.setAutoCheck(v);
                        },
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _checkingUpdates
                            ? null
                            : () async {
                                setState(() => _checkingUpdates = true);
                                await AppUpdateFlow.checkNow(context);
                                if (mounted) setState(() => _checkingUpdates = false);
                              },
                        icon: const Icon(Icons.refresh),
                        label: Text(t['profile.checkUpdates']!),
                      ),
                    ],
                  ),
                // Cloud or the clinic's offline server (2026-10-17).
                if (!kIsWeb)
                  InkWell(
                    onTap: () => context.push('/server'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          const SettingsSectionIcon(icon: Icons.dns_outlined, color: Color(0xFF64748B)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t['server.title']!, style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text(
                                  server.isClinic ? '${t['server.clinic']!} · ${server.host}' : t['server.cloud']!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_left, color: scheme.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                InkWell(
                  onTap: () => context.push('/sessions'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        const SettingsSectionIcon(icon: Icons.devices_outlined, color: Color(0xFF10B981)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t['profile.activeSessions']!, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(
                                t['profile.activeSessionsSubtitle']!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_left, color: scheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
