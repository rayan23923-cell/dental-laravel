package com.dentalclinic.tv;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Build;
import android.provider.Settings;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

/**
 * "سجل التشغيل التلقائي" (2026-11-02): a short log of what the app saw
 * around boot and wake (broadcasts, service start, attempts to come to the
 * front, when the screen showed), kept in device storage so it works early
 * in boot. Shown from the menu, so the user can tell us where auto-start
 * stops on a TV we cannot reach.
 */
final class Diag {
    private static final int KEEP = 40;

    private Diag() {
    }

    private static SharedPreferences prefs(Context context) {
        Context c = Build.VERSION.SDK_INT >= Build.VERSION_CODES.N
                ? context.createDeviceProtectedStorageContext() : context;
        return c.getSharedPreferences("diag", Context.MODE_PRIVATE);
    }

    static synchronized void log(Context context, String event) {
        try {
            SharedPreferences p = prefs(context);
            String line = new SimpleDateFormat("dd/MM HH:mm:ss", Locale.US).format(new Date())
                    + "  " + event;
            String all = p.getString("log", "");
            String[] lines = all.isEmpty() ? new String[0] : all.split("\n");
            StringBuilder out = new StringBuilder();
            for (int i = Math.max(0, lines.length - (KEEP - 1)); i < lines.length; i++) {
                out.append(lines[i]).append('\n');
            }
            out.append(line);
            p.edit().putString("log", out.toString()).apply();
        } catch (RuntimeException ignored) {
        }
    }

    static String report(Context context) {
        StringBuilder sb = new StringBuilder();
        sb.append("Android ").append(Build.VERSION.RELEASE).append(" (API ").append(Build.VERSION.SDK_INT).append(")\n");
        sb.append(Build.MANUFACTURER).append(' ').append(Build.MODEL).append('\n');
        sb.append("overlay: ").append(Build.VERSION.SDK_INT < 23 || Settings.canDrawOverlays(context)).append('\n');
        sb.append("accessibility: ").append(AutoStartAccessibility.isEnabled(context)).append('\n');
        sb.append("battery exempt: ").append(SystemLinks.batteryExempt(context)).append('\n');
        sb.append("autostart: ").append(MainActivity.autostartEnabled(context)).append("\n\n");
        String log = "";
        try {
            log = prefs(context).getString("log", "");
        } catch (RuntimeException ignored) {
        }
        sb.append(log.isEmpty() ? "—" : log);
        return sb.toString();
    }
}
