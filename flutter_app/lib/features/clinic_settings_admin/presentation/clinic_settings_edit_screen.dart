import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../data/clinic_settings_admin_repository.dart';
import '../domain/clinic_settings_admin.dart';
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
    if (!(_formKey.currentState?.validate() ?? true)) return;
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
    };

    try {
      await ref.read(clinicSettingsAdminRepositoryProvider).update(
            fields,
            clinicLogo: _clinicLogoPick,
            universityLogo: _universityLogoPick,
          );
      ref.invalidate(clinicSettingsAdminProvider);
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
        error: (error, stackTrace) => Center(
          child: Text(error is ApiException ? error.userMessage : t['clinicSettingsAdmin.loadFailed']!),
        ),
        data: (settings) {
          _seed(settings);
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(t['clinicSettingsAdmin.basicInfoHeading']!, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(labelText: t['clinicSettingsAdmin.clinicNameLabel'], border: const OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? t['clinicSettingsAdmin.requiredField'] : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  decoration: InputDecoration(labelText: t['clinicSettingsAdmin.descriptionLabel'], border: const OutlineInputBorder()),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                _LogoPicker(
                  label: t['clinicSettingsAdmin.clinicLogoLabel']!,
                  networkUrl: _current?.logoUrl,
                  previewBytes: _clinicLogoPreview,
                  onPick: _pickClinicLogo,
                ),
                const SizedBox(height: 24),
                Text(t['clinicSettingsAdmin.contactInfoHeading']!, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
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
                  decoration: InputDecoration(labelText: t['clinicSettingsAdmin.workingHoursLabel'], border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 24),
                Text(t['clinicSettingsAdmin.universityCollegeHeading']!, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _universityNameController,
                  decoration: InputDecoration(labelText: t['clinicSettingsAdmin.universityNameLabel'], border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _collegeNameController,
                  decoration: InputDecoration(labelText: t['clinicSettingsAdmin.collegeNameLabel'], border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                _LogoPicker(
                  label: t['clinicSettingsAdmin.universityLogoLabel']!,
                  networkUrl: _current?.universityLogoUrl,
                  previewBytes: _universityLogoPreview,
                  onPick: _pickUniversityLogo,
                ),
                const SizedBox(height: 24),
                Text(t['clinicSettingsAdmin.systemHeading']!, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _currencyController,
                  decoration: InputDecoration(labelText: t['clinicSettingsAdmin.currencyLabel'], border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: kClinicTimezones.any((tz) => tz.$1 == _timezone) ? _timezone : null,
                  decoration: InputDecoration(labelText: t['clinicSettingsAdmin.timezoneLabel'], border: const OutlineInputBorder()),
                  items: [for (final tz in kClinicTimezones) DropdownMenuItem(value: tz.$1, child: Text(tz.$2))],
                  onChanged: (v) => setState(() => _timezone = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _baseUrlController,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: t['clinicSettingsAdmin.baseUrlLabel'], border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 24),
                Text(t['clinicSettingsAdmin.notificationsHeading']!, style: Theme.of(context).textTheme.titleMedium),
                CheckboxListTile(
                  value: _enableNotifications,
                  title: Text(t['clinicSettingsAdmin.enableNotifications']!),
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (v) => setState(() => _enableNotifications = v ?? true),
                ),
                CheckboxListTile(
                  value: _enableSms,
                  title: Text(t['clinicSettingsAdmin.enableSms']!),
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (v) => setState(() => _enableSms = v ?? false),
                ),
                CheckboxListTile(
                  value: _enableEmail,
                  title: Text(t['clinicSettingsAdmin.enableEmail']!),
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (v) => setState(() => _enableEmail = v ?? true),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(t['clinicSettingsAdmin.saveSettings']!),
                ),
              ],
            ),
          );
        },
      ),
    );
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
              : (networkUrl != null
                  ? Image.network(networkUrl!, fit: BoxFit.contain)
                  : const Icon(Icons.image_outlined)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.upload_outlined),
            label: Text(label),
          ),
        ),
      ],
    );
  }
}
