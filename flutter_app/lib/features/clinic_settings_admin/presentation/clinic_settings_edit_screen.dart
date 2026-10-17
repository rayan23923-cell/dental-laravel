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
  // SMTP (2026-10-17, as on the web). The password field starts empty:
  // blank keeps the stored one, which the server never sends back.
  final _mailHostController = TextEditingController();
  final _mailPortController = TextEditingController();
  final _mailUsernameController = TextEditingController();
  final _mailPasswordController = TextEditingController();
  final _mailFromAddressController = TextEditingController();
  final _mailFromNameController = TextEditingController();
  final _testToController = TextEditingController();
  String? _mailEncryption;
  bool _sendingTest = false;

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
    _mailHostController.dispose();
    _mailPortController.dispose();
    _mailUsernameController.dispose();
    _mailPasswordController.dispose();
    _mailFromAddressController.dispose();
    _mailFromNameController.dispose();
    _testToController.dispose();
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
    _mailHostController.text = settings.mailHost ?? '';
    _mailPortController.text = settings.mailPort?.toString() ?? '';
    _mailUsernameController.text = settings.mailUsername ?? '';
    _mailFromAddressController.text = settings.mailFromAddress ?? '';
    _mailFromNameController.text = settings.mailFromName ?? '';
    _mailEncryption = settings.mailEncryption;
  }

  /// The web's "إرسال رسالة تجريبية": goes through the *saved* settings.
  Future<void> _sendTestEmail() async {
    final t = ref.read(translationsProvider);
    final to = _testToController.text.trim();
    if (to.isEmpty) return;
    setState(() => _sendingTest = true);
    try {
      final message = await ref.read(clinicSettingsAdminRepositoryProvider).sendTestEmail(to);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : t['clinicSettingsAdmin.saveFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _sendingTest = false);
    }
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
      // Validated fields live in the basic/contact sections and in mail;
      // open the basic one when the name is missing, else leave it be.
      if (_nameController.text.trim().isEmpty) setState(() => _open = 'basic');
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
      if (_current?.mailVisible ?? false) ...{
        'mail_host': _mailHostController.text.trim(),
        'mail_port': _mailPortController.text.trim(),
        'mail_username': _mailUsernameController.text.trim(),
        // Blank keeps the stored password (see the controller above).
        'mail_password': _mailPasswordController.text,
        'mail_encryption': _mailEncryption ?? '',
        'mail_from_address': _mailFromAddressController.text.trim(),
        'mail_from_name': _mailFromNameController.text.trim(),
      },
    };

    try {
      final saved = await ref
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
          _mailPasswordController.clear();
          // The saved copy: mail configured / password set, logo URLs.
          _current = saved;
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
                    if ((_current ?? settings).mailVisible) _mailSection(t, _current ?? settings),
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

  Widget _mailSection(Map<String, String> t, ClinicSettingsAdmin settings) {
    final configured = settings.mailConfigured;
    final statusColor = configured ? Colors.green : Colors.amber.shade800;
    return SettingsSection(
      icon: Icons.mail_outline,
      color: const Color(0xFF10B981),
      title: t['clinicSettingsAdmin.mailSectionHeading']!,
      summary: configured ? t['clinicSettingsAdmin.mailConfiguredShort']! : t['clinicSettingsAdmin.mailNotConfiguredShort']!,
      open: _open == 'mail',
      onToggle: () => setState(() => _open = _open == 'mail' ? null : 'mail'),
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(configured ? Icons.check_circle : Icons.warning_amber_outlined, color: statusColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  configured
                      ? t['clinicSettingsAdmin.mailConfiguredMsg']!
                      : '${t['clinicSettingsAdmin.mailNotConfiguredPrefix']!} (\u2066${settings.mailDriver ?? 'log'}\u2069) ${t['clinicSettingsAdmin.mailNotConfiguredSuffix']!}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(t['clinicSettingsAdmin.mailSectionDesc']!, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        // Hosts, ports, addresses: forced LTR (see the website field above).
        TextFormField(
          controller: _mailHostController,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: t['clinicSettingsAdmin.mailHostLabel'],
            hintText: 'smtp.gmail.com',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _mailPortController,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: t['clinicSettingsAdmin.mailPortLabel'],
                  hintText: '587',
                  border: const OutlineInputBorder(),
                ),
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.isEmpty) return null;
                  final port = int.tryParse(value);
                  return port == null || port < 1 || port > 65535 ? t['clinicSettingsAdmin.invalidPort'] : null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _mailEncryption == 'tls' || _mailEncryption == 'ssl' ? _mailEncryption : '',
                decoration: InputDecoration(
                  labelText: t['clinicSettingsAdmin.mailEncryptionLabel'],
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(value: '', child: Text(t['clinicSettingsAdmin.mailEncryptionNone']!)),
                  const DropdownMenuItem(value: 'tls', child: Text('TLS')),
                  const DropdownMenuItem(value: 'ssl', child: Text('SSL')),
                ],
                onChanged: (v) => setState(() => _mailEncryption = (v == null || v.isEmpty) ? null : v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _mailUsernameController,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(labelText: t['clinicSettingsAdmin.mailUsernameLabel'], border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _mailPasswordController,
          obscureText: true,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: t['clinicSettingsAdmin.mailPasswordLabel'],
            hintText: settings.mailPasswordSet ? t['clinicSettingsAdmin.mailPasswordPlaceholder'] : null,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _mailFromAddressController,
          textDirection: TextDirection.ltr,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: t['clinicSettingsAdmin.mailFromAddressLabel'],
            hintText: 'clinic@example.com',
            border: const OutlineInputBorder(),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return null;
            return v.contains('@') ? null : t['clinicSettingsAdmin.invalidEmail'];
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _mailFromNameController,
          decoration: InputDecoration(
            labelText: t['clinicSettingsAdmin.mailFromNameLabel'],
            hintText: _nameController.text,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(t['clinicSettingsAdmin.gmailHelperSummary']!, style: const TextStyle(fontSize: 14)),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${t['clinicSettingsAdmin.gmailWarningBold']!} ${t['clinicSettingsAdmin.gmailWarningRest']!}',
              style: TextStyle(color: Colors.amber.shade900, fontSize: 13),
            ),
            const SizedBox(height: 6),
            for (final line in [
              '${t['clinicSettingsAdmin.gmailServerLabel']!} \u2066smtp.gmail.com\u2069',
              '${t['clinicSettingsAdmin.gmailPortLabel']!} \u2066587\u2069 ${t['clinicSettingsAdmin.gmailWithEncryption']!} TLS (\u2066465\u2069 ${t['clinicSettingsAdmin.gmailWithConnector']!} SSL)',
              '${t['clinicSettingsAdmin.gmailUsernameLabel']!} ${t['clinicSettingsAdmin.gmailUsernameFullEmail']!} \u2066you@gmail.com\u2069',
              '${t['clinicSettingsAdmin.gmailPasswordLabel']!} ${t['clinicSettingsAdmin.gmailPasswordAppPassword']!}',
              '${t['clinicSettingsAdmin.gmailFromAddressLabel']!} ${t['clinicSettingsAdmin.gmailFromAddressBold']!} ${t['clinicSettingsAdmin.gmailFromAddressRest']!}',
              t['clinicSettingsAdmin.gmailLimitsNote']!,
            ])
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('• $line', style: const TextStyle(fontSize: 13)),
              ),
          ],
        ),
        const Divider(height: 24),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _testToController,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: t['clinicSettingsAdmin.testEmailLabel'],
                  hintText: 'you@example.com',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _sendingTest || _testToController.text.trim().isEmpty ? null : _sendTestEmail,
              child: Text(_sendingTest ? t['clinicSettingsAdmin.testEmailSending']! : t['clinicSettingsAdmin.testEmailSend']!),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(t['clinicSettingsAdmin.testEmailSaveFirstNote']!, style: Theme.of(context).textTheme.bodySmall),
      ],
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
