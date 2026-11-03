package com.dentalclinic.dental_clinic_app

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Tells the Dart side whether this is a weak device (2026-11-03, by
 * request: the app was very slow on the clinic's POS terminals, e.g. the
 * Q2 on Android 8.1). device_perf.dart then turns off the costly
 * effects (glass blur, long splash, zoom page transitions).
 */
class DevicePerfPlugin(private val context: Context, messenger: BinaryMessenger) {
    init {
        MethodChannel(messenger, "dental/device_perf").setMethodCallHandler { call, result ->
            when (call.method) {
                "info" -> result.success(info())
                else -> result.notImplemented()
            }
        }
    }

    private fun info(): Map<String, Any> {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val mem = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
        val totalMb = mem.totalMem / (1024 * 1024)
        val cores = Runtime.getRuntime().availableProcessors()
        val lowEnd = am.isLowRamDevice ||
            totalMb < 3000 ||
            cores <= 4 ||
            Build.VERSION.SDK_INT < Build.VERSION_CODES.P
        return mapOf(
            "lowEnd" to lowEnd,
            "totalMb" to totalMb,
            "cores" to cores,
            "sdk" to Build.VERSION.SDK_INT,
            "model" to (Build.MODEL ?: ""),
        )
    }
}
