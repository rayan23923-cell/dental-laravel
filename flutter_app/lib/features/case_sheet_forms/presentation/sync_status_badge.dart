import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/case_sheet_offline_store.dart';
import '../domain/case_sheet_sync_status.dart';

/// Per-record offline-sync indicator — shown in `CaseSheetFormScreen`'s
/// AppBar. Renders nothing once synced
/// (the common case), so it never adds visual noise to a record with no
/// offline history.
class SyncStatusBadge extends ConsumerWidget {
  const SyncStatusBadge({super.key, required this.resource, required this.id});
  final String resource;
  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(caseSheetPendingStatusProvider((resource, id))).valueOrNull;

    return switch (status) {
      null || CaseSheetSynced() => const SizedBox.shrink(),
      CaseSheetSyncPending() => Tooltip(
          message: 'بانتظار المزامنة مع الخادم',
          child: _Chip(
            icon: Icons.cloud_upload_outlined,
            label: 'بانتظار المزامنة',
            color: Theme.of(context).colorScheme.tertiary,
          ),
        ),
      CaseSheetSyncFailed(:final message) => Tooltip(
          message: message,
          child: _Chip(
            icon: Icons.warning_amber_rounded,
            label: 'فشلت المزامنة',
            color: Theme.of(context).colorScheme.error,
          ),
        ),
    };
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
