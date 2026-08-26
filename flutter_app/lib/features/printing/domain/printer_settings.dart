/// Which physical printer a ticket/receipt prints to. `builtin` is the
/// original, still-default behavior from Phase 4D/5 — the built-in POS
/// terminal printer, AIDL-first with a Bluetooth-SPP fallback to that
/// exact same hardcoded device. `bluetooth`/`usb` are new: an explicitly
/// chosen external printer.
enum PrinterConnectionType { builtin, bluetooth, usb }

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
  });

  final PrinterConnectionType connectionType;
  final String? bluetoothAddress;
  final String? bluetoothName;
  final String? usbDeviceName;
  final int paperWidthMm;

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
  }) {
    return PrinterSettings(
      connectionType: connectionType ?? this.connectionType,
      bluetoothAddress: bluetoothAddress ?? this.bluetoothAddress,
      bluetoothName: bluetoothName ?? this.bluetoothName,
      usbDeviceName: usbDeviceName ?? this.usbDeviceName,
      paperWidthMm: paperWidthMm ?? this.paperWidthMm,
    );
  }
}
