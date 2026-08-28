import CoreBluetooth
import Flutter
import UIKit

/// iOS printing counterpart to `PosPrinterPlugin.kt` (Android) — same two
/// channel names, so `pos_printer_service.dart` needs no changes. Android
/// speaks classic Bluetooth SPP, a vendor AIDL SDK, and USB host — none of
/// which iOS can reach for a non-MFi device. The only third-party-usable
/// Bluetooth API on iOS is CoreBluetooth (BLE), so this plugin only ever
/// implements the `"bluetooth"` connection type; `"builtin"`/`"usb"` fail
/// with a clear error (see `handlePrintTicket`).
///
/// The real printer this targets (a generic "58E" thermal receipt printer,
/// already in production use via the Android path) was confirmed live via
/// a LightBlue BLE scan to expose GATT service `0xFF00` (characteristics
/// `0xFF01` notify / `0xFF02` write+writeWithoutResponse / `0xFF03` notify)
/// — the extremely common generic-Chinese-BLE-serial-module pattern used by
/// countless cheap ESC/POS BLE printers — plus an alternate service `0x18F0`
/// (`0x2AF0` notify / `0x2AF1` write). Both are tried, FF00 first.
///
/// Its advertisement packet does NOT include a service UUID (confirmed via
/// the same scan), so scanning must not filter by service — see
/// `startScan()`.
final class PosPrinterPlugin: NSObject, FlutterStreamHandler, CBCentralManagerDelegate, CBPeripheralDelegate {
    private let channel: FlutterMethodChannel
    private let scanEventChannel: FlutterEventChannel

    private var centralManager: CBCentralManager!
    private var discoveredPeripherals: [String: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var usesWriteWithoutResponse = false
    /// User-selectable via printer settings ("سريع"/"آمن" — see
    /// `BluetoothWriteMode` on the Dart side). Only meaningful for
    /// `printTicket`; `pairDevice`'s connect-probe never writes anything.
    private var preferFastWrite = true

    private var scanEventSink: FlutterEventSink?

    /// One in-flight connect-chain at a time — either a `printTicket` (with
    /// bytes queued to write once connected) or a `pairDevice` probe (no
    /// bytes, just proves the GATT profile resolves and disconnects).
    private var pendingResult: FlutterResult?
    private var pendingPrintPayload: (pngData: Data, maxDots: Int)?
    private var isPairProbe = false

    private var connectTimeoutTimer: Timer?
    private var writeStallTimer: Timer?

    private var writeChunks: [Data] = []
    private var writeChunkIndex = 0

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
        scanEventChannel = FlutterEventChannel(name: Self.scanEventsChannelName, binaryMessenger: messenger)
        super.init()
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
        scanEventChannel.setStreamHandler(self)
    }

    private func ensureCentralManager() -> CBCentralManager {
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }
        return centralManager
    }

    // MARK: - Method channel dispatch

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "printTicket":
            handlePrintTicket(call, result: result)
        case "getPrinterStatus":
            // Android's value is a passthrough to the vendor AIDL service's
            // own status getter — a builtin-only concept with no BLE
            // equivalent. Nothing calls this outside builtin-only flows;
            // -1 matches Kotlin's own "service isn't bound" fallback.
            result(-1)
        case "listPairedDevices":
            // BLE has no OS-level "bonded devices" list an app can
            // enumerate the way classic-Bluetooth `bondedDevices` works —
            // only peripherals this app has itself discovered/connected to,
            // retrievable by identifier, not by an "all paired" query.
            result([])
        case "pairDevice":
            handlePairDevice(call, result: result)
        case "listUsbDevices":
            result([])
        case "requestUsbPermission":
            result(false)
        case "isBluetoothEnabled":
            result(ensureCentralManager().state == .poweredOn)
        case "requestEnableBluetooth":
            // iOS has no programmatic "turn on Bluetooth" API — the user
            // must do it themselves via Settings/Control Center. Dart's
            // printTicket() throws BluetoothDisabledException regardless of
            // this call's outcome, so a no-op success here matches
            // Android's own documented "no completion, user re-taps طباعة"
            // behavior, just without an in-between system dialog.
            result(nil)
        case "isLocationEnabled":
            // BLE scanning has never required Location on iOS — that's an
            // Android classic-Bluetooth-discovery-only historical quirk.
            result(true)
        case "openLocationSettings":
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Printing

    private func handlePrintTicket(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any], let bytes = args["pngBytes"] as? FlutterStandardTypedData else {
            result(FlutterError(code: "bad_args", message: "pngBytes missing", details: nil))
            return
        }
        let maxDots = (args["paperWidthDots"] as? NSNumber)?.intValue ?? 384
        let connectionType = args["connectionType"] as? String ?? "builtin"

        guard connectionType == "bluetooth" else {
            result(FlutterError(code: "unsupported_connection_type", message: "هذا النوع من الاتصال غير متاح على iOS", details: nil))
            return
        }
        guard let address = args["bluetoothAddress"] as? String else {
            result(FlutterError(code: "bad_args", message: "عنوان بلوتوث مفقود", details: nil))
            return
        }
        if pendingResult != nil {
            finish(false, error: "طلب طباعة آخر قيد التنفيذ")
        }

        // "safe" opts out of .withoutResponse even when the characteristic
        // supports it — see BluetoothWriteMode's Dart-side doc comment.
        preferFastWrite = (args["bluetoothWriteMode"] as? String) != "safe"

        pendingResult = result
        pendingPrintPayload = (bytes.data, maxDots)
        isPairProbe = false
        beginConnectChain(address: address)
    }

    private func handlePairDevice(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any], let address = args["address"] as? String else {
            result(FlutterError(code: "bad_args", message: "address missing", details: nil))
            return
        }
        if pendingResult != nil {
            finish(false, error: "عملية اقتران أخرى قيد التنفيذ")
        }
        pendingResult = result
        pendingPrintPayload = nil
        isPairProbe = true
        beginConnectChain(address: address)
    }

    private func beginConnectChain(address: String) {
        let manager = ensureCentralManager()
        guard manager.state == .poweredOn else {
            finish(false, error: "البلوتوث مغلق — شغّله لتفعيل الطباعة")
            return
        }

        let peripheral: CBPeripheral?
        if let cached = discoveredPeripherals[address] {
            peripheral = cached
        } else if let uuid = UUID(uuidString: address) {
            peripheral = manager.retrievePeripherals(withIdentifiers: [uuid]).first
        } else {
            peripheral = nil
        }

        guard let target = peripheral else {
            finish(false, error: "لم يتم العثور على الطابعة — أعد البحث عنها")
            return
        }

        connectedPeripheral = target
        target.delegate = self

        connectTimeoutTimer?.invalidate()
        connectTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            self?.finish(false, error: "تعذر الاتصال بالطابعة — تأكد أنها قريبة وقيد التشغيل")
        }

        manager.connect(target, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.ff00ServiceUUID, Self.altServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        finish(false, error: "تعذر الاتصال بالطابعة: \(error?.localizedDescription ?? "خطأ غير معروف")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // A disconnect while a result is still pending (not one we
        // triggered ourselves on success/failure) means the printer went
        // away mid-operation — fail cleanly instead of leaving the Dart
        // Future hanging.
        if pendingResult != nil {
            finish(false, error: "انقطع الاتصال بالطابعة")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            finish(false, error: "تعذر قراءة خدمات الطابعة: \(error.localizedDescription)")
            return
        }
        guard let services = peripheral.services, !services.isEmpty else {
            finish(false, error: "الطابعة لا تستخدم بروتوكولاً معروفًا")
            return
        }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            finish(false, error: "تعذر قراءة خصائص الطابعة: \(error.localizedDescription)")
            return
        }
        guard let characteristics = service.characteristics else { return }

        // FF00 takes priority over the alternate 18F0 service — see the
        // class doc for why both exist on this hardware.
        if service.uuid == Self.ff00ServiceUUID {
            if let write = characteristics.first(where: { $0.uuid == Self.ff02CharUUID }) {
                resolveWriteCharacteristic(write)
            }
        } else if service.uuid == Self.altServiceUUID, writeCharacteristic == nil {
            if let write = characteristics.first(where: { $0.uuid == Self.altWriteCharUUID }) {
                resolveWriteCharacteristic(write)
            }
        }
    }

    private func resolveWriteCharacteristic(_ characteristic: CBCharacteristic) {
        guard writeCharacteristic == nil else { return }
        writeCharacteristic = characteristic
        // Prefer .withoutResponse when the characteristic supports it (this
        // hardware's FF02/2AF1 both do) and the user hasn't opted into
        // "آمن" (safe) mode in printer settings — confirmed live
        // (2026-08-28) that printing works reliably either way, and
        // .withResponse's per-chunk ack round-trip made a full ticket
        // noticeably slower than Android's classic-Bluetooth SPP stream.
        // Backpressure still applies via canSendWriteWithoutResponse/
        // peripheralIsReady below even in fast mode, so this isn't an
        // unthrottled firehose — just fewer round trips than waiting for
        // an explicit ack on every single chunk. A characteristic that
        // doesn't support .writeWithoutResponse at all still forces safe
        // mode regardless of the setting, since fast isn't actually possible.
        usesWriteWithoutResponse = preferFastWrite && characteristic.properties.contains(.writeWithoutResponse)

        connectTimeoutTimer?.invalidate()
        connectTimeoutTimer = nil

        if isPairProbe {
            connectedPeripheral?.delegate = nil
            let peripheralToDisconnect = connectedPeripheral
            let successResult = pendingResult
            pendingResult = nil
            connectedPeripheral = nil
            writeCharacteristic = nil
            successResult?(true)
            if let p = peripheralToDisconnect {
                ensureCentralManager().cancelPeripheralConnection(p)
            }
            return
        }

        guard let payload = pendingPrintPayload, let peripheral = connectedPeripheral else {
            finish(false, error: "لا توجد بيانات طباعة")
            return
        }
        let raster = Self.bitmapToEscPosRaster(pngData: payload.pngData, maxDotsPerLine: payload.maxDots)
        guard !raster.isEmpty else {
            finish(false, error: "تعذر فك ترميز الصورة")
            return
        }

        let writeType: CBCharacteristicWriteType = usesWriteWithoutResponse ? .withoutResponse : .withResponse
        let chunkSize = max(peripheral.maximumWriteValueLength(for: writeType), 20)
        writeChunks = stride(from: 0, to: raster.count, by: chunkSize).map { offset in
            raster.subdata(in: offset..<min(offset + chunkSize, raster.count))
        }
        writeChunkIndex = 0
        sendNextChunk()
    }

    private func sendNextChunk() {
        guard let peripheral = connectedPeripheral, let characteristic = writeCharacteristic else {
            finish(false, error: "انقطع الاتصال أثناء الطباعة")
            return
        }
        guard writeChunkIndex < writeChunks.count else {
            // All chunks sent — the printer buffers asynchronously, an
            // early disconnect truncates the job (same physical firmware
            // behavior as the Android path), so wait before closing.
            writeStallTimer?.invalidate()
            writeStallTimer = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.finish(true, error: nil)
            }
            return
        }

        writeStallTimer?.invalidate()
        writeStallTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            self?.finish(false, error: "توقفت الطابعة عن الاستجابة أثناء الطباعة")
        }

        let chunk = writeChunks[writeChunkIndex]
        if usesWriteWithoutResponse {
            if peripheral.canSendWriteWithoutResponse {
                peripheral.writeValue(chunk, for: characteristic, type: .withoutResponse)
                writeChunkIndex += 1
                sendNextChunk()
            }
            // else: wait for peripheralIsReady(toSendWriteWithoutResponse:)
        } else {
            peripheral.writeValue(chunk, for: characteristic, type: .withResponse)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic === writeCharacteristic else { return }
        if let error = error {
            finish(false, error: "فشلت الطباعة: \(error.localizedDescription)")
            return
        }
        writeChunkIndex += 1
        sendNextChunk()
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        sendNextChunk()
    }

    private func finish(_ success: Bool, error: String?) {
        connectTimeoutTimer?.invalidate()
        connectTimeoutTimer = nil
        writeStallTimer?.invalidate()
        writeStallTimer = nil

        let result = pendingResult
        pendingResult = nil
        pendingPrintPayload = nil
        writeChunks = []
        writeChunkIndex = 0

        if let peripheral = connectedPeripheral {
            peripheral.delegate = nil
            ensureCentralManager().cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        writeCharacteristic = nil

        guard let result = result else { return }
        if success {
            result(nil)
        } else {
            result(FlutterError(code: "print_failed", message: error, details: nil))
        }
    }

    // MARK: - Scanning (EventChannel)

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        scanEventSink = events
        let manager = ensureCentralManager()
        guard manager.state == .poweredOn else {
            events(FlutterError(code: "bluetooth_disabled", message: "البلوتوث مغلق — شغّله للبحث عن طابعات", details: nil))
            return nil
        }
        // Must scan for ALL peripherals (no service filter) — this
        // printer's advertisement packet doesn't include its service UUID
        // (confirmed via LightBlue), so filtering here would make it
        // permanently invisible to scan.
        manager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        centralManager?.stopScan()
        scanEventSink = nil
        return nil
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        discoveredPeripherals[peripheral.identifier.uuidString] = peripheral
        scanEventSink?(["name": peripheral.name ?? "", "address": peripheral.identifier.uuidString])
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // Real bug class this guards against (mirroring the Kotlin
        // plugin's own comment): Bluetooth turning off mid-scan should
        // surface as a clean error instead of the scan silently going
        // nowhere.
        if central.state != .poweredOn, scanEventSink != nil {
            central.stopScan()
            scanEventSink?(FlutterError(code: "bluetooth_disabled", message: "البلوتوث مغلق — شغّله للبحث عن طابعات", details: nil))
            scanEventSink = nil
        }
    }

    // MARK: - ESC/POS raster (ported from PosPrinterPlugin.kt's bitmapToEscPosRaster)

    /// Byte-for-byte the same algorithm as the Android plugin's
    /// `bitmapToEscPosRaster()` — ESC/POS raster bit-image (`GS v 0`), one
    /// bit per dot, rows padded to whole bytes, MSB leftmost, darker-than-
    /// mid-grey non-transparent pixels become printed dots, `ESC d 8`
    /// trailing feed (doubled from 4 on this exact physical printer to
    /// clear the tear bar past the QR code — a hardware fact, not an OS
    /// detail, so kept identical here).
    private static func bitmapToEscPosRaster(pngData: Data, maxDotsPerLine: Int) -> Data {
        guard let image = UIImage(data: pngData)?.cgImage else { return Data() }

        let bitmapWidth = image.width
        let bitmapHeight = image.height
        let width = min(bitmapWidth, maxDotsPerLine)
        let height = bitmapHeight
        let bytesPerRow = (width + 7) / 8

        var pixelData = [UInt8](repeating: 0, count: bitmapWidth * bitmapHeight * 4)
        guard let context = CGContext(
            data: &pixelData,
            width: bitmapWidth,
            height: bitmapHeight,
            bitsPerComponent: 8,
            bytesPerRow: bitmapWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return Data()
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: bitmapWidth, height: bitmapHeight))

        var out = Data()
        out.append(contentsOf: [0x1B, 0x40]) // ESC @ — initialize
        out.append(contentsOf: [0x1D, 0x76, 0x30, 0x00]) // GS v 0, mode 0
        out.append(UInt8(bytesPerRow & 0xFF))
        out.append(UInt8((bytesPerRow >> 8) & 0xFF))
        out.append(UInt8(height & 0xFF))
        out.append(UInt8((height >> 8) & 0xFF))

        for y in 0..<height {
            for xByte in 0..<bytesPerRow {
                var b: UInt8 = 0
                for bit in 0..<8 {
                    let x = xByte * 8 + bit
                    if x >= width { continue }
                    let offset = (y * bitmapWidth + x) * 4
                    let r = Int(pixelData[offset])
                    let g = Int(pixelData[offset + 1])
                    let bl = Int(pixelData[offset + 2])
                    let alpha = Int(pixelData[offset + 3])
                    let luminance = (r * 299 + g * 587 + bl * 114) / 1000
                    if alpha > 128 && luminance < 160 {
                        b |= UInt8(0x80 >> bit)
                    }
                }
                out.append(b)
            }
        }

        out.append(contentsOf: [0x1B, 0x64, 0x08]) // ESC d 8 — feed 8 lines
        return out
    }

    // MARK: - Constants

    private static let channelName = "com.dentalclinic.dental_clinic_app/pos_printer"
    private static let scanEventsChannelName = "com.dentalclinic.dental_clinic_app/pos_printer/bt_scan_events"
    private static let ff00ServiceUUID = CBUUID(string: "FF00")
    private static let ff02CharUUID = CBUUID(string: "FF02")
    private static let altServiceUUID = CBUUID(string: "18F0")
    private static let altWriteCharUUID = CBUUID(string: "2AF1")
}
