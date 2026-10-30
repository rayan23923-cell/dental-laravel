import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/locale_controller.dart';
import '../utils/case_code.dart';
import 'qr_image.dart';

/// Shared "show this QR in a modal" pattern (2026-08-27) — mirrors the web
/// app's `SectionedForm.vue` "رمز القR" button → "رمز الحالة" modal.
/// Generalized over [imagePath] (rather than hardcoding a task-instance id)
/// so the same dialog serves both the per-instance QR
/// (`/task-instances/{id}/qr`) and the per-pending-task QR
/// (`/pending-tasks/{id}/qr`) from one place.
Future<void> showQrDialog(
  BuildContext context, {
  required String imagePath,
  required String title,
  String? caption,
  // The typeable case code under the QR (2026-10-30, by request) — see
  // `CaseCode`; a supervisor types it when the camera can't read the QR.
  String? code,
}) {
  final t = ProviderScope.containerOf(context).read(translationsProvider);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          QrImage(path: imagePath),
          if (code != null) ...[
            const SizedBox(height: 10),
            Text(t['caseCode.manualLabel']!, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            SelectableText(
              CaseCode.format(code),
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 3, fontFamily: 'monospace'),
            ),
          ],
          if (caption != null) ...[
            const SizedBox(height: 12),
            Text(caption, textAlign: TextAlign.center),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t['common.close']!)),
      ],
    ),
  );
}
