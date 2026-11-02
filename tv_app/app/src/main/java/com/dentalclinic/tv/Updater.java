package com.dentalclinic.tv;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import android.widget.Toast;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;

/**
 * Self-update (2026-11-02, by request). Asks the chosen server for the
 * newest TV build: the hosting's `/api/v1/app/version?platform=android_tv`,
 * else the offline server's `/apps/releases.json` (key `android_tv`). A
 * newer version is downloaded and handed to the system installer, which on
 * a TV shows one "Install" confirmation; the app then reopens by itself
 * (BootReceiver, MY_PACKAGE_REPLACED). Runs on start and every 6 hours.
 */
final class Updater {
    interface Ui {
        void status(String text);
    }

    private Updater() {
    }

    static void check(Activity activity, String server, boolean manual, Ui ui) {
        new Thread(() -> {
            try {
                String[] release = latest(server);
                String current = currentVersion(activity);
                if (release == null || !isNewer(release[0], current)) {
                    if (manual) toast(activity, activity.getString(R.string.update_latest, current));
                    return;
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                        && !activity.getPackageManager().canRequestPackageInstalls()) {
                    activity.runOnUiThread(() -> {
                        Toast.makeText(activity, R.string.update_allow, Toast.LENGTH_LONG).show();
                        try {
                            activity.startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:" + activity.getPackageName())));
                        } catch (RuntimeException ignored) {
                            // No such settings screen on this TV.
                        }
                    });
                    return;
                }
                activity.runOnUiThread(() -> ui.status(activity.getString(R.string.update_downloading, release[0])));
                File apk = ApkProvider.file(activity);
                download(release[1], apk);
                PackageInfo info = activity.getPackageManager().getPackageArchiveInfo(apk.getPath(), 0);
                if (info == null || !activity.getPackageName().equals(info.packageName)) {
                    throw new IllegalStateException("bad apk");
                }
                activity.runOnUiThread(() -> {
                    ui.status(null);
                    Intent install = new Intent(Intent.ACTION_VIEW);
                    install.setDataAndType(ApkProvider.URI, "application/vnd.android.package-archive");
                    install.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
                    try {
                        activity.startActivity(install);
                    } catch (RuntimeException e) {
                        Toast.makeText(activity, R.string.update_failed, Toast.LENGTH_LONG).show();
                    }
                });
            } catch (Exception e) {
                activity.runOnUiThread(() -> ui.status(null));
                if (manual) toast(activity, activity.getString(R.string.update_failed));
            }
        }).start();
    }

    /** {version, absolute apk url} or null. */
    private static String[] latest(String server) {
        String[] fromApi = fromJson(server, server + "/api/v1/app/version?platform=android_tv", false);
        if (fromApi != null) return fromApi;
        return fromJson(server, server + "/apps/releases.json", true);
    }

    private static String[] fromJson(String server, String url, boolean manifest) {
        try {
            JSONObject json = new JSONObject(get(url));
            if (manifest) json = json.optJSONObject("android_tv");
            if (json == null) return null;
            String version = json.optString("version", "");
            String apk = json.optString("url", "");
            if (version.isEmpty() || apk.isEmpty()) return null;
            // The offline manifest has paths like /apps/DentalClinicTV-1.1.9.apk.
            String absolute = new URL(new URL(server + "/"), apk).toString();
            return new String[]{version, absolute};
        } catch (Exception e) {
            return null;
        }
    }

    private static HttpURLConnection open(String url) throws Exception {
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        c.setConnectTimeout(15000);
        c.setReadTimeout(30000);
        c.setInstanceFollowRedirects(true);
        return c;
    }

    private static String get(String url) throws Exception {
        HttpURLConnection c = open(url);
        try {
            if (c.getResponseCode() != 200) throw new IllegalStateException("http " + c.getResponseCode());
            try (InputStream in = c.getInputStream(); ByteArrayOutputStream out = new ByteArrayOutputStream()) {
                byte[] buf = new byte[8192];
                int n;
                while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
                return out.toString("UTF-8");
            }
        } finally {
            c.disconnect();
        }
    }

    private static void download(String url, File target) throws Exception {
        HttpURLConnection c = open(url);
        c.setReadTimeout(60000);
        try {
            if (c.getResponseCode() != 200) throw new IllegalStateException("http " + c.getResponseCode());
            File part = new File(target.getPath() + ".part");
            try (InputStream in = c.getInputStream(); OutputStream out = new FileOutputStream(part)) {
                byte[] buf = new byte[65536];
                int n;
                while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
            }
            if (!part.renameTo(target)) throw new IllegalStateException("rename");
        } finally {
            c.disconnect();
        }
    }

    private static String currentVersion(Activity activity) throws PackageManager.NameNotFoundException {
        return activity.getPackageManager().getPackageInfo(activity.getPackageName(), 0).versionName;
    }

    /** "1.1.300" > "1.1.299", numerically part by part. */
    static boolean isNewer(String candidate, String current) {
        String[] a = candidate.split("\\.");
        String[] b = (current == null ? "0" : current).split("\\.");
        for (int i = 0; i < Math.max(a.length, b.length); i++) {
            int x = i < a.length ? parse(a[i]) : 0;
            int y = i < b.length ? parse(b[i]) : 0;
            if (x != y) return x > y;
        }
        return false;
    }

    private static int parse(String s) {
        try {
            return Integer.parseInt(s.replaceAll("[^0-9]", ""));
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    private static void toast(Activity activity, String text) {
        activity.runOnUiThread(() -> Toast.makeText(activity, text, Toast.LENGTH_LONG).show());
    }
}
