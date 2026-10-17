import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/network/api_client.dart';
import '../domain/backup_status.dart';

final backupAdminRepositoryProvider = Provider<BackupAdminRepository>((ref) {
  return BackupAdminRepository(ref.watch(apiClientProvider));
});

/// `/backup` — plain (non-`{data:}`-wrapped) JSON, matching
/// `Api\BackupController`'s own shape.
class BackupAdminRepository {
  BackupAdminRepository(this._client);
  final ApiClient _client;

  Future<BackupStatus> fetch() async {
    final data = await _client.getJson('/backup') as Map<String, dynamic>;
    return BackupStatus.fromJson(data);
  }

  Future<void> createBackup() => _client.postJson('/backup');

  Future<void> setAutoEnabled(bool enabled) => _client.putJson('/backup/auto', body: {'enabled': enabled});

  /// Saving a file needs a real file system (not the web build).
  static bool get canDownload => !kIsWeb;

  /// Downloads [file] (the web's backup.download, 2026-10-17) and returns
  /// where it was saved: the Downloads folder on a computer; on a phone
  /// the app's own storage folder, since the app has no share/"save to"
  /// plugin (Android: `Android/data/<app>/files`, reachable from a file
  /// manager or a USB cable).
  Future<String> download(BackupFile file) async {
    final dir = await _targetDirectory();
    await dir.create(recursive: true);
    final path = '${dir.path}${Platform.pathSeparator}${file.name}';
    await _client.downloadToFile('/backup/${Uri.encodeComponent(file.name)}/download', path);
    return path;
  }

  Future<Directory> _targetDirectory() async {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) return downloads;
    }
    if (Platform.isAndroid) {
      final external = await getExternalStorageDirectory();
      if (external != null) return Directory('${external.path}${Platform.pathSeparator}backups');
    }
    final documents = await getApplicationDocumentsDirectory();
    return Directory('${documents.path}${Platform.pathSeparator}backups');
  }

  /// Shows the saved file in the system file browser where one can be
  /// opened (Windows Explorer / macOS Finder / Linux file manager).
  static Future<bool> reveal(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.start('explorer.exe', ['/select,', path]);
        return true;
      }
      if (Platform.isMacOS) {
        await Process.start('open', ['-R', path]);
        return true;
      }
      if (Platform.isLinux) {
        await Process.start('xdg-open', [File(path).parent.path]);
        return true;
      }
    } catch (_) {
      // No file browser to hand it to: the caller still shows the path.
    }
    return false;
  }

  static bool get canReveal => !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
}
