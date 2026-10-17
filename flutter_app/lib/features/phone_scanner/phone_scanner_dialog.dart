import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/locale_controller.dart';
import '../../core/network/api_exception.dart';
import 'phone_scanner_pairing.dart';

/// Links a phone to this computer (or reuses the linked one) and shows its
/// QR and code until the phone opens it — for screens that use the phone
/// without a QR scanner open, like the paper-photos sheet's "from the
/// phone" (2026-10-17, the web's `PhoneScannerLink` there). Resolves to
/// the pairing, or null when it could not be opened or was ended here.
Future<PhoneScannerSession?> showPhoneScannerPairDialog(BuildContext context, WidgetRef ref) async {
  final pairing = ref.read(phoneScannerPairingProvider);
  PhoneScannerSession? session;
  try {
    session = await pairing.saved() ?? await pairing.open();
  } on ApiException catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.userMessage)));
    return null;
  }
  if (!context.mounted) return session;
  return showDialog<PhoneScannerSession?>(
    context: context,
    builder: (_) => _PairDialog(initial: session!),
  );
}

class _PairDialog extends ConsumerStatefulWidget {
  const _PairDialog({required this.initial});
  final PhoneScannerSession initial;

  @override
  ConsumerState<_PairDialog> createState() => _PairDialogState();
}

class _PairDialogState extends ConsumerState<_PairDialog> {
  late PhoneScannerSession? _session = widget.initial;
  Timer? _timer;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _check());
    _check();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    final session = _session;
    if (session == null || _checking) return;
    _checking = true;
    try {
      final fresh = await ref.read(phoneScannerPairingProvider).refresh(session);
      if (!mounted) return;
      setState(() => _session = fresh);
      // Joined: nothing left to show, hand it back.
      if (fresh != null && fresh.phoneJoined) {
        _timer?.cancel();
        Navigator.of(context).pop(fresh);
      }
    } catch (_) {
      // Offline for a moment: the next tick tries again.
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final session = _session;
    return AlertDialog(
      title: Text(t['phoneScanner.title']!, textAlign: TextAlign.center),
      content: session == null
          ? Text(t['phoneScanner.ended']!)
          : SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t['phoneScanner.howTo']!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  Image.memory(Uint8List.fromList(session.qrPng), width: 200, height: 200),
                  const SizedBox(height: 8),
                  Text(t['phoneScanner.orCode']!, style: Theme.of(context).textTheme.bodySmall),
                  SelectableText(
                    session.code,
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, letterSpacing: 8, fontFamily: 'monospace'),
                  ),
                  SelectableText(session.enterUrl, textDirection: TextDirection.ltr, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(t['phoneScanner.waiting']!)),
                    ],
                  ),
                ],
              ),
            ),
      actions: [
        FilledButton(onPressed: () => Navigator.of(context).pop(session), child: Text(t['common.close']!)),
      ],
    );
  }
}
