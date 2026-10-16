import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/platform_support.dart';
import '../domain/printer_settings.dart';
import 'desktop_ticket_printer.dart';
import 'printer_settings_repository.dart';

final posPrinterServiceProvider = Provider<PosPrinterService>((ref) {
  return PosPrinterService(ref.watch(printerSettingsRepositoryProvider));
});

/// Thrown by [PosPrinterService.printTicket] when the configured printer is
/// Bluetooth but the adapter is off — distinguished from every other print
/// failure so the UI can offer "turn it on" instead of just "check the
/// connection" (see `printer_error_snackbar.dart`).
class BluetoothDisabledException implements Exception {
  const BluetoothDisabledException();
}

/// Talks to `PosPrinterPlugin.kt`. `connectionType == builtin` (the
/// default) keeps the exact original behavior from Phase 4D/5 unchanged:
/// binds the built-in POS printer's AIDL service
/// (`com.iposprinter.iposprinterservice` — see that Kotlin file's doc
/// comment for how this exact SDK was identified on this device, and
/// `IPosPrinterService.aidl` for the real, vendor-documented method
/// signatures this bridges to), falling back to a hardcoded bonded
/// Bluetooth device. `bluetooth`/`usb` target an explicitly-chosen
/// external printer instead — see the printer-settings screen. Android-only;
/// nothing calls this on other platforms (`Platform.isAndroid` guarded at
/// the call site).
class PosPrinterService {
  const PosPrinterService(this._settingsRepository);

  final PrinterSettingsRepository _settingsRepository;

  static const MethodChannel _channel = MethodChannel('com.dentalclinic.dental_clinic_app/pos_printer');

  /// `pngBytes` is a rendered ticket image (see `ticket_renderer.dart`) —
  /// printed as a bitmap, not text, because the printer's own built-in
  /// fonts are Chinese GBK/GB18030 + ASCII only (confirmed from the
  /// vendor service's bundled font resources) and have no Arabic glyphs.
  ///
  /// Call sites don't pass connection/width info — this reads the stored
  /// preference itself and forwards it, so `TicketWidget`/`ReceiptWidget`'s
  /// `widthDots` (which the call site *does* need to set, since it affects
  /// the rendered bitmap itself) is the only other place a caller needs to
  /// touch `printerSettingsProvider`.
  ///
  /// When the configured printer is Bluetooth and the adapter is off, this
  /// proactively triggers Android's own "turn on Bluetooth?" prompt
  /// (`requestEnableBluetooth()`, already used by the printer-settings
  /// screen) instead of just failing — that prompt has no completion
  /// callback (see that method's doc comment), so this still throws
  /// [BluetoothDisabledException] to abort *this* attempt; the user taps
  /// "طباعة" again once Bluetooth is actually on.
  Future<void> printTicket(Uint8List pngBytes) async {
    final settings = await _settingsRepository.read();
    // Windows has no POS plugin: the ticket goes to a Windows printer
    // instead (2026-10-12), see DesktopTicketPrinter.
    if (isWindowsDesktop) {
      await DesktopTicketPrinter.printTicket(
        pngBytes,
        paperWidthMm: settings.paperWidthMm,
        widthDots: settings.dotsPerLine.round(),
      );
      return;
    }
    if (settings.connectionType == PrinterConnectionType.bluetooth && !await isBluetoothEnabled()) {
      await requestEnableBluetooth();
      throw const BluetoothDisabledException();
    }
    await _channel.invokeMethod('printTicket', {
      'pngBytes': pngBytes,
      'connectionType': settings.connectionType.name,
      'bluetoothAddress': settings.bluetoothAddress,
      'usbDeviceName': settings.usbDeviceName,
      'paperWidthDots': settings.dotsPerLine.round(),
      // iOS-only — see BluetoothWriteMode's doc comment. Android ignores
      // this (classic Bluetooth SPP has no such distinction).
      'bluetoothWriteMode': settings.bluetoothWriteMode.name,
    });
  }

  /// Mirrors the AIDL `getPrinterStatus()` codes from the vendor doc:
  /// 0=normal, 1=paperless, 2=head overheat, 3=motor overheat, 4=busy,
  /// 5=unknown error. -1 if the service isn't bound yet. Only meaningful
  /// for the builtin connection type — AIDL is what exposes this call.
  Future<int> getPrinterStatus() async {
    final status = await _channel.invokeMethod<int>('getPrinterStatus');
    return status ?? -1;
  }

  Future<List<BluetoothDeviceInfo>> listPairedBluetoothDevices() async {
    final result = await _channel.invokeMethod<List<Object?>>('listPairedDevices');
    return (result ?? [])
        .cast<Map<Object?, Object?>>()
        .map((m) => BluetoothDeviceInfo(name: m['name'] as String? ?? '', address: m['address'] as String? ?? ''))
        .toList();
  }

  /// Streams devices as they're discovered — see `PosPrinterPlugin.kt`'s
  /// `bt_scan_events` `EventChannel`. Emits `null` once discovery finishes
  /// (`ACTION_DISCOVERY_FINISHED`) so the UI knows to stop showing a
  /// scanning spinner.
  Stream<BluetoothDeviceInfo?> scanBluetoothDevices() {
    const events = EventChannel('com.dentalclinic.dental_clinic_app/pos_printer/bt_scan_events');
    return events.receiveBroadcastStream().map((event) {
      if (event == null) return null;
      final m = event as Map<Object?, Object?>;
      return BluetoothDeviceInfo(name: m['name'] as String? ?? '', address: m['address'] as String? ?? '');
    });
  }

  /// Triggers Android's own pairing dialog (`ACTION_PAIRING_REQUEST`) —
  /// this app never builds a custom PIN UI, the OS handles that. Resolves
  /// once bonding finishes (success or failure).
  Future<bool> pairBluetoothDevice(String address) async {
    final result = await _channel.invokeMethod<bool>('pairDevice', {'address': address});
    return result ?? false;
  }

  Future<List<UsbDeviceInfo>> listUsbDevices() async {
    final result = await _channel.invokeMethod<List<Object?>>('listUsbDevices');
    return (result ?? [])
        .cast<Map<Object?, Object?>>()
        .map((m) => UsbDeviceInfo(deviceName: m['deviceName'] as String? ?? '', productName: m['productName'] as String?))
        .toList();
  }

  /// Android shows its own permission dialog for USB device access.
  Future<bool> requestUsbPermission(String deviceName) async {
    final result = await _channel.invokeMethod<bool>('requestUsbPermission', {'deviceName': deviceName});
    return result ?? false;
  }

  /// Whether the device's Bluetooth adapter is currently on — checked
  /// before scanning so a disabled adapter surfaces as an immediate,
  /// actionable message instead of `scanBluetoothDevices()` hanging
  /// forever (see `PosPrinterPlugin.kt`'s `onListen()` doc comment for the
  /// real bug this was found fixing).
  Future<bool> isBluetoothEnabled() async {
    final result = await _channel.invokeMethod<bool>('isBluetoothEnabled');
    return result ?? false;
  }

  /// Shows Android's own "Allow app to turn on Bluetooth?" system dialog
  /// (`ACTION_REQUEST_ENABLE`) — no result callback (the plugin only holds
  /// a plain `Context`, not an `Activity`), so the caller re-checks
  /// [isBluetoothEnabled] itself when the user returns to the app.
  Future<void> requestEnableBluetooth() {
    return _channel.invokeMethod('requestEnableBluetooth');
  }

  /// Fails open (`true`) on any error — an unknown Location state must
  /// never block scanning outright, only inform the "why aren't devices
  /// showing" message (classic Bluetooth discovery needs system Location
  /// enabled on some Android versions, independent of the permission
  /// grant — see `printer_settings_screen.dart`'s `_scanBluetooth()`).
  Future<bool> isLocationEnabled() async {
    try {
      final result = await _channel.invokeMethod<bool>('isLocationEnabled');
      return result ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> openLocationSettings() {
    return _channel.invokeMethod('openLocationSettings');
  }
}

class BluetoothDeviceInfo {
  const BluetoothDeviceInfo({required this.name, required this.address});
  final String name;
  final String address;
}

class UsbDeviceInfo {
  const UsbDeviceInfo({required this.deviceName, this.productName});
  final String deviceName;
  final String? productName;
}
