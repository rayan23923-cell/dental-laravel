import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `intl` exports its own `TextDirection` (LTR/RTL/UNKNOWN, for bidi text
// detection) that collides with `dart:ui`'s `TextDirection` used by
// `Directionality` below — hidden here rather than prefixing every
// `DateFormat` reference.
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/network/api_exception.dart';
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إنشاء نسخة احتياطية.')));
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : 'تعذر إنشاء النسخة الاحتياطية.';
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
        final message = e is ApiException ? e.userMessage : 'تعذر التحديث.';
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

    return Scaffold(
      appBar: AppBar(title: const Text('النسخ الاحتياطي')),
      body: statusAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text(error is ApiException ? error.userMessage : 'تعذر التحميل.'),
        ),
        data: (status) {
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(backupStatusProvider),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  status.lastBackupAt != null
                      ? 'آخر نسخة احتياطية: ${dateFormat.format(status.lastBackupAt!)}'
                      : 'لا يوجد نسخ سابق',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: status.enabled,
                  onChanged: _togglingAuto ? null : _toggleAuto,
                  title: const Text('تفعيل النسخ اليومي التلقائي'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _creating ? null : _createBackup,
                  icon: _creating
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.backup_outlined),
                  label: Text(_creating ? 'جاري الإنشاء...' : 'إنشاء نسخة احتياطية الآن'),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'يتم تشغيل النسخ اليومي تلقائيًا عبر جدولة الخادم (وليس عند فتح الشاشة فقط)، '
                    'ويُحفظ كل نسخة في تخزين الخادم الخاص — غير متاح للتحميل من التطبيق.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 24),
                Text('النسخ الأخيرة', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (status.files.isEmpty) const Text('لا توجد نسخ احتياطية بعد.'),
                for (final file in status.files) _BackupFileTile(file: file, formatSize: _formatSize, dateFormat: dateFormat),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BackupFileTile extends StatelessWidget {
  const _BackupFileTile({required this.file, required this.formatSize, required this.dateFormat});
  final BackupFile file;
  final String Function(int) formatSize;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.description_outlined),
        title: Directionality(
          textDirection: TextDirection.ltr,
          child: Text(file.name, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ),
        // Forced LTR: two LTR-ish values (a size, a date) joined only by
        // "·" have no strong-direction anchor inside RTL text — same bidi
        // reordering issue documented in permission_edit_screen.dart.
        subtitle: Directionality(
          textDirection: TextDirection.ltr,
          child: Text('${formatSize(file.size)} · ${dateFormat.format(file.mtime)}'),
        ),
      ),
    );
  }
}
