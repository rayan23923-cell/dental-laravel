import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/tg_spinner.dart';
import '../../records/domain/payment.dart' show formatMoney;
import '../data/patient_registration_repository.dart';
import '../domain/lab_service.dart';

/// «خدمات المختبر» (2026-11-17, by request) — the web lab page's
/// services window in the app: the lab's own priced services, such as
/// «فحص المختبر» for 2,000. Add, rename, price, switch off, delete; a
/// service with patients is switched off instead of deleted.
class LabServicesScreen extends ConsumerStatefulWidget {
  const LabServicesScreen({super.key, this.currency});

  final String? currency;

  @override
  ConsumerState<LabServicesScreen> createState() => _LabServicesScreenState();
}

class _LabServicesScreenState extends ConsumerState<LabServicesScreen> {
  List<LabService>? _services;
  LabServiceAbilities _abilities = const LabServiceAbilities();
  String? _error;
  bool _busy = false;

  PatientRegistrationRepository get _repo => ref.read(patientRegistrationRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (services, abilities) = await _repo.listLabServices();
      if (mounted) {
        setState(() {
          _services = services;
          _abilities = abilities;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.userMessage : ref.read(translationsProvider)['common.loadFailed']!);
    }
  }

  Future<void> _run(Future<List<LabService>> Function() action, {String? done}) async {
    setState(() => _busy = true);
    try {
      final services = await action();
      if (!mounted) return;
      setState(() => _services = services);
      if (done != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (mounted) {
        final t = ref.read(translationsProvider);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is ValidationException
              ? (e.firstError('name') ?? e.firstError('price') ?? e.message)
              : e is ApiException
                  ? e.userMessage
                  : t['labServices.saveFailed']!),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([LabService? service]) async {
    final t = ref.read(translationsProvider);
    final name = TextEditingController(text: service?.name ?? '');
    final price = TextEditingController(text: service == null ? '' : service.price.toStringAsFixed(service.price % 1 == 0 ? 0 : 2));
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(service == null ? t['labServices.add']! : t['labServices.edit']!),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                autofocus: true,
                maxLength: 100,
                decoration: InputDecoration(labelText: t['labServices.name']!),
                validator: (v) => (v ?? '').trim().isEmpty ? t['labServices.nameRequired']! : null,
              ),
              TextFormField(
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: t['labServices.price']!, suffixText: widget.currency),
                validator: (v) => double.tryParse((v ?? '').trim()) == null ? t['labServices.priceRequired']! : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t['labServices.cancel']!)),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(context, true);
            },
            child: Text(t['labServices.save']!),
          ),
        ],
      ),
    );
    if (saved != true) return;
    await _run(() => _repo.saveLabService(id: service?.id, name: name.text.trim(), price: double.parse(price.text.trim())));
  }

  Future<void> _delete(LabService service) async {
    final t = ref.read(translationsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(t['labServices.deleteConfirm']!.replaceAll('{name}', service.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t['labServices.cancel']!)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t['labServices.delete']!),
          ),
        ],
      ),
    );
    if (ok != true) return;
    String? message;
    await _run(() async {
      final (services, msg) = await _repo.deleteLabService(service.id);
      message = msg;
      return services;
    });
    if (mounted && message != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message!)));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final services = _services;
    return Scaffold(
      appBar: AppBar(title: Text(t['labServices.title']!)),
      floatingActionButton: _abilities.manage
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : () => _edit(),
              icon: const Icon(Icons.add),
              label: Text(t['labServices.add']!),
            )
          : null,
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(t['labServices.hint']!, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: _error != null
                ? Center(child: Text(_error!))
                : services == null
                    ? const Center(child: TgSpinner())
                    : services.isEmpty
                        ? Center(child: Text(t['labServices.empty']!))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.only(bottom: 88),
                              itemCount: services.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, i) => _tile(services[i], t),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _tile(LabService s, Map<String, String> t) {
    final details = [
      formatMoney(s.price, widget.currency),
      s.active ? t['labServices.active']! : t['labServices.inactive']!,
      if (s.patients > 0) t['labServices.patients']!.replaceAll('{n}', '${s.patients}'),
    ].join(' · ');
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: s.active ? Colors.deepPurple.shade50 : Colors.grey.shade200,
        child: Icon(Icons.biotech_outlined, color: s.active ? Colors.deepPurple : Colors.grey),
      ),
      title: Text(s.name, style: TextStyle(color: s.active ? null : Colors.grey)),
      subtitle: Text(details),
      onTap: _abilities.manage && !_busy ? () => _edit(s) : null,
      trailing: _abilities.manage
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: s.active,
                  onChanged: _busy ? null : (v) => _run(() => _repo.saveLabService(id: s.id, name: s.name, price: s.price, active: v)),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.red.shade700),
                  tooltip: t['labServices.delete']!,
                  onPressed: _busy ? null : () => _delete(s),
                ),
              ],
            )
          : null,
    );
  }
}
