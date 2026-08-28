import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/app_theme.dart';
import '../data/pos_printer_service.dart';
import '../domain/printer_settings.dart';
import 'printer_settings_providers.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يلزم إذن البلوتوث للبحث عن أجهزة.')));
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('بدون إذن الموقع لن تظهر بعض أجهزة البلوتوث القريبة في نتائج البحث هنا، حتى لو ظهرت في إعدادات الجهاز.'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'الإعدادات',
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('البلوتوث مغلق. شغّله للبحث عن طابعات.'),
          action: SnackBarAction(
            label: 'تشغيل',
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
        // Bluetooth turned off *during* an active scan, not just before
        // starting one — same one-tap fix as the pre-scan check above.
        if (e is PlatformException && e.code == 'bluetooth_disabled') {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('البلوتوث مغلق. شغّله للبحث عن طابعات.'),
            action: SnackBarAction(
              label: 'تشغيل',
              textColor: InstagramColors.blue,
              onPressed: () => ref.read(posPrinterServiceProvider).requestEnableBluetooth(),
            ),
          ));
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر البحث: $e')));
      },
    );
  }

  Future<void> _pair(BluetoothDeviceInfo device) async {
    final ok = await ref.read(posPrinterServiceProvider).pairBluetoothDevice(device.address);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم الاقتران بـ ${device.name}.')));
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر الاقتران.')));
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم رفض إذن الوصول لجهاز USB.')));
    }
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(printerSettingsProvider.notifier).save(draft);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ إعدادات الطابعة.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(printerSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات الطابعة')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('تعذر تحميل الإعدادات: $error')),
        data: (settings) {
          _seed(settings);
          final draft = _draft ?? settings;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('نوع الاتصال', style: Theme.of(context).textTheme.titleMedium),
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
                    const ButtonSegment(value: PrinterConnectionType.builtin, label: Text('الطابعة المدمجة')),
                  const ButtonSegment(value: PrinterConnectionType.bluetooth, label: Text('بلوتوث')),
                  if (!kIsWeb && Platform.isAndroid)
                    const ButtonSegment(value: PrinterConnectionType.usb, label: Text('USB')),
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
                    Expanded(child: Text('البحث عن أجهزة بلوتوث', style: Theme.of(context).textTheme.titleMedium)),
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
                      label: const Text('بحث'),
                    ),
                  ],
                ),
                if (draft.bluetoothAddress != null)
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: ListTile(
                      title: Text('المحدد حالياً: ${draft.bluetoothName ?? draft.bluetoothAddress}'),
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
                  Text('وضع الطباعة', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  SegmentedButton<BluetoothWriteMode>(
                    segments: const [
                      ButtonSegment(value: BluetoothWriteMode.fast, label: Text('سريع')),
                      ButtonSegment(value: BluetoothWriteMode.safe, label: Text('آمن')),
                    ],
                    selected: {draft.bluetoothWriteMode},
                    onSelectionChanged: (selection) {
                      setState(() => _draft = draft.copyWith(bluetoothWriteMode: selection.first));
                    },
                  ),
                ],
                const SizedBox(height: 8),
                Text('أجهزة مقترنة', style: Theme.of(context).textTheme.titleSmall),
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
                        child: const Text('تحديد'),
                      ),
                    ),
                  ),
                if (_discovered.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('أجهزة مكتشفة', style: Theme.of(context).textTheme.titleSmall),
                  for (final d in _discovered.values)
                    Card(
                      child: ListTile(
                        title: Text(d.name.isEmpty ? d.address : d.name),
                        subtitle: Directionality(textDirection: TextDirection.ltr, child: Text(d.address)),
                        trailing: OutlinedButton(
                          style: OutlinedButton.styleFrom(minimumSize: const Size(64, 36)),
                          onPressed: () => _pair(d),
                          child: const Text('اقتران'),
                        ),
                      ),
                    ),
                ],
              ],
              if (draft.connectionType == PrinterConnectionType.usb) ...[
                Row(
                  children: [
                    Expanded(child: Text('أجهزة USB المتصلة', style: Theme.of(context).textTheme.titleMedium)),
                    FilledButton.icon(
                      // Same infinite-width fix as the Bluetooth "بحث" button above.
                      style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
                      onPressed: _loadingUsb ? null : _loadUsbDevices,
                      icon: _loadingUsb
                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh),
                      label: const Text('تحديث'),
                    ),
                  ],
                ),
                if (draft.usbDeviceName != null)
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: ListTile(title: Text('المحدد حالياً: ${draft.usbDeviceName}')),
                  ),
                if (_usbDevices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('لا توجد أجهزة USB متصلة حالياً.'),
                  ),
                for (final d in _usbDevices)
                  Card(
                    child: ListTile(
                      title: Text(d.productName ?? d.deviceName),
                      subtitle: Directionality(textDirection: TextDirection.ltr, child: Text(d.deviceName)),
                      trailing: OutlinedButton(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(64, 36)),
                        onPressed: () => _selectUsbDevice(d),
                        child: const Text('تحديد'),
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 24),
              Text('حجم الورق', style: Theme.of(context).textTheme.titleMedium),
              RadioGroup<int>(
                groupValue: draft.paperWidthMm,
                onChanged: (v) {
                  if (v != null) setState(() => _draft = draft.copyWith(paperWidthMm: v));
                },
                child: const Column(
                  children: [
                    RadioListTile<int>(title: Text('58 ملم'), value: 58),
                    RadioListTile<int>(title: Text('80 ملم'), value: 80),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('حفظ'),
              ),
            ],
          );
        },
      ),
    );
  }
}
