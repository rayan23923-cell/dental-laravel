import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/locale_controller.dart';
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
