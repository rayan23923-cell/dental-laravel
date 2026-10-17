import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';

final _recipientCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final data = await ref.watch(apiClientProvider).getJson('/admin-broadcast') as Map<String, dynamic>;
  return ((data['data'] as Map<String, dynamic>)['recipient_count'] as num?)?.toInt() ?? 0;
});

/// "إرسال تنبيه للموظفين" (2026-10-17) — the web's `AdminBroadcast/Create`:
/// one alert to every staff member, through the in-app inbox (and email
/// when enabled in clinic settings). Asks before sending, as the web does.
class AdminBroadcastScreen extends ConsumerStatefulWidget {
  const AdminBroadcastScreen({super.key});

  @override
  ConsumerState<AdminBroadcastScreen> createState() => _AdminBroadcastScreenState();
}

class _AdminBroadcastScreenState extends ConsumerState<AdminBroadcastScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send(int count) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final t = ref.read(translationsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(trf(t['adminBroadcast.confirmTemplate']!, {'count': '$count'})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t['nav.cancel']!)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t['adminBroadcast.sendButton']!)),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _sending = true);
    try {
      final data = await ref.read(apiClientProvider).postJson('/admin-broadcast', body: {
        'title': _title.text.trim(),
        'body': _body.text.trim(),
      }) as Map<String, dynamic>;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message'] as String? ?? t['adminBroadcast.sent']!)));
      _title.clear();
      _body.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.userMessage : t['adminBroadcast.failed']!)),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final count = ref.watch(_recipientCountProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(t['adminBroadcast.title']!)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              trf(t['adminBroadcast.description']!, {'count': count == null ? '…' : '$count'}),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _title,
              maxLength: 100,
              decoration: InputDecoration(labelText: t['adminBroadcast.titleLabel'], border: const OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? t['clinicSettingsAdmin.requiredField'] : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _body,
              maxLength: 2000,
              minLines: 4,
              maxLines: 10,
              decoration: InputDecoration(labelText: t['adminBroadcast.bodyLabel'], border: const OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? t['clinicSettingsAdmin.requiredField'] : null,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _sending || count == null ? null : () => _send(count),
              icon: _sending
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.campaign_outlined),
              label: Text(t['adminBroadcast.sendButton']!),
            ),
          ],
        ),
      ),
    );
  }
}
