import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/printer_settings.dart';

final printerSettingsRepositoryProvider = Provider<PrinterSettingsRepository>((ref) => PrinterSettingsRepository());

/// Plain key/value persistence for the printer preference — `shared_preferences`,
/// not `flutter_secure_storage` (reserved for the real secret, the Sanctum
/// bearer token, see `core/storage/token_storage.dart`). A printer choice
/// isn't a secret; using Keystore-backed storage for it would just be
/// slower for no benefit. Same "pure key/value wrapper, no business logic"
/// shape as `TokenStorage`.
class PrinterSettingsRepository {
  static const _kConnectionType = 'printer_connection_type';
  static const _kBluetoothAddress = 'printer_bluetooth_address';
  static const _kBluetoothName = 'printer_bluetooth_name';
  static const _kUsbDeviceName = 'printer_usb_device_name';
  static const _kPaperWidthMm = 'printer_paper_width_mm';

  Future<PrinterSettings> read() async {
    final prefs = await SharedPreferences.getInstance();
    final typeName = prefs.getString(_kConnectionType);
    final connectionType = PrinterConnectionType.values.firstWhere(
      (t) => t.name == typeName,
      orElse: () => PrinterConnectionType.builtin,
    );

    return PrinterSettings(
      connectionType: connectionType,
      bluetoothAddress: prefs.getString(_kBluetoothAddress),
      bluetoothName: prefs.getString(_kBluetoothName),
      usbDeviceName: prefs.getString(_kUsbDeviceName),
      paperWidthMm: prefs.getInt(_kPaperWidthMm) ?? 58,
    );
  }

  Future<void> save(PrinterSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kConnectionType, settings.connectionType.name);
    await prefs.setInt(_kPaperWidthMm, settings.paperWidthMm);

    if (settings.bluetoothAddress != null) {
      await prefs.setString(_kBluetoothAddress, settings.bluetoothAddress!);
    } else {
      await prefs.remove(_kBluetoothAddress);
    }
    if (settings.bluetoothName != null) {
      await prefs.setString(_kBluetoothName, settings.bluetoothName!);
    } else {
      await prefs.remove(_kBluetoothName);
    }
    if (settings.usbDeviceName != null) {
      await prefs.setString(_kUsbDeviceName, settings.usbDeviceName!);
    } else {
      await prefs.remove(_kUsbDeviceName);
    }
  }
}
