import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../clinic_settings/data/clinic_settings_repository.dart';
import '../../clinic_settings/presentation/clinic_settings_providers.dart';
import '../data/patient_registration_repository.dart';
import '../domain/service.dart';
import 'patient_registration_providers.dart';
import '../../../core/widgets/numeric_input.dart';

/// "إعدادات التسجيل" — mirrors `PatientRegistrations/Settings.vue`:
/// services with a name and a price (the price pre-fills the registration
/// form's amount paid), plus the lab fee and how long a clear lab result
/// stays valid. The days and the day ↔ diagnosis mapping sections were
/// removed (2026-10-12) — registration no longer asks for a day; their
/// repository methods are kept. Admin-only — `permission:settings,edit`
/// server-side, same gate the web settings page uses.
class RegisterSettingsScreen extends ConsumerStatefulWidget {
  const RegisterSettingsScreen({super.key});

  @override
  ConsumerState<RegisterSettingsScreen> createState() => _RegisterSettingsScreenState();
}

/// Plain (ungrouped) number for an editable price field, so it parses back.
String _plainAmount(double v) => v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

/// Empty → null (no price); otherwise must be a non-negative number. The
/// outer null means "invalid".
({double? value})? _parsePrice(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return (value: null);
  final n = double.tryParse(trimmed);
  return (n == null || n < 0) ? null : (value: n);
}

/// Student discount percentage (2026-10-25): empty → 50 (the default),
/// otherwise 0–100; null means invalid.
double? _parsePercent(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return 50;
  final n = double.tryParse(trimmed);
  return (n == null || n < 0 || n > 100) ? null : n;
}

class _RegisterSettingsScreenState extends ConsumerState<RegisterSettingsScreen> {
  final _serviceNameController = TextEditingController();
  final _servicePriceController = TextEditingController();
  final _serviceDiscountController = TextEditingController(text: '50');
  final _labFeeController = TextEditingController();
  final _labDiscountController = TextEditingController(text: '50');
  final _labValidityController = TextEditingController();
  bool _addingService = false;
  bool _labLoading = true;
  bool _savingLab = false;

  @override
  void initState() {
    super.initState();
    _loadLab();
  }

  @override
  void dispose() {
    _serviceNameController.dispose();
    _servicePriceController.dispose();
    _serviceDiscountController.dispose();
    _labFeeController.dispose();
    _labDiscountController.dispose();
    _labValidityController.dispose();
    super.dispose();
  }

  void _showError(Object e, String fallbackKey) {
    if (!mounted) return;
    final t = ref.read(translationsProvider);
    final message = e is ApiException ? e.userMessage : t[fallbackKey]!;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showMessage(String key) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.read(translationsProvider)[key]!)));
  }

  /// Fetched fresh (not from `clinicSettingsProvider`, which keeps its
  /// first response for the whole session and swallows errors).
  Future<void> _loadLab() async {
    try {
      final settings = await ref.read(clinicSettingsRepositoryProvider).fetch();
      if (!mounted) return;
      _labFeeController.text = settings.labFee == null ? '' : _plainAmount(settings.labFee!);
      _labValidityController.text = '${settings.labValidityDays}';
      _labDiscountController.text = _plainAmount(settings.labStudentDiscountPercent);
    } catch (e) {
      _showError(e, 'common.loadFailed');
    } finally {
      if (mounted) setState(() => _labLoading = false);
    }
  }

  Future<void> _saveLab() async {
    final fee = _parsePrice(_labFeeController.text);
    if (fee == null) {
      _showMessage('registerSettings.priceInvalid');
      return;
    }
    final daysText = _labValidityController.text.trim();
    final days = daysText.isEmpty ? 0 : int.tryParse(daysText);
    if (days == null || days < 0) {
      _showMessage('registerSettings.labValidityInvalid');
      return;
    }
    final discount = _parsePercent(_labDiscountController.text);
    if (discount == null) {
      _showMessage('registerSettings.discountInvalid');
      return;
    }
    setState(() => _savingLab = true);
    try {
      await ref
          .read(clinicSettingsRepositoryProvider)
          .updateLab(labFee: fee.value, labValidityDays: days, labStudentDiscountPercent: discount);
      ref.invalidate(clinicSettingsProvider);
      _showMessage('registerSettings.saved');
    } catch (e) {
      _showError(e, 'profile.saveFailed');
    } finally {
      if (mounted) setState(() => _savingLab = false);
    }
  }

  Future<void> _addService() async {
    if (_serviceNameController.text.trim().isEmpty) return;
    final price = _parsePrice(_servicePriceController.text);
    if (price == null) {
      _showMessage('registerSettings.priceInvalid');
      return;
    }
    final discount = _parsePercent(_serviceDiscountController.text);
    if (discount == null) {
      _showMessage('registerSettings.discountInvalid');
      return;
    }
    setState(() => _addingService = true);
    try {
      await ref
          .read(patientRegistrationRepositoryProvider)
          .createService(_serviceNameController.text.trim(), price: price.value, studentDiscountPercent: discount);
      _serviceNameController.clear();
      _servicePriceController.clear();
      _serviceDiscountController.text = '50';
      ref.invalidate(servicesProvider);
      _showMessage('registerSettings.serviceAdded');
    } catch (e) {
      _showError(e, 'profile.saveFailed');
    } finally {
      if (mounted) setState(() => _addingService = false);
    }
  }

  Future<void> _editService(Service service) async {
    final result = await showDialog<({String name, double? price, double discount})>(
      context: context,
      builder: (_) => _ServiceDialog(service: service),
    );
    if (result == null) return;
    try {
      // The service's current days are passed through so the edit does
      // not clear them server-side (see `updateService`).
      await ref.read(patientRegistrationRepositoryProvider).updateService(
            service.id,
            result.name,
            price: result.price,
            studentDiscountPercent: result.discount,
            dayIds: service.days.map((d) => d.id).toList(),
          );
      ref.invalidate(servicesProvider);
      _showMessage('registerSettings.serviceUpdated');
    } catch (e) {
      _showError(e, 'profile.saveFailed');
    }
  }

  Future<void> _deleteService(Service service) async {
    try {
      await ref.read(patientRegistrationRepositoryProvider).deleteService(service.id);
      ref.invalidate(servicesProvider);
    } catch (e) {
      _showError(e, 'registerSettings.deleteFailed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final servicesAsync = ref.watch(servicesProvider);
    final t = ref.watch(translationsProvider);
    final priceFormat = NumberFormat('#,##0.##');

    return Scaffold(
      appBar: AppBar(title: Text(t['registerSettings.title']!)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(t['registerSettings.servicesHeading']!, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _serviceNameController,
            decoration: InputDecoration(labelText: t['registerSettings.serviceNameLabel']!, border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _servicePriceController,
            textDirection: TextDirection.ltr,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: decimalOnly,
            decoration: InputDecoration(labelText: t['registerSettings.priceLabel']!, border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _serviceDiscountController,
            textDirection: TextDirection.ltr,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: decimalOnly,
            decoration: InputDecoration(
              labelText: t['registerSettings.studentDiscountLabel']!,
              helperText: t['registerSettings.studentDiscountHint']!,
              helperMaxLines: 2,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _addingService ? null : _addService,
            child: Text(t['registerSettings.addService']!),
          ),
          const SizedBox(height: 16),
          servicesAsync.when(
            loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
            error: (error, _) => Text(error is ApiException ? error.userMessage : t['common.loadFailed']!),
            data: (services) => Column(
              children: [
                for (final service in services)
                  Card(
                    child: ListTile(
                      title: Text(service.name),
                      subtitle: Text(
                        '${service.price == null ? t['registerSettings.noPrice']! : priceFormat.format(service.price)}'
                        ' · ${t['registerSettings.studentDiscountShort']!} ${priceFormat.format(service.studentDiscountPercent)}%',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: t['registerSettings.editService']!,
                            onPressed: () => _editService(service),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _deleteService(service),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (services.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(t['registerSettings.noServicesYet']!)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          // Lab fee + result validity (2026-10-12) — stored in clinic
          // settings, see `ClinicSettingsRepository.updateLab`.
          Text(t['registerSettings.labHeading']!, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_labLoading)
            const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator())
          else ...[
            TextField(
              controller: _labFeeController,
              textDirection: TextDirection.ltr,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: decimalOnly,
              decoration: InputDecoration(
                labelText: t['registerSettings.labFeeLabel']!,
                helperText: t['registerSettings.labFeeHint']!,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _labValidityController,
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.number,
              inputFormatters: digitsOnly,
              decoration: InputDecoration(
                labelText: t['registerSettings.labValidityLabel']!,
                helperText: t['registerSettings.labValidityHint']!,
                helperMaxLines: 3,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _labDiscountController,
              textDirection: TextDirection.ltr,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: decimalOnly,
              decoration: InputDecoration(
                labelText: t['registerSettings.studentDiscountLabel']!,
                helperText: t['registerSettings.studentDiscountHint']!,
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _savingLab ? null : _saveLab,
              child: _savingLab
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(t['profile.saveChanges']!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Edit a service's name, price and student discount; pops
/// `(name, price, discount)` or null.
class _ServiceDialog extends ConsumerStatefulWidget {
  const _ServiceDialog({required this.service});

  final Service service;

  @override
  ConsumerState<_ServiceDialog> createState() => _ServiceDialogState();
}

class _ServiceDialogState extends ConsumerState<_ServiceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.service.name);
  late final _priceController =
      TextEditingController(text: widget.service.price == null ? '' : _plainAmount(widget.service.price!));
  late final _discountController = TextEditingController(text: _plainAmount(widget.service.studentDiscountPercent));

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop((
      name: _nameController.text.trim(),
      price: _parsePrice(_priceController.text)!.value,
      discount: _parsePercent(_discountController.text)!,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    return AlertDialog(
      title: Text(t['registerSettings.editService']!),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(labelText: t['registerSettings.serviceNameLabel']!, border: const OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? t['profile.requiredField']! : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _priceController,
              textDirection: TextDirection.ltr,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: decimalOnly,
              decoration: InputDecoration(labelText: t['registerSettings.priceLabel']!, border: const OutlineInputBorder()),
              validator: (v) => _parsePrice(v ?? '') == null ? t['registerSettings.priceInvalid']! : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _discountController,
              textDirection: TextDirection.ltr,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: decimalOnly,
              decoration: InputDecoration(labelText: t['registerSettings.studentDiscountLabel']!, border: const OutlineInputBorder()),
              validator: (v) => _parsePercent(v ?? '') == null ? t['registerSettings.discountInvalid']! : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t['nav.cancel']!)),
        FilledButton(onPressed: _save, child: Text(t['profile.saveChanges']!)),
      ],
    );
  }
}
