import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/platform/platform_support.dart';
import '../data/desktop_ticket_printer.dart';
import '../data/pos_printer_service.dart';
import '../domain/printer_settings.dart';
import 'printer_error_snackbar.dart';
import 'printer_settings_providers.dart';
import 'ticket_renderer.dart';

/// "إعدادات الطابعة" — lets staff pick between the original built-in POS
/// printer (unchanged default behavior), an external Bluetooth printer
/// (search/pair — the OS's own dialog handles the PIN, this screen never
/// builds one), or a USB printer, plus the paper width (58mm/80mm). See
/// `PosPrinterPlugin.kt`'s doc comment for how each connection type is
/// actually driven.
class PrinterSettingsScreen extends ConsumerStatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  ConsumerState<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends ConsumerState<PrinterSettingsScreen> {
  PrinterSettings? _draft;
  bool _seeded = false;
  bool _saving = false;

  List<BluetoothDeviceInfo> _pairedDevices = [];
  final Map<String, BluetoothDeviceInfo> _discovered = {};
  bool _scanning = false;
  StreamSubscription<BluetoothDeviceInfo?>? _scanSubscription;

  List<UsbDeviceInfo> _usbDevices = [];
  bool _loadingUsb = false;

  /// Windows (2026-10-12): the system printer tickets go to, see
  /// `DesktopTicketPrinter`.
  String? _desktopPrinterName;
  DesktopPrintMode _desktopMode = DesktopPrintMode.driver;
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '${DesktopTicketPrinter.defaultNetworkPort}');
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    if (isWindowsDesktop) {
      DesktopTicketPrinter.savedPrinterName().then((name) {
        if (mounted) setState(() => _desktopPrinterName = name);
      });
      DesktopTicketPrinter.savedMode().then((mode) {
        if (mounted) setState(() => _desktopMode = mode);
      });
      DesktopTicketPrinter.savedNetworkPrinter().then((printer) {
        if (!mounted) return;
        _hostController.text = printer.host ?? '';
        _portController.text = '${printer.port}';
      });
    }
  }

  Future<void> _setDesktopMode(DesktopPrintMode mode) async {
    setState(() => _desktopMode = mode);
    await DesktopTicketPrinter.saveMode(mode);
  }

  Future<void> _saveNetworkPrinter() => DesktopTicketPrinter.saveNetworkPrinter(
        _hostController.text,
        int.tryParse(_portController.text.trim()) ?? DesktopTicketPrinter.defaultNetworkPort,
      );

  /// Prints a short Arabic slip through the chosen mode and paper width,
  /// so the desk can check the printer before a real patient's ticket.
  Future<void> _testPrint(PrinterSettings draft) async {
    final t = ref.read(translationsProvider);
    setState(() => _testing = true);
    try {
      await _saveNetworkPrinter();
      final widthDots = draft.dotsPerLine.round();
      if (!mounted) return;
      final png = await renderWidgetToPng(context, _TestSlip(widthDots: widthDots, title: t['printerSettingsAdmin.testPrintSlip']!));
      await DesktopTicketPrinter.printTicket(png, paperWidthMm: draft.paperWidthMm, widthDots: widthDots);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['printerSettingsAdmin.testPrintSent']!)));
      }
    } catch (e) {
      if (mounted) showPrinterErrorSnackBar(context, t['printerSettingsAdmin.testPrintFailed']!, error: e);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _pickDesktopPrinter() async {
    final name = await DesktopTicketPrinter.pickPrinter(context);
    if (name != null && mounted) setState(() => _desktopPrinterName = name);
  }

  void _seed(PrinterSettings settings) {
    if (_seeded) return;
    _seeded = true;
    _draft = settings;
    // Otherwise the paired/USB device list stays empty until the user
    // re-taps the segment, even though it's already the saved selection.
    if (settings.connectionType == PrinterConnectionType.bluetooth) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPairedDevices());
    } else if (settings.connectionType == PrinterConnectionType.usb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadUsbDevices());
    }
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _loadPairedDevices() async {
    final devices = await ref.read(posPrinterServiceProvider).listPairedBluetoothDevices();
    if (mounted) setState(() => _pairedDevices = devices);
  }

  Future<void> _scanBluetooth() async {
    // Runtime permission (API 31+) — requested Dart-side since the plugin
    // only holds a plain Context, not an Activity (see PosPrinterPlugin.kt's
    // doc comment).
    // `Permission.bluetoothScan`/`bluetoothConnect` are Android-12+-only
    // permission *types* — permission_handler has no iOS mapping for them
    // and always reports them denied there, which permanently blocked this
    // screen's scan button on iOS regardless of the real CoreBluetooth
    // permission (`NSBluetoothAlwaysUsageDescription`) the user had
    // already granted. iOS's single equivalent is `Permission.bluetooth`.
    // locationWhenInUse is an Android-only requirement here (classic-
    // Bluetooth discovery historically ties to it) — BLE scanning on iOS
    // has never needed Location, so asking for it there would just be a
    // confusing, purposeless permission prompt.
    final isAndroid = !kIsWeb && Platform.isAndroid;
    final isIOS = !kIsWeb && Platform.isIOS;
    final bluetoothPermissions = isAndroid
        ? [Permission.bluetoothScan, Permission.bluetoothConnect]
        : isIOS
            ? [Permission.bluetooth]
            : <Permission>[];
    final statuses = await [
      ...bluetoothPermissions,
      if (isAndroid) Permission.locationWhenInUse,
    ].request();

    final btDenied = bluetoothPermissions.map((p) => statuses[p]).any((s) => s != null && !s.isGranted);
    if (btDenied) {
      if (mounted) {
        final t = ref.read(translationsProvider);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['printerSettingsAdmin.bluetoothPermissionRequired']!)));
      }
      return;
    }

    // A real bug, found live: on API 23–30, startDiscovery() silently
    // withholds ACTION_FOUND results without a location permission (see
    // AndroidManifest.xml's comment) — a device visible in the phone's own
    // Bluetooth settings never showed up here. Warn rather than block:
    // on API 31+ this permission isn't even declared in the manifest for
    // that OS range (BLUETOOTH_SCAN's neverForLocation flag covers
    // discovery there instead), so it will always read as denied there and
    // must not stop the scan.
    final locationStatus = statuses[Permission.locationWhenInUse];
    if (locationStatus != null && !locationStatus.isGranted && mounted) {
      final t = ref.read(translationsProvider);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t['printerSettingsAdmin.locationHintMsg']!),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: t['printerSettingsAdmin.settingsAction']!,
          // Explicit color: the theme's default SnackBarAction color was
          // nearly invisible against this app's SnackBar background in
          // dark system theme — found live via a device screenshot, not a
          // cosmetic guess.
          textColor: InstagramColors.blue,
          onPressed: () => ref.read(posPrinterServiceProvider).openLocationSettings(),
        ),
      ));
    }

    // Real bug, found live: Bluetooth being off wasn't checked anywhere
    // before scanning — startDiscovery() silently no-ops when off, so the
    // "scanning" spinner below never stopped (see PosPrinterPlugin.kt's
    // onListen() doc comment). Checked here so the fix is immediate and
    // actionable instead of a hang.
    if (!await ref.read(posPrinterServiceProvider).isBluetoothEnabled()) {
      if (mounted) {
        final t = ref.read(translationsProvider);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t['printerSettingsAdmin.bluetoothOffMsg']!),
          action: SnackBarAction(
            label: t['printerSettingsAdmin.turnOnAction']!,
            textColor: InstagramColors.blue,
            onPressed: () => ref.read(posPrinterServiceProvider).requestEnableBluetooth(),
          ),
        ));
      }
      return;
    }

    setState(() {
      _scanning = true;
      _discovered.clear();
    });

    await _scanSubscription?.cancel();
    _scanSubscription = ref.read(posPrinterServiceProvider).scanBluetoothDevices().listen(
      (device) {
        if (!mounted) return;
        if (device == null) {
          setState(() => _scanning = false);
          return;
        }
        if (device.address.isEmpty) return;
        setState(() => _discovered[device.address] = device);
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() => _scanning = false);
        final t = ref.read(translationsProvider);
        // Bluetooth turned off *during* an active scan, not just before
        // starting one — same one-tap fix as the pre-scan check above.
        if (e is PlatformException && e.code == 'bluetooth_disabled') {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t['printerSettingsAdmin.bluetoothOffMsg']!),
            action: SnackBarAction(
              label: t['printerSettingsAdmin.turnOnAction']!,
              textColor: InstagramColors.blue,
              onPressed: () => ref.read(posPrinterServiceProvider).requestEnableBluetooth(),
            ),
          ));
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(trf(t['printerSettingsAdmin.scanFailed']!, {'error': '$e'}))));
      },
    );
  }

  Future<void> _pair(BluetoothDeviceInfo device) async {
    final ok = await ref.read(posPrinterServiceProvider).pairBluetoothDevice(device.address);
    if (!mounted) return;
    final t = ref.read(translationsProvider);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(trf(t['printerSettingsAdmin.pairedSuccessMsg']!, {'name': device.name}))));
      // On Android, `listPairedDevices()` reflects the OS's own bonded-
      // devices list, so a second explicit "تحديد" step (from that list)
      // makes sense there. BLE has no such list — `listPairedDevices()`
      // always returns [] on iOS (see PosPrinterPlugin.swift) — so without
      // this, a successful pairing there had nothing to select from and
      // `bluetoothAddress` was never actually saved (found live: printing
      // failed with "عنوان بلوتوث مفقود" despite pairing having
      // succeeded). On iOS, pairing itself *is* the selection.
      if (!kIsWeb && Platform.isIOS) {
        _selectBluetoothDevice(device);
      } else {
        await _loadPairedDevices();
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['printerSettingsAdmin.pairFailedMsg']!)));
    }
  }

  void _selectBluetoothDevice(BluetoothDeviceInfo device) {
    setState(() {
      _draft = _draft?.copyWith(bluetoothAddress: device.address, bluetoothName: device.name);
    });
  }

  Future<void> _loadUsbDevices() async {
    setState(() => _loadingUsb = true);
    try {
      final devices = await ref.read(posPrinterServiceProvider).listUsbDevices();
      if (mounted) setState(() => _usbDevices = devices);
    } finally {
      if (mounted) setState(() => _loadingUsb = false);
    }
  }

  Future<void> _selectUsbDevice(UsbDeviceInfo device) async {
    final granted = await ref.read(posPrinterServiceProvider).requestUsbPermission(device.deviceName);
    if (!mounted) return;
    if (granted) {
      setState(() => _draft = _draft?.copyWith(usbDeviceName: device.deviceName));
    } else {
      final t = ref.read(translationsProvider);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['printerSettingsAdmin.usbPermissionDenied']!)));
    }
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _saving = true);
    try {
      if (isWindowsDesktop) await _saveNetworkPrinter();
      await ref.read(printerSettingsProvider.notifier).save(draft);
      if (mounted) {
        final t = ref.read(translationsProvider);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['printerSettingsAdmin.settingsSavedSuccess']!)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(printerSettingsProvider);
    final t = ref.watch(translationsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t['printerSettingsAdmin.title']!)),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(trf(t['printerSettingsAdmin.loadFailed']!, {'error': '$error'}))),
        data: (settings) {
          _seed(settings);
          final draft = _draft ?? settings;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Windows: one system printer (the desk's thermal printer
              // through its driver) instead of the phone connection types.
              if (isWindowsDesktop) ...[
                Text(t['printerSettingsAdmin.windowsPrinterHeading']!, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<DesktopPrintMode>(
                  segments: [
                    ButtonSegment(value: DesktopPrintMode.driver, label: Text(t['printerSettingsAdmin.windowsModeDriver']!)),
                    ButtonSegment(value: DesktopPrintMode.usbRaw, label: Text(t['printerSettingsAdmin.windowsModeUsb']!)),
                    ButtonSegment(value: DesktopPrintMode.network, label: Text(t['printerSettingsAdmin.windowsModeNetwork']!)),
                  ],
                  selected: {_desktopMode},
                  onSelectionChanged: (selection) => _setDesktopMode(selection.first),
                ),
                const SizedBox(height: 8),
                if (_desktopMode == DesktopPrintMode.network) ...[
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _hostController,
                          textDirection: TextDirection.ltr,
                          keyboardType: TextInputType.url,
                          decoration: InputDecoration(labelText: t['printerSettingsAdmin.networkHost']!, hintText: '192.168.1.100'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _portController,
                          textDirection: TextDirection.ltr,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: t['printerSettingsAdmin.networkPort']!),
                        ),
                      ),
                    ],
                  ),
                ] else
                  Card(
                    color: _desktopPrinterName != null ? Theme.of(context).colorScheme.primaryContainer : null,
                    child: ListTile(
                      leading: const Icon(Icons.print_outlined),
                      title: Text(_desktopPrinterName ?? t['printerSettingsAdmin.windowsPrinterNone']!),
                      trailing: OutlinedButton(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(64, 36)),
                        onPressed: _pickDesktopPrinter,
                        child: Text(t['printerSettingsAdmin.selectButton']!),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    t[switch (_desktopMode) {
                      DesktopPrintMode.driver => 'printerSettingsAdmin.windowsPrinterHint',
                      DesktopPrintMode.usbRaw => 'printerSettingsAdmin.windowsModeUsbHint',
                      DesktopPrintMode.network => 'printerSettingsAdmin.windowsModeNetworkHint',
                    }]!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _testing ? null : () => _testPrint(draft),
                  icon: _testing
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.receipt_long_outlined),
                  label: Text(t['printerSettingsAdmin.testPrint']!),
                ),
              ] else ...[
              Text(t['printerSettingsAdmin.connectionTypeHeading']!, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SegmentedButton<PrinterConnectionType>(
                // Android-only connection types: "builtin" is a vendor AIDL
                // SDK for one specific POS terminal, and "usb" needs
                // Android's USB host API — neither has an iOS equivalent
                // (no MFi accessory involved), so only Bluetooth (BLE on
                // iOS) is offered there. See PosPrinterPlugin.swift's class
                // doc for why.
                segments: [
                  if (!kIsWeb && Platform.isAndroid)
                    ButtonSegment(value: PrinterConnectionType.builtin, label: Text(t['printerSettingsAdmin.builtinPrinterOption']!)),
                  ButtonSegment(value: PrinterConnectionType.bluetooth, label: Text(t['printerSettingsAdmin.bluetoothOption']!)),
                  if (!kIsWeb && Platform.isAndroid)
                    ButtonSegment(value: PrinterConnectionType.usb, label: Text(t['printerSettingsAdmin.usbOption']!)),
                ],
                selected: {draft.connectionType},
                onSelectionChanged: (selection) {
                  setState(() => _draft = draft.copyWith(connectionType: selection.first));
                  if (selection.first == PrinterConnectionType.bluetooth) _loadPairedDevices();
                  if (selection.first == PrinterConnectionType.usb) _loadUsbDevices();
                },
              ),
              const SizedBox(height: 24),
              if (draft.connectionType == PrinterConnectionType.bluetooth) ...[
                Row(
                  children: [
                    Expanded(child: Text(t['printerSettingsAdmin.searchBluetoothHeading']!, style: Theme.of(context).textTheme.titleMedium)),
                    FilledButton.icon(
                      // app_theme.dart's FilledButtonThemeData defaults to
                      // Size.fromHeight(44) (infinite width) for full-width
                      // buttons like "حفظ" below. That crashes a button
                      // placed inline in a Row (BoxConstraints forces an
                      // infinite width) — bound the width back down here.
                      style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
                      onPressed: _scanning ? null : _scanBluetooth,
                      icon: _scanning
                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.bluetooth_searching),
                      label: Text(t['printerSettingsAdmin.searchButton']!),
                    ),
                  ],
                ),
                if (draft.bluetoothAddress != null)
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: ListTile(
                      title: Text(trf(t['printerSettingsAdmin.currentlySelected']!, {'name': draft.bluetoothName ?? draft.bluetoothAddress ?? ''})),
                    ),
                  ),
                // iOS-only — classic Bluetooth SPP (Android) has no
                // withResponse/withoutResponse distinction, this is purely
                // a BLE GATT write-type choice (see BluetoothWriteMode's
                // doc comment). "سريع" prints noticeably faster; "آمن"
                // falls back to it if a specific printer unit ever drops
                // fast-mode writes.
                if (!kIsWeb && Platform.isIOS) ...[
                  const SizedBox(height: 12),
                  Text(t['printerSettingsAdmin.printModeHeading']!, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  SegmentedButton<BluetoothWriteMode>(
                    segments: [
                      ButtonSegment(value: BluetoothWriteMode.fast, label: Text(t['printerSettingsAdmin.fastMode']!)),
                      ButtonSegment(value: BluetoothWriteMode.safe, label: Text(t['printerSettingsAdmin.safeMode']!)),
                    ],
                    selected: {draft.bluetoothWriteMode},
                    onSelectionChanged: (selection) {
                      setState(() => _draft = draft.copyWith(bluetoothWriteMode: selection.first));
                    },
                  ),
                ],
                const SizedBox(height: 8),
                Text(t['printerSettingsAdmin.pairedDevicesHeading']!, style: Theme.of(context).textTheme.titleSmall),
                for (final d in _pairedDevices)
                  Card(
                    child: ListTile(
                      title: Text(d.name.isEmpty ? d.address : d.name),
                      subtitle: Directionality(textDirection: TextDirection.ltr, child: Text(d.address)),
                      trailing: OutlinedButton(
                        // Same infinite-width theme fix as the FilledButtons above —
                        // OutlinedButtonThemeData also defaults to Size.fromHeight(44).
                        style: OutlinedButton.styleFrom(minimumSize: const Size(64, 36)),
                        onPressed: () => _selectBluetoothDevice(d),
                        child: Text(t['printerSettingsAdmin.selectButton']!),
                      ),
                    ),
                  ),
                if (_discovered.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(t['printerSettingsAdmin.discoveredDevicesHeading']!, style: Theme.of(context).textTheme.titleSmall),
                  for (final d in _discovered.values)
                    Card(
                      child: ListTile(
                        title: Text(d.name.isEmpty ? d.address : d.name),
                        subtitle: Directionality(textDirection: TextDirection.ltr, child: Text(d.address)),
                        trailing: OutlinedButton(
                          style: OutlinedButton.styleFrom(minimumSize: const Size(64, 36)),
                          onPressed: () => _pair(d),
                          child: Text(t['printerSettingsAdmin.pairButton']!),
                        ),
                      ),
                    ),
                ],
              ],
              if (draft.connectionType == PrinterConnectionType.usb) ...[
                Row(
                  children: [
                    Expanded(child: Text(t['printerSettingsAdmin.usbConnectedHeading']!, style: Theme.of(context).textTheme.titleMedium)),
                    FilledButton.icon(
                      // Same infinite-width fix as the Bluetooth "بحث" button above.
                      style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
                      onPressed: _loadingUsb ? null : _loadUsbDevices,
                      icon: _loadingUsb
                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh),
                      label: Text(t['printerSettingsAdmin.refreshButton']!),
                    ),
                  ],
                ),
                if (draft.usbDeviceName != null)
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: ListTile(title: Text(trf(t['printerSettingsAdmin.currentlySelected']!, {'name': draft.usbDeviceName ?? ''}))),
                  ),
                if (_usbDevices.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(t['printerSettingsAdmin.noUsbDevices']!),
                  ),
                for (final d in _usbDevices)
                  Card(
                    child: ListTile(
                      title: Text(d.productName ?? d.deviceName),
                      subtitle: Directionality(textDirection: TextDirection.ltr, child: Text(d.deviceName)),
                      trailing: OutlinedButton(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(64, 36)),
                        onPressed: () => _selectUsbDevice(d),
                        child: Text(t['printerSettingsAdmin.selectButton']!),
                      ),
                    ),
                  ),
              ],
              ],
              const SizedBox(height: 24),
              Text(t['printerSettingsAdmin.paperSizeHeading']!, style: Theme.of(context).textTheme.titleMedium),
              RadioGroup<int>(
                groupValue: draft.paperWidthMm,
                onChanged: (v) {
                  if (v != null) setState(() => _draft = draft.copyWith(paperWidthMm: v));
                },
                child: Column(
                  children: [
                    RadioListTile<int>(title: Text(t['printerSettingsAdmin.paper58mm']!), value: 58),
                    RadioListTile<int>(title: Text(t['printerSettingsAdmin.paper80mm']!), value: 80),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(t['printerSettingsAdmin.save']!),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The slip "طباعة تجريبية" prints: Arabic text, a solid bar and a box
/// edge to edge, so width, darkness and Arabic shaping are all visible.
class _TestSlip extends StatelessWidget {
  const _TestSlip({required this.widthDots, required this.title});

  final int widthDots;
  final String title;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: Colors.black, fontSize: 22);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        width: widthDots.toDouble(),
        color: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: style.copyWith(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(DateTime.now().toString().substring(0, 16), style: style, textDirection: TextDirection.ltr),
            Text('$widthDots dots', style: style, textDirection: TextDirection.ltr),
            const SizedBox(height: 8),
            Container(height: 16, color: Colors.black),
            const SizedBox(height: 8),
            Container(height: 40, decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 3))),
          ],
        ),
      ),
    );
  }
}
