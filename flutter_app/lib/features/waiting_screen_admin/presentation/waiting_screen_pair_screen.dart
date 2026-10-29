import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lookup_repository.dart';
import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../data/waiting_screen_admin_repository.dart';
import '../../../core/widgets/tg_spinner.dart';

final _pairingStagesProvider = FutureProvider.autoDispose<List<LookupItem>>((ref) {
  return ref.watch(lookupRepositoryProvider).stages();
});

/// "ربط شاشة انتظار" (2026-10-17) — the web's `WaitingScreenPairing/Enter`:
/// type the 4-digit code the TV shows, choose the stage it should display,
/// and activate it. Open to any signed-in staff member, as on the web.
class WaitingScreenPairScreen extends ConsumerStatefulWidget {
  const WaitingScreenPairScreen({super.key});

  @override
  ConsumerState<WaitingScreenPairScreen> createState() => _WaitingScreenPairScreenState();
}

class _WaitingScreenPairScreenState extends ConsumerState<WaitingScreenPairScreen> {
  final _code = TextEditingController();
  int? _stageId;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final t = ref.read(translationsProvider);
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(waitingScreenAdminRepositoryProvider).pair(code: _code.text.trim(), stageId: _stageId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['waitingScreenPairing.success']!)));
      _code.clear();
    } on ServerException catch (e) {
      // 404: wrong or expired code; 410: the screen's code went stale.
      if (mounted) setState(() => _error = e.statusCode == 404 || e.statusCode == 410 ? e.message : e.userMessage);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.userMessage);
    } catch (_) {
      if (mounted) setState(() => _error = t['waitingScreenPairing.failed']!);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final stages = ref.watch(_pairingStagesProvider).valueOrNull ?? const <LookupItem>[];
    final ready = _code.text.trim().length == 4 && !_submitting;

    return Scaffold(
      appBar: AppBar(title: Text(t['waitingScreenPairing.title']!)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Icon(Icons.connected_tv_outlined, size: 56),
          const SizedBox(height: 12),
          Text(t['waitingScreenPairing.description']!, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 32, letterSpacing: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
            decoration: InputDecoration(
              labelText: t['waitingScreenPairing.codeLabel'],
              border: const OutlineInputBorder(),
              errorText: _error,
              errorMaxLines: 3,
            ),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => ready ? _confirm() : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            initialValue: _stageId,
            isExpanded: true,
            decoration: InputDecoration(labelText: t['waitingScreenPairing.stageLabel'], border: const OutlineInputBorder()),
            items: [
              DropdownMenuItem<int?>(value: null, child: Text(t['waitingScreenPairing.allStages']!)),
              for (final s in stages) DropdownMenuItem<int?>(value: s.id, child: Text(s.name)),
            ],
            onChanged: (v) => setState(() => _stageId = v),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: ready ? _confirm : null,
            icon: _submitting
                ? const SizedBox(height: 18, width: 18, child: TgSpinner(strokeWidth: 2))
                : const Icon(Icons.check),
            label: Text(t['waitingScreenPairing.confirm']!),
          ),
        ],
      ),
    );
  }
}
