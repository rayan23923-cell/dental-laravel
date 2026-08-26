import 'dart:async';

import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';

/// Reads a physical NFC tag's hardware UID (formatted uppercase hex, no
/// separators — the same normalization the backend applies, see
/// `DoctorController::validateDoctor()`'s docblock) rather than writing/
/// reading custom NDEF data — works with read-only/factory tags, no
/// provisioning step beyond "tap once." Shared between doctor NFC-tag
/// enrollment (`doctors_admin`) and the staff NFC lookup screen
/// (`task_progress_admin`) — same read operation, two different callers.
///
/// `NfcTagAndroid.from(tag)` (not a specific tech class like `NfcAAndroid`)
/// is used because it exposes the tag's raw `id` regardless of which NFC
/// standard the physical tag speaks — no need to try each tech class in
/// turn.
class NfcUidReader {
  const NfcUidReader._();

  static Future<String> readUid({Duration timeout = const Duration(seconds: 20)}) async {
    final availability = await NfcManager.instance.checkAvailability();
    if (availability != NfcAvailability.enabled) {
      throw Exception('قارئ NFC غير متاح أو غير مفعّل على هذا الجهاز.');
    }

    final completer = Completer<String>();

    await NfcManager.instance.startSession(
      pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693, NfcPollingOption.iso18092},
      onDiscovered: (NfcTag tag) async {
        final id = NfcTagAndroid.from(tag)?.id;
        await NfcManager.instance.stopSession();

        if (id == null || id.isEmpty) {
          if (!completer.isCompleted) completer.completeError(Exception('تعذرت قراءة رقم البطاقة.'));
          return;
        }

        final hex = id.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
        if (!completer.isCompleted) completer.complete(hex);
      },
    );

    return completer.future.timeout(
      timeout,
      onTimeout: () async {
        await NfcManager.instance.stopSession();
        throw Exception('انتهت مهلة المسح — قرّب البطاقة من الجهاز وحاول مجدداً.');
      },
    );
  }
}
