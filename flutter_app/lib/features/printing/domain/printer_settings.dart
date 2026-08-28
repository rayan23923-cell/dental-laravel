/// Which physical printer a ticket/receipt prints to. `builtin` is the
/// original, still-default behavior from Phase 4D/5 — the built-in POS
/// terminal printer, AIDL-first with a Bluetooth-SPP fallback to that
/// exact same hardcoded device. `bluetooth`/`usb` are new: an explicitly
/// chosen external printer.
enum PrinterConnectionType { builtin, bluetooth, usb }

/// iOS-only (see `PosPrinterPlugin.swift`'s `resolveWriteCharacteristic()`):
/// classic Bluetooth SPP (Android) has no such distinction — this is a BLE
/// GATT write-type choice. `fast` (`.withoutResponse`, paced by
/// `canSendWriteWithoutResponse`) is noticeably quicker than `safe`
/// (`.withResponse`, waits for an ack every chunk) but was originally the
/// more conservative default since this class of cheap BLE-serial-bridge
/// printer is known to sometimes drop unthrottled writes — confirmed live
/// (2026-08-28) that `fast` actually prints reliably on the real "58E"
/// hardware too, just user-selectable now rather than silently switching
/// the default, in case a different printer unit needs `safe` after all.
enum BluetoothWriteMode { fast, safe }

/// Persisted printer preference (see `printer_settings_repository.dart`).
/// Defaults (`builtin`, 58mm) reproduce today's exact behavior for anyone
/// who never opens the new settings screen — this is additive, not a
/// breaking change to how printing already worked.
class PrinterSettings {
  const PrinterSettings({
    this.connectionType = PrinterConnectionType.builtin,
    this.bluetoothAddress,
    this.bluetoothName,
    this.usbDeviceName,
    this.paperWidthMm = 58,
    this.bluetoothWriteMode = BluetoothWriteMode.fast,
  });

  final PrinterConnectionType connectionType;
  final String? bluetoothAddress;
  final String? bluetoothName;
  final String? usbDeviceName;
  final int paperWidthMm;
  final BluetoothWriteMode bluetoothWriteMode;

  /// ESC/POS raster dot count for the chosen paper width — the
  /// industry-standard 58mm=384/80mm=576 convention (~8 dots/mm at the
  /// 203dpi-class density this printer's existing 384/58mm pairing
  /// already implies), not an arbitrary choice.
  double get dotsPerLine => paperWidthMm == 80 ? 576 : 384;

  PrinterSettings copyWith({
    PrinterConnectionType? connectionType,
    String? bluetoothAddress,
    String? bluetoothName,
    String? usbDeviceName,
    int? paperWidthMm,
    BluetoothWriteMode? bluetoothWriteMode,
  }) {
    return PrinterSettings(
      connectionType: connectionType ?? this.connectionType,
      bluetoothAddress: bluetoothAddress ?? this.bluetoothAddress,
      bluetoothName: bluetoothName ?? this.bluetoothName,
      usbDeviceName: usbDeviceName ?? this.usbDeviceName,
      paperWidthMm: paperWidthMm ?? this.paperWidthMm,
      bluetoothWriteMode: bluetoothWriteMode ?? this.bluetoothWriteMode,
    );
  }
}
