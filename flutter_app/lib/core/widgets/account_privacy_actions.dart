import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/profile/data/profile_repository.dart';
import '../config/app_config.dart';
import '../i18n/locale_controller.dart';
import '../network/api_exception.dart';

/// The privacy-policy link and the "delete my account" request both app
/// stores want reachable inside the app (2026-10-28). Used by the phone's
/// account sheet, the profile page and the login screen.

/// Opens one of the site's public pages (`privacy-policy`, `terms`,
/// `support`, `delete-account`) in the browser.
Future<void> openSitePage(BuildContext context, String path) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final url = AppConfig.sitePage(path);
  final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) => false);
  if (!opened) messenger?.showSnackBar(SnackBar(content: Text(url)));
}

/// Asks for confirmation (with an optional reason), then sends the request
/// to the clinic's administration; accounts here are theirs to delete.
Future<void> requestAccountDeletion(BuildContext context, WidgetRef ref) async {
  final t = ref.read(translationsProvider);
  final messenger = ScaffoldMessenger.of(context);
  final reason = TextEditingController();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t['account.deleteTitle']!),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t['account.deleteBody']!),
          const SizedBox(height: 12),
          TextField(
            controller: reason,
            maxLines: 2,
            decoration: InputDecoration(labelText: t['account.deleteReason']),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(t['nav.cancel']!)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(t['account.deleteSend']!),
        ),
      ],
    ),
  );
  final text = reason.text.trim();
  reason.dispose();
  if (confirmed != true) return;

  try {
    final message = await ref.read(profileRepositoryProvider).requestDeletion(reason: text);
    messenger.showSnackBar(SnackBar(content: Text(message.isNotEmpty ? message : t['account.deleteSent']!)));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e is ApiException ? e.userMessage : t['profile.saveFailed']!)));
  }
}
