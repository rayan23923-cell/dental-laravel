package com.dentalclinic.dental_clinic_app

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
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
                "check" -> {
                    val path = call.argument<String>("path")
                    result.success(if (path == null) "corrupt" else check(File(path)))
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

    /**
     * Checks a downloaded update before the system installer sees it
     * (2026-10-31): Android only says "package appears to be invalid" for
     * a broken download and for an APK that can't replace this app, so the
     * app tells which one it is. Returns "ok", "corrupt" (not a readable
     * APK: cut off or not an APK at all), "package" (another app),
     * "older" (not newer than this one) or "signature" (signed with
     * another key, e.g. an install from before 1.1.110: only removing the
     * app and installing it again helps).
     */
    @Suppress("DEPRECATION")
    private fun check(apk: File): String {
        if (!apk.isFile || apk.length() == 0L) return "corrupt"
        val pm = activity.packageManager
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val archive = try {
            pm.getPackageArchiveInfo(apk.absolutePath, flags)
        } catch (e: Exception) {
            null
        } ?: return "corrupt"
        if (archive.packageName != activity.packageName) return "package"
        val installed = try {
            pm.getPackageInfo(activity.packageName, flags)
        } catch (e: Exception) {
            return "ok"
        }
        val newCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) archive.longVersionCode else archive.versionCode.toLong()
        val oldCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) installed.longVersionCode else installed.versionCode.toLong()
        if (newCode < oldCode) return "older"
        val newCerts = certificates(archive)
        val oldCerts = certificates(installed)
        // Unknown on either side: let the installer decide.
        if (newCerts.isEmpty() || oldCerts.isEmpty()) return "ok"
        return if (newCerts == oldCerts) "ok" else "signature"
    }

    @Suppress("DEPRECATION")
    private fun certificates(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signing = info.signingInfo ?: return emptySet()
            if (signing.hasMultipleSigners()) signing.apkContentsSigners else signing.signingCertificateHistory
        } else {
            info.signatures
        } ?: return emptySet()
        return signatures.map { it.toCharsString() }.toSet()
    }

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
