package com.dentalclinic.dental_clinic_app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * In-app updates without a store (2026-10-17, by request): the app
 * downloads the new APK from the clinic server (app_update_checker.dart)
 * and hands it to Android's package installer, which shows the usual
 * "install this update?" confirmation. Android only allows it once the
 * user lets this app install apps ("Install unknown apps"), so the Dart
 * side asks for that first.
 */
class AppUpdatePlugin(private val activity: Activity, messenger: BinaryMessenger) {
    init {
        MethodChannel(messenger, "dental/app_update").setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstall" -> result.success(canInstall())
                "openInstallSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        activity.startActivity(
                            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + activity.packageName))
                        )
                    }
                    result.success(null)
                }
                "install" -> {
                    val path = call.argument<String>("path")
                    if (path == null || !File(path).exists()) {
                        result.error("missing", "Update file not found", null)
                    } else {
                        try {
                            install(File(path))
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("install", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun canInstall(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || activity.packageManager.canRequestPackageInstalls()

    private fun install(apk: File) {
        val uri = FileProvider.getUriForFile(activity, activity.packageName + ".updates", apk)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        activity.startActivity(intent)
    }
}

/** Its own class so it never clashes with a plugin's FileProvider entry. */
class UpdateFileProvider : FileProvider()
