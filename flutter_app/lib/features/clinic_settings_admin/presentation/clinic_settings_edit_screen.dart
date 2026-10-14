import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/widgets/settings_list.dart';
import '../../../core/network/api_exception.dart';
import '../data/clinic_settings_admin_repository.dart';
import '../domain/clinic_settings_admin.dart';
import '../../clinic_settings/presentation/clinic_settings_providers.dart';
import 'clinic_settings_admin_providers.dart';

class ClinicSettingsEditScreen extends ConsumerStatefulWidget {
  const ClinicSettingsEditScreen({super.key});

  @override
  ConsumerState<ClinicSettingsEditScreen> createState() => _ClinicSettingsEditScreenState();
}

class _ClinicSettingsEditScreenState extends ConsumerState<ClinicSettingsEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _websiteController = TextEditingController();
  final _workingHoursController = TextEditingController();
  final _currencyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _universityNameController = TextEditingController();
  final _collegeNameController = TextEditingController();

  String? _timezone;
  bool _enableNotifications = true;
  bool _enableSms = false;
  bool _enableEmail = true;
  bool _groupsEnabled = true;
  String? _open;
  bool _seeded = false;
  bool _submitting = false;

  ClinicSettingsAdmin? _current;
  XFile? _clinicLogoPick;
  Uint8List? _clinicLogoPreview;
  XFile? _universityLogoPick;
  Uint8List? _universityLogoPreview;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _websiteController.dispose();
    _workingHoursController.dispose();
    _currencyController.dispose();
    _baseUrlController.dispose();
    _universityNameController.dispose();
    _collegeNameController.dispose();
    super.dispose();
  }

  void _seed(ClinicSettingsAdmin settings) {
    if (_seeded) return;
    _seeded = true;
    _current = settings;
    _nameController.text = settings.clinicName;
    _descriptionController.text = settings.clinicDescription ?? '';
    _addressController.text = settings.clinicAddress ?? '';
    _phoneController.text = settings.clinicPhone ?? '';
    _emailController.text = settings.clinicEmail ?? '';
    _websiteController.text = settings.clinicWebsite ?? '';
    _workingHoursController.text = settings.clinicWorkingHours ?? '';
    _currencyController.text = settings.clinicCurrency ?? '';
    _baseUrlController.text = settings.baseUrl ?? '';
    _universityNameController.text = settings.universityName ?? '';
    _collegeNameController.text = settings.collegeName ?? '';
    _timezone = settings.clinicTimezone;
    _enableNotifications = settings.enableNotifications;
    _enableSms = settings.enableSms;
    _enableEmail = settings.enableEmail;
    _groupsEnabled = settings.groupsEnabled;
  }

  Future<void> _pickClinicLogo() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _clinicLogoPick = file;
      _clinicLogoPreview = bytes;
    });
  }

  Future<void> _pickUniversityLogo() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _universityLogoPick = file;
      _universityLogoPreview = bytes;
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? true)) {
      // Only the basic section has validated fields (name, email).
      setState(() => _open = 'basic');
      return;
    }
    setState(() => _submitting = true);

    final fields = {
      'clinic_name': _nameController.text.trim(),
      'clinic_description': _descriptionController.text.trim(),
      'clinic_address': _addressController.text.trim(),
      'clinic_phone': _phoneController.text.trim(),
      'clinic_email': _emailController.text.trim(),
      'clinic_website': _websiteController.text.trim(),
      'clinic_working_hours': _workingHoursController.text.trim(),
      'clinic_currency': _currencyController.text.trim(),
      'clinic_timezone': _timezone,
      'base_url': _baseUrlController.text.trim(),
      'university_name': _universityNameController.text.trim(),
      'college_name': _collegeNameController.text.trim(),
      'enable_notifications': _enableNotifications,
      'enable_sms': _enableSms,
      'enable_email': _enableEmail,
      'groups_enabled': _groupsEnabled,
    };

    try {
      await ref
          .read(clinicSettingsAdminRepositoryProvider)
          .update(fields, clinicLogo: _clinicLogoPick, universityLogo: _universityLogoPick);
      ref.invalidate(clinicSettingsAdminProvider);
      // The app-wide copy (theme, groups switch) re-reads the saved values.
      ref.invalidate(clinicSettingsProvider);
      if (mounted) {
        final t = ref.read(translationsProvider);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['clinicSettingsAdmin.savedSuccess']!)));
        setState(() {
          _clinicLogoPick = null;
          _clinicLogoPreview = null;
          _universityLogoPick = null;
          _universityLogoPreview = null;
        });
      }
    } catch (e) {
      if (mounted) {
        final t = ref.read(translationsProvider);
        final message = e is ApiException ? e.userMessage : t['clinicSettingsAdmin.saveFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(clinicSettingsAdminProvider);
    final t = ref.watch(translationsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t['clinicSettingsAdmin.title']!)),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text(error is ApiException ? error.userMessage : t['clinicSettingsAdmin.loadFailed']!)),
        data: (settings) {
          _seed(settings);
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                SettingsGroupHeader(t['clinicSettingsAdmin.groupClinic']!),
                SettingsGroupCard(
                  children: [
                    SettingsSection(
                      icon: Icons.storefront_outlined,
                      color: const Color(0xFF6366F1),
                      title: t['clinicSettingsAdmin.basicInfoHeading']!,
                      summary: _join([_nameController.text, _phoneController.text]),
                      open: _open == 'basic',
                      onToggle: () => setState(() => _open = _open == 'basic' ? null : 'basic'),
                      children: [
                        TextFormField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: t['clinicSettingsAdmin.clinicNameLabel'],
                            border: const OutlineInputBorder(),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? t['clinicSettingsAdmin.requiredField'] : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _descriptionController,
                          decoration: InputDecoration(
                            labelText: t['clinicSettingsAdmin.descriptionLabel'],
                            border: const OutlineInputBorder(),
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 12),
                        _LogoPicker(
                          label: t['clinicSettingsAdmin.clinicLogoLabel']!,
                          networkUrl: _current?.logoUrl,
                          previewBytes: _clinicLogoPreview,
                          onPick: _pickClinicLogo,
                        ),
                      ],
                    ),
                    SettingsSection(
                      icon: Icons.contact_phone_outlined,
                      color: const Color(0xFF0EA5E9),
                      title: t['clinicSettingsAdmin.contactInfoHeading']!,
                      summary: _join([_addressController.text, _workingHoursController.text]),
                      open: _open == 'contact',
                      onToggle: () => setState(() => _open = _open == 'contact' ? null : 'contact'),
                      children: [
                        TextFormField(
                          controller: _addressController,
                          decoration: InputDecoration(labelText: t['clinicSettingsAdmin.addressLabel'], border: const OutlineInputBorder()),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 12),
                        // Forced LTR — confirmed live: typing "0770-CDP-TEST"
                        // displayed as "CDP-TEST-0770". Same bidi cause as the
                        // other fields above.
                        TextFormField(
                          controller: _phoneController,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(labelText: t['clinicSettingsAdmin.phoneLabel'], border: const OutlineInputBorder()),
                        ),
                        const SizedBox(height: 12),
                        // Forced LTR — same reasoning as the website/base_url
                        // fields below: an email address mixes strong-LTR letters
                        // with bidi-neutral `@`/`.` characters, the same shape that
                        // caused the base_url reordering.
                        TextFormField(
                          controller: _emailController,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(labelText: t['clinicSettingsAdmin.emailLabel'], border: const OutlineInputBorder()),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return null;
                            return v.contains('@') ? null : t['clinicSettingsAdmin.invalidEmail'];
                          },
                        ),
                        const SizedBox(height: 12),
                        // Forced LTR — a URL/path value shown inside an ambient-RTL
                        // field gets visually reordered otherwise (confirmed live
                        // on `base_url`: stored "/dental_clinic" rendered as
                        // "dental_clinic/", the leading "/" — a bidi-neutral
                        // character next to strong-LTR text — pushed to the visual
                        // end). Same root cause as every other bidi fix this
                        // session, here inside an editable field rather than a
                        // `Text`; the stored `TextEditingController.text` itself
                        // was never wrong, only the on-screen rendering.
                        TextFormField(
                          controller: _websiteController,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(labelText: t['clinicSettingsAdmin.websiteLabel'], border: const OutlineInputBorder()),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _workingHoursController,
                          decoration: InputDecoration(
                            labelText: t['clinicSettingsAdmin.workingHoursLabel'],
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                    SettingsSection(
                      icon: Icons.school_outlined,
                      color: const Color(0xFF8B5CF6),
                      title: t['clinicSettingsAdmin.universityCollegeHeading']!,
                      summary: _join([_universityNameController.text, _collegeNameController.text]),
                      open: _open == 'university',
                      onToggle: () => setState(() => _open = _open == 'university' ? null : 'university'),
                      children: [
                        TextFormField(
                          controller: _universityNameController,
                          decoration: InputDecoration(
                            labelText: t['clinicSettingsAdmin.universityNameLabel'],
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _collegeNameController,
                          decoration: InputDecoration(
                            labelText: t['clinicSettingsAdmin.collegeNameLabel'],
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _LogoPicker(
                          label: t['clinicSettingsAdmin.universityLogoLabel']!,
                          networkUrl: _current?.universityLogoUrl,
                          previewBytes: _universityLogoPreview,
                          onPick: _pickUniversityLogo,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SettingsGroupHeader(t['clinicSettingsAdmin.groupSystem']!),
                SettingsGroupCard(
                  children: [
                    SettingsSection(
                      icon: Icons.tune,
                      color: const Color(0xFFF59E0B),
                      title: t['clinicSettingsAdmin.systemHeading']!,
                      summary: _join([_currencyController.text, _timezoneLabel()]),
                      open: _open == 'system',
                      onToggle: () => setState(() => _open = _open == 'system' ? null : 'system'),
                      children: [
                        TextFormField(
                          controller: _currencyController,
                          decoration: InputDecoration(
                            labelText: t['clinicSettingsAdmin.currencyLabel'],
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: kClinicTimezones.any((tz) => tz.$1 == _timezone) ? _timezone : null,
                          decoration: InputDecoration(
                            labelText: t['clinicSettingsAdmin.timezoneLabel'],
                            border: const OutlineInputBorder(),
                          ),
                          items: [for (final tz in kClinicTimezones) DropdownMenuItem(value: tz.$1, child: Text(tz.$2))],
                          onChanged: (v) => setState(() => _timezone = v),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _baseUrlController,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(labelText: t['clinicSettingsAdmin.baseUrlLabel'], border: const OutlineInputBorder()),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SettingsSectionIcon(icon: Icons.groups_outlined, color: Color(0xFF14B8A6)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _groupsEnabled,
                              title: Text(t['clinicSettingsAdmin.groupsEnabled']!),
                              subtitle: Text(t['clinicSettingsAdmin.groupsNote']!, maxLines: 2, overflow: TextOverflow.ellipsis),
                              onChanged: (v) => setState(() => _groupsEnabled = v),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SettingsGroupHeader(t['clinicSettingsAdmin.groupMessaging']!),
                SettingsGroupCard(
                  children: [
                    SettingsSection(
                      icon: Icons.notifications_outlined,
                      color: const Color(0xFFF43F5E),
                      title: t['clinicSettingsAdmin.notificationsHeading']!,
                      summary: _notificationsSummary(t),
                      open: _open == 'notifications',
                      onToggle: () => setState(() => _open = _open == 'notifications' ? null : 'notifications'),
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _enableNotifications,
                          title: Text(t['clinicSettingsAdmin.enableNotifications']!),
                          onChanged: (v) => setState(() => _enableNotifications = v),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _enableSms,
                          title: Text(t['clinicSettingsAdmin.enableSms']!),
                          onChanged: (v) => setState(() => _enableSms = v),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _enableEmail,
                          title: Text(t['clinicSettingsAdmin.enableEmail']!),
                          onChanged: (v) => setState(() => _enableEmail = v),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
      // Save bar stays reachable whichever section is open.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _submitting || !settingsAsync.hasValue ? null : _submit,
            icon: _submitting
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: Text(t['clinicSettingsAdmin.saveSettings']!),
          ),
        ),
      ),
    );
  }

  String _join(List<String> parts) => parts.map((p) => p.trim()).where((p) => p.isNotEmpty).join(' · ');

  String _timezoneLabel() {
    for (final tz in kClinicTimezones) {
      if (tz.$1 == _timezone) return tz.$2;
    }
    return '';
  }

  String _notificationsSummary(Map<String, String> t) {
    final on = [
      if (_enableNotifications) t['clinicSettingsAdmin.enableNotifications']!,
      if (_enableSms) 'SMS',
      if (_enableEmail) t['clinicSettingsAdmin.emailShort']!,
    ];
    return on.isEmpty ? t['clinicSettingsAdmin.off']! : on.join('، ');
  }
}

class _LogoPicker extends StatelessWidget {
  const _LogoPicker({required this.label, required this.networkUrl, required this.previewBytes, required this.onPick});
  final String label;
  final String? networkUrl;
  final Uint8List? previewBytes;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: previewBytes != null
              ? Image.memory(previewBytes!, fit: BoxFit.contain)
              : (networkUrl != null ? Image.network(networkUrl!, fit: BoxFit.contain) : const Icon(Icons.image_outlined)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(onPressed: onPick, icon: const Icon(Icons.upload_outlined), label: Text(label)),
        ),
      ],
    );
  }
}
