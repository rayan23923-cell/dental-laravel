import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Sends bytes untouched to a Windows printer queue (winspool, datatype
/// RAW), so ESC/POS reaches a USB thermal printer exactly as written,
/// bypassing the driver's page rendering (2026-10-16). Works with the
/// printer's own driver or Windows' "Generic / Text Only" driver.
class WindowsRawPrinter {
  const WindowsRawPrinter._();

  static void write(String printerName, Uint8List bytes, {String jobName = 'ticket'}) {
    final lib = DynamicLibrary.open('winspool.drv');
    final openPrinter = lib.lookupFunction<Int32 Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>),
        int Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>)>('OpenPrinterW');
    final startDoc = lib.lookupFunction<Uint32 Function(IntPtr, Uint32, Pointer<_DocInfo1>),
        int Function(int, int, Pointer<_DocInfo1>)>('StartDocPrinterW');
    final startPage = lib.lookupFunction<Int32 Function(IntPtr), int Function(int)>('StartPagePrinter');
    final writePrinter = lib.lookupFunction<Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>),
        int Function(int, Pointer<Uint8>, int, Pointer<Uint32>)>('WritePrinter');
    final endPage = lib.lookupFunction<Int32 Function(IntPtr), int Function(int)>('EndPagePrinter');
    final endDoc = lib.lookupFunction<Int32 Function(IntPtr), int Function(int)>('EndDocPrinter');
    final closePrinter = lib.lookupFunction<Int32 Function(IntPtr), int Function(int)>('ClosePrinter');

    final arena = Arena();
    try {
      final handle = arena<IntPtr>();
      if (openPrinter(printerName.toNativeUtf16(allocator: arena), handle, nullptr) == 0) {
        throw WindowsRawPrinterException('Could not open the printer "$printerName".');
      }
      final printer = handle.value;
      try {
        final doc = arena<_DocInfo1>()
          ..ref.pDocName = jobName.toNativeUtf16(allocator: arena)
          ..ref.pOutputFile = nullptr
          ..ref.pDatatype = 'RAW'.toNativeUtf16(allocator: arena);
        if (startDoc(printer, 1, doc) == 0) {
          throw WindowsRawPrinterException('The printer "$printerName" refused a raw print job.');
        }
        try {
          startPage(printer);
          final data = arena<Uint8>(bytes.length)..asTypedList(bytes.length).setAll(0, bytes);
          final written = arena<Uint32>();
          if (writePrinter(printer, data, bytes.length, written) == 0 || written.value != bytes.length) {
            throw WindowsRawPrinterException('Sending to the printer "$printerName" failed.');
          }
          endPage(printer);
        } finally {
          endDoc(printer);
        }
      } finally {
        closePrinter(printer);
      }
    } finally {
      arena.releaseAll();
    }
  }
}

class WindowsRawPrinterException implements Exception {
  const WindowsRawPrinterException(this.message);
  final String message;

  @override
  String toString() => message;
}

final class _DocInfo1 extends Struct {
  external Pointer<Utf16> pDocName;
  external Pointer<Utf16> pOutputFile;
  external Pointer<Utf16> pDatatype;
}
