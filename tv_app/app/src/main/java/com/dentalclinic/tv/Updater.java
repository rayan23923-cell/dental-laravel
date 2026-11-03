package com.dentalclinic.tv;

import android.app.Activity;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageInstaller;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import android.widget.Toast;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
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
                    // The clinic TV never shows "allow installing updates"
                    // for this app (2026-11-03). Automatic checks only say an
                    // update exists; a check from settings downloads it to
                    // the Download folder and opens the file manager, which
                    // can install it.
                    if (!manual) {
                        activity.runOnUiThread(() -> {
                            ui.status(activity.getString(R.string.update_available, release[0]));
                            // A note, not a banner over the waiting screen.
                            new android.os.Handler(android.os.Looper.getMainLooper())
                                    .postDelayed(() -> ui.status(null), 30_000);
                        });
                        return;
                    }
                    activity.runOnUiThread(() -> ui.status(activity.getString(R.string.update_downloading, release[0])));
                    File saved = downloadToFolder(activity, release);
                    activity.runOnUiThread(() -> {
                        ui.status(null);
                        showSaved(activity, saved);
                    });
                    return;
                }
                activity.runOnUiThread(() -> ui.status(activity.getString(R.string.update_downloading, release[0])));
                File dir = new File(activity.getCacheDir(), "updates");
                //noinspection ResultOfMethodCallIgnored
                dir.mkdirs();
                File apk = new File(dir, "update.apk");
                download(release[1], apk);
                PackageInfo info = activity.getPackageManager().getPackageArchiveInfo(apk.getPath(), 0);
                if (info == null || !activity.getPackageName().equals(info.packageName)) {
                    throw new IllegalStateException("bad apk");
                }
                activity.runOnUiThread(() -> ui.status(null));
                install(activity, apk);
            } catch (Exception e) {
                activity.runOnUiThread(() -> ui.status(null));
                if (manual) toast(activity, activity.getString(R.string.update_failed));
            }
        }).start();
    }

    /**
     * Hands the APK to Android's package installer, which shows its install
     * screen: the adhan app's way (azan_tv Updater.install, 2026-11-03).
     */
    static void install(Context c, File apk) throws Exception {
        PackageInstaller pi = c.getPackageManager().getPackageInstaller();
        PackageInstaller.SessionParams p = new PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL);
        p.setAppPackageName(c.getPackageName());
        int id = pi.createSession(p);
        try (PackageInstaller.Session s = pi.openSession(id)) {
            try (OutputStream out = s.openWrite("app.apk", 0, apk.length());
                 InputStream in = new FileInputStream(apk)) {
                byte[] buf = new byte[16384];
                int n;
                while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
                s.fsync(out);
            }
            Intent done = new Intent(c, Result.class);
            int flags = PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 31 ? PendingIntent.FLAG_MUTABLE : 0);
            s.commit(PendingIntent.getBroadcast(c, 7, done, flags).getIntentSender());
        }
    }

    /** Android asks the person to confirm: open that screen. */
    public static final class Result extends BroadcastReceiver {
        @Override
        public void onReceive(Context c, Intent i) {
            if (i.getIntExtra(PackageInstaller.EXTRA_STATUS, 0) != PackageInstaller.STATUS_PENDING_USER_ACTION) return;
            Intent confirm = i.getParcelableExtra(Intent.EXTRA_INTENT);
            if (confirm == null) return;
            confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            try { c.startActivity(confirm); } catch (RuntimeException ignored) { }
        }
    }

    /**
     * Saves the update as Download/DentalClinicTV-<version>.apk (shared
     * storage, where any file manager looks); falls back to the app's own
     * external folder when writing there is not allowed.
     */
    private static File downloadToFolder(Activity activity, String[] release) throws Exception {
        String name = "DentalClinicTV-" + release[0] + ".apk";
        File dir = android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_DOWNLOADS);
        boolean canWrite = Build.VERSION.SDK_INT < 23 || activity.checkSelfPermission(
                android.Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED;
        if (!canWrite || !(dir.isDirectory() || dir.mkdirs())) {
            dir = activity.getExternalFilesDir(android.os.Environment.DIRECTORY_DOWNLOADS);
        }
        if (dir == null) throw new IllegalStateException("no storage");
        // Remove older copies so the folder holds only the newest update.
        File[] old = dir.listFiles((d, n) -> n.startsWith("DentalClinicTV-") && n.endsWith(".apk"));
        if (old != null) for (File f : old) //noinspection ResultOfMethodCallIgnored
            f.delete();
        File apk = new File(dir, name);
        download(release[1], apk);
        PackageInfo info = activity.getPackageManager().getPackageArchiveInfo(apk.getPath(), 0);
        if (info == null || !activity.getPackageName().equals(info.packageName)) {
            //noinspection ResultOfMethodCallIgnored
            apk.delete();
            throw new IllegalStateException("bad apk");
        }
        Diag.log(activity, "update saved " + apk.getPath());
        return apk;
    }

    /** Tells where the file is, then opens a file manager on the Download folder. */
    private static void showSaved(Activity activity, File apk) {
        new android.app.AlertDialog.Builder(activity)
                .setTitle(R.string.update_saved_title)
                .setMessage(activity.getString(R.string.update_saved_message, apk.getParent(), apk.getName()))
                .setPositiveButton(R.string.update_open_files, (d, w) -> {
                    if (!openFileManager(activity)) {
                        Toast.makeText(activity, R.string.update_no_file_manager, Toast.LENGTH_LONG).show();
                    }
                })
                .setNegativeButton(R.string.update_later, null)
                .show();
    }

    /** The first file manager that opens: the Download folder, the downloads list, then any app that looks like one. */
    static boolean openFileManager(Activity activity) {
        java.util.List<Intent> tries = new java.util.ArrayList<>();
        Uri downloads = Uri.parse("content://com.android.externalstorage.documents/document/primary%3ADownload");
        tries.add(new Intent(Intent.ACTION_VIEW).setDataAndType(downloads, "vnd.android.document/directory"));
        tries.add(new Intent(android.app.DownloadManager.ACTION_VIEW_DOWNLOADS));
        if (Build.VERSION.SDK_INT >= 29) {
            tries.add(Intent.makeMainSelectorActivity(Intent.ACTION_MAIN, Intent.CATEGORY_APP_FILES));
        }
        PackageManager pm = activity.getPackageManager();
        String[] words = {"file", "explorer", "manager", "media", "ملفات", "文件"};
        for (android.content.pm.ApplicationInfo app : pm.getInstalledApplications(0)) {
            String pkg = app.packageName.toLowerCase(java.util.Locale.ROOT);
            String label = String.valueOf(pm.getApplicationLabel(app)).toLowerCase(java.util.Locale.ROOT);
            if (pkg.equals(activity.getPackageName())) continue;
            boolean looks = false;
            for (String w : words) if (pkg.contains(w) || label.contains(w)) { looks = true; break; }
            if (!looks) continue;
            Intent launch = pm.getLeanbackLaunchIntentForPackage(app.packageName);
            if (launch == null) launch = pm.getLaunchIntentForPackage(app.packageName);
            if (launch != null) tries.add(launch);
        }
        for (Intent i : tries) {
            try {
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                activity.startActivity(i);
                Diag.log(activity, "file manager " + (i.getComponent() != null ? i.getComponent().getPackageName() : i.getAction()));
                return true;
            } catch (RuntimeException ignored) {
                // Not on this TV; try the next.
            }
        }
        return false;
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
