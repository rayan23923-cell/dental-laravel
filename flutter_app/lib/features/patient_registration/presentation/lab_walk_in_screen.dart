import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/tg_spinner.dart';
import '../../records/domain/payment.dart' show formatMoney;
import '../data/patient_registration_repository.dart';
import '../domain/lab_service.dart';

/// «مريض للفحص فقط» (2026-11-17, by request): the lab registers a patient
/// who came for the test only, against one of its own services. The
/// patient stays off the reception list; the price goes to the lab
/// payments, now when «استلمت المبلغ» is ticked, otherwise with the
/// result. Pops with the new patient's `RegistrationPaymentState`, which
/// the lab list opens in the screening screen.
class LabWalkInScreen extends ConsumerStatefulWidget {
  const LabWalkInScreen({super.key, this.currency});

  final String? currency;

  @override
  ConsumerState<LabWalkInScreen> createState() => _LabWalkInScreenState();
}

class _LabWalkInScreenState extends ConsumerState<LabWalkInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _age = TextEditingController();
  List<LabService>? _services;
  int? _serviceId;
  bool _paid = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _age.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final (services, _) = await ref.read(patientRegistrationRepositoryProvider).listLabServices();
      final active = services.where((s) => s.active).toList();
      if (mounted) {
        setState(() {
          _services = active;
          if (active.length == 1) _serviceId = active.first.id;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.userMessage : ref.read(translationsProvider)['common.loadFailed']!);
    }
  }

  LabService? get _service => _services?.where((s) => s.id == _serviceId).firstOrNull;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final state = await ref.read(patientRegistrationRepositoryProvider).registerLabPatient(
            name: _name.text.trim(),
            phone: _phone.text.trim(),
            age: int.tryParse(_age.text.trim()),
            labServiceId: _serviceId!,
            paid: _paid && (_service?.price ?? 0) > 0,
          );
      if (mounted) Navigator.of(context).pop(state);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is ValidationException
            ? (e.firstError('lab_service_id') ?? e.firstError('name') ?? e.firstError('phone') ?? e.message)
            : e is ApiException
                ? e.userMessage
                : ref.read(translationsProvider)['labWalkIn.failed']!);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final services = _services;
    final service = _service;
    return Scaffold(
      appBar: AppBar(title: Text(t['labWalkIn.title']!)),
      body: services == null && _error == null
          ? const Center(child: TgSpinner())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(t['labWalkIn.hint']!, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 16),
                  if (services != null && services.isEmpty)
                    Card(
                      color: Colors.amber.shade50,
                      child: Padding(padding: const EdgeInsets.all(12), child: Text(t['labWalkIn.noServices']!)),
                    )
                  else if (services != null)
                    DropdownButtonFormField<int>(
                      initialValue: _serviceId,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: t['labWalkIn.service']!, border: const OutlineInputBorder()),
                      items: [
                        for (final s in services)
                          DropdownMenuItem(value: s.id, child: Text('${s.name} — ${formatMoney(s.price, widget.currency)}')),
                      ],
                      onChanged: (v) => setState(() => _serviceId = v),
                      validator: (v) => v == null ? t['labWalkIn.pick']! : null,
                    ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _name,
                    maxLength: 255,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(labelText: t['labWalkIn.name']!, border: const OutlineInputBorder()),
                    validator: (v) => (v ?? '').trim().isEmpty ? t['labWalkIn.required']! : null,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _phone,
                          maxLength: 20,
                          keyboardType: TextInputType.phone,
                          textDirection: TextDirection.ltr,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(labelText: t['labWalkIn.phone']!, border: const OutlineInputBorder()),
                          validator: (v) => (v ?? '').trim().isEmpty ? t['labWalkIn.required']! : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _age,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                          decoration: InputDecoration(labelText: t['labWalkIn.age']!, border: const OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  if (service != null && service.price > 0)
                    Card(
                      color: Colors.deepPurple.shade50,
                      child: CheckboxListTile(
                        value: _paid,
                        onChanged: (v) => setState(() => _paid = v ?? false),
                        title: Text(t['labWalkIn.paid']!.replaceAll('{amount}', formatMoney(service.price, widget.currency))),
                        subtitle: Text(t['labWalkIn.paidHint']!),
                      ),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
                    ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _saving || (services?.isEmpty ?? true) ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check),
                    label: Text(t['labWalkIn.save']!),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  ),
                ],
              ),
            ),
    );
  }
}
