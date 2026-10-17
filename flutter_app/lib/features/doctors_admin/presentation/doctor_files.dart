import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Saves a downloaded file (the doctors template or export, 2026-10-17)
/// where the user picks: the system "save as" on Android/iOS (which takes
/// the bytes itself) and a save dialog on Windows. If the platform has no
/// save dialog, it falls back to the app's documents folder. Returns where
/// it went, or null when the user cancelled.
Future<String?> saveDownloadedFile(String fileName, List<int> bytes) async {
  final data = Uint8List.fromList(bytes);
  final mobile = Platform.isAndroid || Platform.isIOS;
  String? path;
  var written = false;
  try {
    path = await FilePicker.platform.saveFile(
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      bytes: mobile ? data : null,
    );
    if (path == null) return null;
    written = mobile;
  } on UnimplementedError {
    final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    path = '${dir.path}${Platform.pathSeparator}$fileName';
  }
  // The mobile picker has already written the bytes.
  if (!written) await File(path).writeAsBytes(data, flush: true);
  return path;
}

/// Picks the Excel sheet to import; null when cancelled.
Future<({String name, List<int> bytes})?> pickExcelFile() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['xlsx', 'xls', 'csv'],
    withData: true,
  );
  final file = result?.files.singleOrNull;
  if (file == null) return null;
  final bytes = file.bytes ?? (file.path != null ? await File(file.path!).readAsBytes() : null);
  if (bytes == null) return null;
  return (name: file.name, bytes: bytes);
}
