package com.dentalclinic.dental_clinic_app

import android.app.PendingIntent
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.ServiceConnection
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.Log
import com.iposprinter.iposprinterservice.IPosPrinterCallback
import com.iposprinter.iposprinterservice.IPosPrinterService
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.UUID

/**
 * Prints the registration ticket, and (new) generalizes beyond the one
 * built-in POS printer this originally targeted: a user can now instead
 * choose an external Bluetooth printer (scan/pair, own PIN dialog handled
 * by the OS) or a USB printer, and a paper width (58mm/384 dots or
 * 80mm/576 dots — see `PrinterSettings.dotsPerLine`). The Dart side reads
 * the stored preference and passes it on every `printTicket` call; the
 * three connection types below are peers, not a fallback chain into each
 * other — only the `builtin` type has its own internal AIDL-then-Bluetooth
 * fallback, unchanged from before.
 *
 * `builtin` (the default, and the only type that existed before this):
 * the vendor SDK ("2C-POS-V1 Mobile POS Printer SDK") documents **two**
 * ways to reach the same physical printer, tried in order:
 *
 *  1. **AIDL** — bind `com.iposprinter.iposprinterservice` and call
 *     `IPosPrinterService`. See `IPosPrinterService.aidl`'s doc comment
 *     for how that interface was obtained (the vendor's own PDF omitted
 *     the callback parameter every method takes; the real signatures came
 *     from an open-source plugin wrapping this exact service).
 *  2. **Bluetooth SPP** — the same built-in printer is also exposed by
 *     the system as a pre-bonded virtual Bluetooth device named
 *     "IposPrinter" (confirmed present on this device at
 *     00:AA:11:BB:22:CC, the exact address the vendor doc uses in its own
 *     example), speaking plain ESC/POS over an RFCOMM socket.
 *
 * The AIDL path is tried first and the Bluetooth path is the fallback,
 * because on this unit AIDL `printerInit()` returns an explicit failure
 * via its callback even though the service binds fine and
 * `getPrinterStatus()` reports 0 (PRINTER_NORMAL) — confirmed live with
 * on-device logging, not assumed.
 *
 * `bluetooth`/`usb`: an explicitly-chosen external printer (from the new
 * printer-settings screen), speaking plain ESC/POS directly — no AIDL
 * involved, since that's this device's own built-in printer's protocol
 * only.
 *
 * Every connection type sends the ticket as a **bitmap**, never as
 * printer text: the built-in printer's fonts are Chinese GBK/GB18030 +
 * ASCII only (no Arabic glyphs — confirmed from the raw font resources
 * bundled in its own APK), so the ticket is laid out and shaped by
 * Flutter (`ticket_widget.dart`), rasterized to PNG, and converted here
 * to either an `android.graphics.Bitmap` (AIDL) or an ESC/POS raster
 * block (`GS v 0`, Bluetooth/USB).
 *
 * Runtime Bluetooth permissions (`BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT` on
 * API 31+) are requested Dart-side via `permission_handler` before any
 * scan/pair call reaches this plugin — this class only holds a plain
 * `Context` (see `MainActivity.kt`), not an `Activity`, so it can't
 * launch a permission-request dialog itself.
 */
class PosPrinterPlugin(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val scanEventChannel = EventChannel(messenger, SCAN_EVENTS_CHANNEL_NAME)
    private val mainHandler = Handler(Looper.getMainLooper())

    private var service: IPosPrinterService? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingPngBytes: ByteArray? = null
    private var pendingPaperWidthDots: Int = MAX_DOTS_PER_LINE

    private var scanEventSink: EventChannel.EventSink? = null
    private var scanReceiver: BroadcastReceiver? = null

    private var pairingReceiver: BroadcastReceiver? = null
    private var pairingResult: MethodChannel.Result? = null
    private var pairingAddress: String? = null

    private var usbPermissionReceiver: BroadcastReceiver? = null
    private var usbPermissionResult: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(this)
        scanEventChannel.setStreamHandler(this)
    }

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            Log.d(TAG, "onServiceConnected")
            service = IPosPrinterService.Stub.asInterface(binder)
            val bytes = pendingPngBytes
            if (bytes != null) {
                pendingPngBytes = null
                beginPrint(bytes, pendingPaperWidthDots)
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            Log.d(TAG, "onServiceDisconnected")
            service = null
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "printTicket" -> handlePrintTicket(call, result)
            "getPrinterStatus" -> result.success(service?.printerStatus ?: -1)
            "listPairedDevices" -> result.success(listPairedDevicesInternal())
            "pairDevice" -> handlePairDevice(call, result)
            "listUsbDevices" -> result.success(listUsbDevicesInternal())
            "requestUsbPermission" -> handleRequestUsbPermission(call, result)
            // Bluetooth/Location enabled-state checks + one-tap system
            // prompts — added because scanning silently hung forever when
            // Bluetooth was off (see onListen()'s fix below) and there was
            // no way to fix that from inside the app. context is the
            // plugin's plain applicationContext (not ActivityAware — see
            // the class-level constructor in MainActivity.kt), hence
            // FLAG_ACTIVITY_NEW_TASK on both intents below.
            "isBluetoothEnabled" -> result.success(BluetoothAdapter.getDefaultAdapter()?.isEnabled ?: false)
            "requestEnableBluetooth" -> {
                context.startActivity(
                    Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                result.success(null)
            }
            "isLocationEnabled" -> result.success(isLocationEnabledInternal())
            "openLocationSettings" -> {
                context.startActivity(
                    Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ---------------------------------------------------------------
    // Printing
    // ---------------------------------------------------------------

    private fun handlePrintTicket(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("pngBytes")
        if (bytes == null) {
            result.error("bad_args", "pngBytes missing", null)
            return
        }
        pendingResult = result
        pendingPaperWidthDots = call.argument<Int>("paperWidthDots") ?: MAX_DOTS_PER_LINE
        val connectionType = call.argument<String>("connectionType") ?: "builtin"

        when (connectionType) {
            "bluetooth" -> {
                val address = call.argument<String>("bluetoothAddress")
                val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                if (address == null || bitmap == null) {
                    finish(false, "عنوان بلوتوث مفقود أو تعذر فك ترميز الصورة")
                    return
                }
                printViaBluetoothAddress(bitmap, address, pendingPaperWidthDots)
            }
            "usb" -> {
                val deviceName = call.argument<String>("usbDeviceName")
                val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                if (deviceName == null || bitmap == null) {
                    finish(false, "جهاز USB غير محدد أو تعذر فك ترميز الصورة")
                    return
                }
                printViaUsb(bitmap, deviceName, pendingPaperWidthDots)
            }
            else -> {
                // "builtin" — unchanged AIDL-first/hardcoded-Bluetooth-fallback path.
                if (service != null) {
                    beginPrint(bytes, pendingPaperWidthDots)
                } else {
                    pendingPngBytes = bytes
                    bindPrinterService()
                }
            }
        }
    }

    private fun bindPrinterService() {
        val intent = Intent()
        intent.setPackage("com.iposprinter.iposprinterservice")
        intent.setAction("com.iposprinter.iposprinterservice.IPosPrintService")
        if (!context.bindService(intent, connection, Context.BIND_AUTO_CREATE)) {
            // No AIDL service at all — go straight to Bluetooth with
            // whatever bytes were queued for it.
            val bytes = pendingPngBytes
            pendingPngBytes = null
            if (bytes != null) {
                val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                if (bitmap != null) {
                    printViaBuiltinBluetoothFallback(bitmap)
                    return
                }
            }
            finish(false, "Could not bind IPosPrinterService")
        }
    }

    private fun finish(success: Boolean, error: String?) {
        Log.d(TAG, "finish success=$success error=$error")
        val result = pendingResult ?: return
        pendingResult = null
        if (success) result.success(null) else result.error("print_failed", error, null)
    }

    /** One-shot [IPosPrinterCallback]; [onFailure] lets the caller fall back. */
    private fun callback(step: String, onFailure: () -> Unit, onSuccess: () -> Unit): IPosPrinterCallback {
        return object : IPosPrinterCallback.Stub() {
            override fun onRunResult(isSuccess: Boolean) {
                Log.d(TAG, "$step onRunResult isSuccess=$isSuccess")
                if (isSuccess) onSuccess() else onFailure()
            }

            override fun onReturnString(result: String?) {
                Log.d(TAG, "$step onReturnString result=$result")
            }
        }
    }

    private fun beginPrint(pngBytes: ByteArray, maxDotsPerLine: Int) {
        val bitmap = BitmapFactory.decodeByteArray(pngBytes, 0, pngBytes.size)
        if (bitmap == null) {
            finish(false, "Could not decode PNG bytes")
            return
        }
        Log.d(TAG, "bitmap ${bitmap.width}x${bitmap.height}")

        val svc = service
        if (svc == null) {
            printViaBuiltinBluetoothFallback(bitmap)
            return
        }

        try {
            val status = svc.printerStatus
            Log.d(TAG, "printerStatus=$status")

            // Any AIDL step failing falls through to the Bluetooth route
            // rather than surfacing an error — see the class doc for why
            // this unit needs that fallback in practice.
            val fallback = {
                Log.d(TAG, "AIDL path failed, falling back to Bluetooth")
                printViaBuiltinBluetoothFallback(bitmap)
            }

            svc.printerInit(callback("printerInit", fallback) {
                svc.setPrinterPrintAlignment(1, callback("setPrinterPrintAlignment", fallback) {
                    svc.printBitmap(1, 10, bitmap, callback("printBitmap", fallback) {
                        svc.printerPerformPrint(150, callback("printerPerformPrint", fallback) {
                            finish(true, null)
                        })
                    })
                })
            })
        } catch (e: Exception) {
            Log.e(TAG, "AIDL beginPrint threw, falling back to Bluetooth", e)
            printViaBuiltinBluetoothFallback(bitmap)
        }
    }

    /** The original hardcoded-device fallback for the `builtin` connection type only. */
    private fun printViaBuiltinBluetoothFallback(bitmap: Bitmap) {
        val adapter = BluetoothAdapter.getDefaultAdapter()
        if (adapter == null) {
            finish(false, "No Bluetooth adapter on this device")
            return
        }
        if (!adapter.isEnabled) {
            finish(false, "البلوتوث مغلق — شغّله لتفعيل الطباعة")
            return
        }
        val device = adapter.bondedDevices?.firstOrNull {
            it.address.equals(IPOS_BT_ADDRESS, ignoreCase = true) || it.name == IPOS_BT_NAME
        }
        if (device == null) {
            finish(false, "الطابعة \"$IPOS_BT_NAME\" غير مقترنة بالبلوتوث")
            return
        }
        Log.d(TAG, "builtin bluetooth fallback device ${device.name} ${device.address}")
        printViaBluetoothDevice(bitmap, device, pendingPaperWidthDots)
    }

    /** An explicitly-chosen external Bluetooth printer (must already be bonded — see [handlePairDevice]). */
    private fun printViaBluetoothAddress(bitmap: Bitmap, address: String, maxDotsPerLine: Int) {
        val adapter = BluetoothAdapter.getDefaultAdapter()
        if (adapter == null) {
            finish(false, "No Bluetooth adapter on this device")
            return
        }
        if (!adapter.isEnabled) {
            finish(false, "البلوتوث مغلق — شغّله لتفعيل الطباعة")
            return
        }
        val device = try {
            adapter.getRemoteDevice(address)
        } catch (e: IllegalArgumentException) {
            finish(false, "عنوان بلوتوث غير صالح: $address")
            return
        }
        printViaBluetoothDevice(bitmap, device, maxDotsPerLine)
    }

    private fun printViaBluetoothDevice(bitmap: Bitmap, device: BluetoothDevice, maxDotsPerLine: Int) {
        Thread {
            var socket: BluetoothSocket? = null
            try {
                val adapter = BluetoothAdapter.getDefaultAdapter()
                adapter?.cancelDiscovery()
                socket = device.createRfcommSocketToServiceRecord(SPP_UUID)
                socket.connect()
                Log.d(TAG, "bluetooth socket connected to ${device.address}")

                val payload = bitmapToEscPosRaster(bitmap, maxDotsPerLine)
                Log.d(TAG, "writing ${payload.size} ESC/POS bytes")
                socket.outputStream.write(payload)
                socket.outputStream.flush()
                // The printer buffers asynchronously; closing the socket
                // immediately can truncate the job.
                Thread.sleep(2000)

                mainHandler.post { finish(true, null) }
            } catch (e: Exception) {
                Log.e(TAG, "bluetooth print failed", e)
                mainHandler.post { finish(false, "Bluetooth: ${e.message}") }
            } finally {
                try {
                    socket?.close()
                } catch (_: Exception) {
                }
            }
        }.start()
    }

    /**
     * A USB ESC/POS thermal printer — genuinely new native code, not an
     * extension of the AIDL/Bluetooth paths above. Uses Android's USB
     * host API (`UsbManager`); the printer must already have been granted
     * permission via [handleRequestUsbPermission]. Finds the first
     * bulk-OUT endpoint on any interface rather than assuming interface 0,
     * since that's the standard shape for a USB printer-class device but
     * not guaranteed to be interface 0 on every unit.
     */
    private fun printViaUsb(bitmap: Bitmap, deviceName: String, maxDotsPerLine: Int) {
        Thread {
            var connection: UsbDeviceConnection? = null
            try {
                val usbManager = context.getSystemService(Context.USB_SERVICE) as? UsbManager
                val device = usbManager?.deviceList?.values?.firstOrNull { it.deviceName == deviceName }
                if (usbManager == null || device == null) {
                    mainHandler.post { finish(false, "جهاز USB غير موجود") }
                    return@Thread
                }
                if (!usbManager.hasPermission(device)) {
                    mainHandler.post { finish(false, "لا يوجد إذن للوصول إلى جهاز USB") }
                    return@Thread
                }

                var targetInterface: UsbInterface? = null
                var outEndpoint: UsbEndpoint? = null
                for (i in 0 until device.interfaceCount) {
                    val iface = device.getInterface(i)
                    for (e in 0 until iface.endpointCount) {
                        val endpoint = iface.getEndpoint(e)
                        if (endpoint.type == UsbConstants.USB_ENDPOINT_XFER_BULK &&
                            endpoint.direction == UsbConstants.USB_DIR_OUT
                        ) {
                            targetInterface = iface
                            outEndpoint = endpoint
                            break
                        }
                    }
                    if (outEndpoint != null) break
                }

                if (targetInterface == null || outEndpoint == null) {
                    mainHandler.post { finish(false, "تعذر العثور على منفذ إخراج USB على هذه الطابعة") }
                    return@Thread
                }

                connection = usbManager.openDevice(device)
                if (connection == null) {
                    mainHandler.post { finish(false, "تعذر فتح اتصال USB") }
                    return@Thread
                }
                connection.claimInterface(targetInterface, true)

                val payload = bitmapToEscPosRaster(bitmap, maxDotsPerLine)
                Log.d(TAG, "writing ${payload.size} ESC/POS bytes via USB")

                // Bulk transfer in chunks — the endpoint's maxPacketSize
                // caps a single transfer, and a full ticket exceeds it.
                val chunkSize = outEndpoint.maxPacketSize.takeIf { it > 0 } ?: 64
                var offset = 0
                while (offset < payload.size) {
                    val len = minOf(chunkSize, payload.size - offset)
                    val chunk = payload.copyOfRange(offset, offset + len)
                    val sent = connection.bulkTransfer(outEndpoint, chunk, chunk.size, 5000)
                    if (sent < 0) {
                        throw Exception("USB bulk transfer failed at offset $offset")
                    }
                    offset += len
                }

                mainHandler.post { finish(true, null) }
            } catch (e: Exception) {
                Log.e(TAG, "USB print failed", e)
                mainHandler.post { finish(false, "USB: ${e.message}") }
            } finally {
                try {
                    connection?.close()
                } catch (_: Exception) {
                }
            }
        }.start()
    }

    /**
     * ESC/POS raster bit-image (`GS v 0`) — one bit per dot, rows padded
     * to whole bytes, MSB leftmost. Pixels darker than mid-grey (and not
     * transparent) become printed dots. [maxDotsPerLine] is 384 for 58mm
     * paper or 576 for 80mm (see `PrinterSettings.dotsPerLine` — the
     * standard ESC/POS convention at ~8 dots/mm), read from the stored
     * preference rather than hardcoded.
     */
    private fun bitmapToEscPosRaster(bitmap: Bitmap, maxDotsPerLine: Int): ByteArray {
        val width = minOf(bitmap.width, maxDotsPerLine)
        val height = bitmap.height
        val bytesPerRow = (width + 7) / 8
        val pixels = IntArray(bitmap.width * height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, height)

        val out = ByteArrayOutputStream()
        out.write(byteArrayOf(0x1B, 0x40)) // ESC @ — initialize
        out.write(byteArrayOf(0x1D, 0x76, 0x30, 0x00)) // GS v 0, mode 0
        out.write(bytesPerRow and 0xFF)
        out.write((bytesPerRow shr 8) and 0xFF)
        out.write(height and 0xFF)
        out.write((height shr 8) and 0xFF)

        for (y in 0 until height) {
            for (xByte in 0 until bytesPerRow) {
                var b = 0
                for (bit in 0 until 8) {
                    val x = xByte * 8 + bit
                    if (x >= width) continue
                    val px = pixels[y * bitmap.width + x]
                    val alpha = (px ushr 24) and 0xFF
                    val r = (px ushr 16) and 0xFF
                    val g = (px ushr 8) and 0xFF
                    val bl = px and 0xFF
                    val luminance = (r * 299 + g * 587 + bl * 114) / 1000
                    if (alpha > 128 && luminance < 160) b = b or (0x80 shr bit)
                }
                out.write(b)
            }
        }

        // ESC d 8 — feed 8 lines. Was 4: real issue reported on-device
        // (Bluetooth/USB only — the builtin AIDL path doesn't go through
        // this function at all, see its own SDK's print call) — 4 lines
        // at the printer's default ~1/6" line spacing (~17mm) wasn't
        // enough clearance past the QR code for the tear bar, so the
        // user had to manually press the printer's own feed button after
        // every ticket. Doubled to give a real trailing margin.
        out.write(byteArrayOf(0x1B, 0x64, 0x08))
        return out.toByteArray()
    }

    // ---------------------------------------------------------------
    // Bluetooth: paired-device list, scan (EventChannel), pairing
    // ---------------------------------------------------------------

    private fun listPairedDevicesInternal(): List<Map<String, String>> {
        val adapter = BluetoothAdapter.getDefaultAdapter() ?: return emptyList()
        return adapter.bondedDevices?.map { mapOf("name" to (it.name ?: ""), "address" to it.address) }
            ?: emptyList()
    }

    /** Live discovery results, streamed as they arrive — see `pos_printer_service.dart`'s `scanBluetoothDevices()`. */
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        scanEventSink = events
        val adapter = BluetoothAdapter.getDefaultAdapter()
        if (adapter == null) {
            events?.error("no_adapter", "No Bluetooth adapter on this device", null)
            return
        }
        // Real bug, found live: startDiscovery() silently no-ops when
        // Bluetooth is off (returns false, fires neither ACTION_FOUND nor
        // ACTION_DISCOVERY_FINISHED) — the Dart side's "scanning" flag was
        // only ever cleared by one of those two events, so it spun forever.
        // Same isEnabled check already used twice in the print path
        // (printViaBuiltinBluetoothFallback/printViaBluetoothAddress) —
        // just missing here.
        if (!adapter.isEnabled) {
            events?.error("bluetooth_disabled", "البلوتوث مغلق — شغّله للبحث عن طابعات", null)
            return
        }

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                when (intent?.action) {
                    BluetoothDevice.ACTION_FOUND -> {
                        val device = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                        if (device != null) {
                            mainHandler.post {
                                scanEventSink?.success(mapOf("name" to (device.name ?: ""), "address" to device.address))
                            }
                        }
                    }
                    BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                        // null signals "discovery finished" to the Dart side.
                        mainHandler.post { scanEventSink?.success(null) }
                    }
                }
            }
        }
        scanReceiver = receiver
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
        }
        registerReceiverCompat(receiver, filter, exported = true)
        // Return value previously discarded — also false (in addition to
        // adapter being off) if discovery is already running or the OS
        // refuses for some other reason; same "never hangs silently" fix.
        if (!adapter.startDiscovery()) {
            try {
                context.unregisterReceiver(receiver)
            } catch (_: Exception) {
            }
            scanReceiver = null
            events?.error("discovery_failed", "تعذر بدء البحث عن أجهزة البلوتوث", null)
        }
    }

    /** API 28+ has a direct getter; older versions read the legacy Settings.Secure integer. */
    private fun isLocationEnabledInternal(): Boolean {
        val lm = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            lm.isLocationEnabled
        } else {
            Settings.Secure.getInt(
                context.contentResolver,
                Settings.Secure.LOCATION_MODE,
                Settings.Secure.LOCATION_MODE_OFF
            ) != Settings.Secure.LOCATION_MODE_OFF
        }
    }

    override fun onCancel(arguments: Any?) {
        BluetoothAdapter.getDefaultAdapter()?.cancelDiscovery()
        scanReceiver?.let {
            try {
                context.unregisterReceiver(it)
            } catch (_: Exception) {
            }
        }
        scanReceiver = null
        scanEventSink = null
    }

    /**
     * Never builds a custom PIN UI — `createBond()` triggers Android's own
     * `ACTION_PAIRING_REQUEST` system dialog, which handles PIN entry
     * itself. This just waits for `ACTION_BOND_STATE_CHANGED` to resolve
     * the Dart future.
     */
    private fun handlePairDevice(call: MethodCall, result: MethodChannel.Result) {
        val address = call.argument<String>("address")
        if (address == null) {
            result.error("bad_args", "address missing", null)
            return
        }
        val adapter = BluetoothAdapter.getDefaultAdapter()
        val device = try {
            adapter?.getRemoteDevice(address)
        } catch (e: IllegalArgumentException) {
            null
        }
        if (device == null) {
            result.error("bad_args", "invalid address", null)
            return
        }
        if (device.bondState == BluetoothDevice.BOND_BONDED) {
            result.success(true)
            return
        }

        pairingResult = result
        pairingAddress = address

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                if (intent?.action != BluetoothDevice.ACTION_BOND_STATE_CHANGED) return
                val d = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                if (d?.address != pairingAddress) return
                val bondState = intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.BOND_NONE)
                if (bondState == BluetoothDevice.BOND_BONDED || bondState == BluetoothDevice.BOND_NONE) {
                    try {
                        context.unregisterReceiver(this)
                    } catch (_: Exception) {
                    }
                    pairingReceiver = null
                    val res = pairingResult
                    pairingResult = null
                    res?.success(bondState == BluetoothDevice.BOND_BONDED)
                }
            }
        }
        pairingReceiver = receiver
        registerReceiverCompat(receiver, IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED), exported = true)

        val started = device.createBond()
        if (!started) {
            try {
                context.unregisterReceiver(receiver)
            } catch (_: Exception) {
            }
            pairingReceiver = null
            pairingResult = null
            result.success(false)
        }
    }

    // ---------------------------------------------------------------
    // USB: device list, permission
    // ---------------------------------------------------------------

    private fun listUsbDevicesInternal(): List<Map<String, String?>> {
        val usbManager = context.getSystemService(Context.USB_SERVICE) as? UsbManager ?: return emptyList()
        return usbManager.deviceList.values.map { mapOf("deviceName" to it.deviceName, "productName" to it.productName) }
    }

    private fun handleRequestUsbPermission(call: MethodCall, result: MethodChannel.Result) {
        val deviceName = call.argument<String>("deviceName")
        val usbManager = context.getSystemService(Context.USB_SERVICE) as? UsbManager
        val device = usbManager?.deviceList?.values?.firstOrNull { it.deviceName == deviceName }
        if (usbManager == null || device == null) {
            result.error("bad_args", "device not found", null)
            return
        }
        if (usbManager.hasPermission(device)) {
            result.success(true)
            return
        }

        usbPermissionResult = result
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
        val permissionIntent = PendingIntent.getBroadcast(context, 0, Intent(ACTION_USB_PERMISSION), flags)

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                if (intent?.action != ACTION_USB_PERMISSION) return
                try {
                    context.unregisterReceiver(this)
                } catch (_: Exception) {
                }
                usbPermissionReceiver = null
                val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                val res = usbPermissionResult
                usbPermissionResult = null
                res?.success(granted)
            }
        }
        usbPermissionReceiver = receiver
        registerReceiverCompat(receiver, IntentFilter(ACTION_USB_PERMISSION))
        usbManager.requestPermission(device, permissionIntent)
    }

    /**
     * `RECEIVER_EXPORTED`/`RECEIVER_NOT_EXPORTED` is required on API 33+ or
     * `registerReceiver` throws. [exported] must be `true` for the two
     * Bluetooth-scan/pairing receivers above — a real bug, found live via
     * `dumpsys activity broadcasts` on a Honor/Android 13 tablet: broadcasts
     * from `com.android.bluetooth` (uid 1002, the Bluetooth stack process)
     * are NOT treated as "the system" (uid 1000) by the `RECEIVER_NOT_EXPORTED`
     * delivery check on this OS version, so `ACTION_FOUND`/
     * `ACTION_DISCOVERY_FINISHED`/`ACTION_BOND_STATE_CHANGED` were silently
     * marked "Skipped" for this app's receiver — no exception, no error, the
     * scan spinner just never got its terminating event. Kept `false`
     * (unexported, the safer default) for the USB-permission receiver below,
     * since that one only ever receives this app's own self-sent
     * `PendingIntent` broadcast, matching the "same app" exemption instead.
     */
    private fun registerReceiverCompat(receiver: BroadcastReceiver, filter: IntentFilter, exported: Boolean = false) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, if (exported) Context.RECEIVER_EXPORTED else Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }
    }

    companion object {
        private const val CHANNEL_NAME = "com.dentalclinic.dental_clinic_app/pos_printer"
        private const val SCAN_EVENTS_CHANNEL_NAME = "com.dentalclinic.dental_clinic_app/pos_printer/bt_scan_events"
        private const val TAG = "PosPrinterPlugin"
        private const val IPOS_BT_ADDRESS = "00:AA:11:BB:22:CC"
        private const val IPOS_BT_NAME = "IposPrinter"
        private const val MAX_DOTS_PER_LINE = 384
        private const val ACTION_USB_PERMISSION = "com.dentalclinic.dental_clinic_app.USB_PERMISSION"
        private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }
}
