import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `intl` exports its own `TextDirection` (LTR/RTL/UNKNOWN, for bidi text
// detection) that collides with `dart:ui`'s `TextDirection` used by
// `Directionality` below — hidden here rather than prefixing every
// `DateFormat` reference.
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/chat_list_tile.dart';
import '../data/backup_admin_repository.dart';
import '../domain/backup_status.dart';
import 'backup_admin_providers.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _creating = false;
  bool _togglingAuto = false;

  Future<void> _createBackup() async {
    setState(() => _creating = true);
    try {
      await ref.read(backupAdminRepositoryProvider).createBackup();
      ref.invalidate(backupStatusProvider);
      if (mounted) {
        final t = ref.read(translationsProvider);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['backupAdmin.createdSuccess']!)));
      }
    } catch (e) {
      if (mounted) {
        final t = ref.read(translationsProvider);
        final message = e is ApiException ? e.userMessage : t['backupAdmin.createFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _toggleAuto(bool value) async {
    setState(() => _togglingAuto = true);
    try {
      await ref.read(backupAdminRepositoryProvider).setAutoEnabled(value);
      ref.invalidate(backupStatusProvider);
    } catch (e) {
      if (mounted) {
        final t = ref.read(translationsProvider);
        final message = e is ApiException ? e.userMessage : t['backupAdmin.updateFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _togglingAuto = false);
    }
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    return '${value.toStringAsFixed(unitIndex == 0 ? 0 : 2)} ${units[unitIndex]}';
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(backupStatusProvider);
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
    final t = ref.watch(translationsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t['backupAdmin.title']!)),
      body: statusAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text(error is ApiException ? error.userMessage : t['backupAdmin.loadFailed']!),
        ),
        data: (status) {
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(backupStatusProvider),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        status.lastBackupAt != null
                            ? trf(t['backupAdmin.lastBackupAt']!, {'date': dateFormat.format(status.lastBackupAt!)})
                            : t['backupAdmin.noPreviousBackup']!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: status.enabled,
                        onChanged: _togglingAuto ? null : _toggleAuto,
                        title: Text(t['backupAdmin.enableDailyAuto']!),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _creating ? null : _createBackup,
                        icon: _creating
                            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.backup_outlined),
                        label: Text(_creating ? t['backupAdmin.creating']! : t['backupAdmin.createNow']!),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          t['backupAdmin.scheduleNote']!,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(t['backupAdmin.recentBackupsHeading']!, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      if (status.files.isEmpty) Text(t['backupAdmin.emptyList']!),
                    ],
                  ),
                ),
                // Chat-list style (2026-10-13, by request): backup files as
                // divided chat rows instead of cards.
                for (final (i, file) in status.files.indexed) ...[
                  if (i > 0) chatDivider,
                  _BackupFileTile(file: file, formatSize: _formatSize, dateFormat: dateFormat),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BackupFileTile extends ConsumerStatefulWidget {
  const _BackupFileTile({required this.file, required this.formatSize, required this.dateFormat});
  final BackupFile file;
  final String Function(int) formatSize;
  final DateFormat dateFormat;

  @override
  ConsumerState<_BackupFileTile> createState() => _BackupFileTileState();
}

class _BackupFileTileState extends ConsumerState<_BackupFileTile> {
  bool _downloading = false;

  /// The web's backup.download (2026-10-17): saves the file on this
  /// device, then shows where (and opens the folder on a computer).
  Future<void> _download() async {
    final t = ref.read(translationsProvider);
    setState(() => _downloading = true);
    try {
      final path = await ref.read(backupAdminRepositoryProvider).download(widget.file);
      if (!mounted) return;
      final revealed = BackupAdminRepository.canReveal && await BackupAdminRepository.reveal(path);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t['backupAdmin.downloadedTitle']!),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(revealed ? t['backupAdmin.downloadedOpened']! : t['backupAdmin.downloadedAt']!),
              const SizedBox(height: 8),
              SelectableText(path, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: path)),
              child: Text(t['backupAdmin.copyPath']!),
            ),
            FilledButton(onPressed: () => Navigator.pop(context), child: Text(t['paperPhotos.close']!)),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : t['backupAdmin.downloadFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final file = widget.file;
    final formatSize = widget.formatSize;
    final dateFormat = widget.dateFormat;
    // Chat-list row (2026-10-13, by request). The file name and the size /
    // date chips are LTR-isolated: LTR-ish values have no strong-direction
    // anchor inside RTL text (see permission_edit_screen.dart).
    return ChatListTile(
      title: '\u2066${file.name}\u2069',
      color: Colors.indigo,
      icon: Icons.inventory_2_outlined,
      chips: [
        ChatChip(label: '\u2066${formatSize(file.size)}\u2069', icon: Icons.sd_storage_outlined, color: Colors.teal),
        ChatChip(label: '\u2066${dateFormat.format(file.mtime)}\u2069', icon: Icons.schedule, color: Colors.blueGrey),
      ],
      actions: [
        if (BackupAdminRepository.canDownload)
          _downloading
              ? const Padding(
                  padding: EdgeInsetsDirectional.only(end: 12),
                  child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(
                  tooltip: t['backupAdmin.download']!,
                  icon: const Icon(Icons.download_outlined),
                  onPressed: _download,
                ),
      ],
    );
  }
}
