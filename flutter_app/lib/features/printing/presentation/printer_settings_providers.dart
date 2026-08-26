import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/printer_settings_repository.dart';
import '../domain/printer_settings.dart';

/// Read anywhere printing happens (`PosPrinterService`) and by the
/// settings screen. `AsyncNotifier` rather than a plain `FutureProvider`
/// because the settings screen needs a `save()` that updates the cached
/// value in place, not just a one-shot read.
final printerSettingsProvider = AsyncNotifierProvider<PrinterSettingsNotifier, PrinterSettings>(
  PrinterSettingsNotifier.new,
);

class PrinterSettingsNotifier extends AsyncNotifier<PrinterSettings> {
  @override
  Future<PrinterSettings> build() {
    return ref.watch(printerSettingsRepositoryProvider).read();
  }

  Future<void> save(PrinterSettings settings) async {
    await ref.read(printerSettingsRepositoryProvider).save(settings);
    state = AsyncData(settings);
  }
}
