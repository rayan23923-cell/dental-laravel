package com.dentalclinic.tv;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;

/**
 * Starts the waiting screen whenever the TV is switched on, the way prayer
 * (adhan) TV apps do (2026-11-02, by request). Most TVs do not reboot when
 * switched on with the remote, they only wake from standby, so the boot
 * broadcast alone never comes. This small foreground service stays running
 * and opens the screen on every wake (screen on, unlock, screensaver end).
 * It is started at boot, after an app update and whenever the app opens.
 * Opening an activity from the background needs "display over other apps"
 * on Android 10+, which the app asks for on first start.
 */
public class AutoStartService extends Service {
    private static final String CHANNEL = "autostart";
    private static final String CHANNEL_OPEN = "open_screen";
    private static final int NOTIFICATION_ID = 7;
    static final int OPEN_NOTIFICATION_ID = 8;

    static final String EXTRA_BOOT = "boot";

    private final Handler handler = new Handler(Looper.getMainLooper());
    private BroadcastReceiver wakeReceiver;
    private long watchUntil;
    private long watchSettleAt;
    private boolean notified;
    private int attempts;

    /**
     * The adhan TV app's way (2026-11-02, by request): the TV's own home
     * screen comes up late in boot (and after a wake) and covers an app that
     * opened once, so for a while keep bringing the waiting screen back
     * every second until it holds the screen; stop early once it has held
     * it past the settle time, so someone opening another app is left alone.
     */
    private final Runnable watcher = new Runnable() {
        @Override
        public void run() {
            long now = System.currentTimeMillis();
            if (now > watchUntil) return;
            if (MainActivity.visible) {
                if (now >= watchSettleAt) return;
            } else {
                if (++attempts <= 3 || attempts % 10 == 0) {
                    Diag.log(AutoStartService.this, "bring to front #" + attempts);
                }
                bringToFront(AutoStartService.this);
                if (!notified && !MainActivity.canOpenFromBackground(AutoStartService.this)) {
                    notified = true;
                    openByNotification(AutoStartService.this, launchIntent(AutoStartService.this));
                }
            }
            handler.postDelayed(this, 1000);
        }
    };

    private void watch(long duration, long settle) {
        long now = System.currentTimeMillis();
        watchUntil = Math.max(watchUntil, now + duration);
        watchSettleAt = now + settle;
        notified = false;
        attempts = 0;
        handler.removeCallbacks(watcher);
        handler.postDelayed(watcher, 300);
    }

    /** How long the TV's own home screen keeps coming up after power-on: slower TVs take longer. */
    static long settleMs(Context context) {
        try {
            android.app.ActivityManager.MemoryInfo mi = new android.app.ActivityManager.MemoryInfo();
            ((android.app.ActivityManager) context.getSystemService(ACTIVITY_SERVICE)).getMemoryInfo(mi);
            long mb = mi.totalMem / (1024 * 1024);
            int cores = Runtime.getRuntime().availableProcessors();
            if (mb > 2600 && cores >= 4) return 10_000;
            if (mb > 1600) return 20_000;
        } catch (RuntimeException ignored) {
        }
        return 45_000;
    }

    /** Starts the service if auto-start is on; safe to call any time. */
    public static void start(Context context) {
        start(context, new Intent(context, AutoStartService.class));
    }

    /** After boot: the service keeps bringing the screen back while the TV finishes starting. */
    public static void startAfterBoot(Context context) {
        start(context, new Intent(context, AutoStartService.class).putExtra(EXTRA_BOOT, true));
    }

    private static void start(Context context, Intent intent) {
        if (!MainActivity.autostartEnabled(context)) return;
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent);
            } else {
                context.startService(intent);
            }
        } catch (RuntimeException ignored) {
            // Not allowed from here right now; the next start tries again.
        }
    }

    public static void stop(Context context) {
        context.stopService(new Intent(context, AutoStartService.class));
    }

    private static Intent launchIntent(Context context) {
        Intent launch = new Intent(context, MainActivity.class);
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT);
        return launch;
    }

    /** Brings the waiting screen to the front (no-op if it already is). */
    public static void bringToFront(Context context) {
        try {
            context.startActivity(launchIntent(context));
        } catch (RuntimeException e) {
            // Not allowed right now; the watch tries again in a second.
            Diag.log(context, "front failed: " + e.getClass().getSimpleName());
        }
    }

    /**
     * Android 10+ silently ignores the call above without "display over
     * other apps", which some TVs do not offer at all. A full-screen
     * notification (the way alarm and adhan apps wake the screen) opens it
     * instead; MainActivity removes it once it is showing.
     */
    private static void openByNotification(Context context, Intent launch) {
        try {
            NotificationManager nm = (NotificationManager) context.getSystemService(NOTIFICATION_SERVICE);
            int flags = PendingIntent.FLAG_UPDATE_CURRENT
                    | (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ? PendingIntent.FLAG_IMMUTABLE : 0);
            PendingIntent pending = PendingIntent.getActivity(context, 1, launch, flags);
            Notification.Builder builder;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                NotificationChannel channel = new NotificationChannel(
                        CHANNEL_OPEN, context.getString(R.string.autostart_open_channel), NotificationManager.IMPORTANCE_HIGH);
                channel.setSound(null, null);
                nm.createNotificationChannel(channel);
                builder = new Notification.Builder(context, CHANNEL_OPEN);
            } else {
                builder = new Notification.Builder(context).setPriority(Notification.PRIORITY_MAX);
            }
            Notification notification = builder
                    .setSmallIcon(R.drawable.ic_launcher)
                    .setContentTitle(context.getString(R.string.app_name))
                    .setContentText(context.getString(R.string.autostart_tap_to_open))
                    .setCategory(Notification.CATEGORY_ALARM)
                    .setContentIntent(pending)
                    .setFullScreenIntent(pending, true)
                    .setAutoCancel(true)
                    .build();
            nm.notify(OPEN_NOTIFICATION_ID, notification);
        } catch (RuntimeException ignored) {
            // Notifications blocked too: home screen mode is the way left.
        }
    }

    @Override
    public void onCreate() {
        super.onCreate();
        goForeground();
        wakeReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                Diag.log(context, "wake " + intent.getAction());
                // Woken from standby: the TV's home screen shows up for a
                // while; keep coming back for 20 s.
                if (MainActivity.autostartEnabled(context)) watch(20_000, 0);
            }
        };
        IntentFilter filter = new IntentFilter();
        filter.addAction(Intent.ACTION_SCREEN_ON);
        filter.addAction(Intent.ACTION_USER_PRESENT);
        filter.addAction(Intent.ACTION_DREAMING_STOPPED);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(wakeReceiver, filter, Context.RECEIVER_EXPORTED);
        } else {
            registerReceiver(wakeReceiver, filter);
        }
    }

    private void goForeground() {
        NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        Notification.Builder builder;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(new NotificationChannel(
                    CHANNEL, getString(R.string.autostart_channel), NotificationManager.IMPORTANCE_MIN));
            builder = new Notification.Builder(this, CHANNEL);
        } else {
            builder = new Notification.Builder(this);
        }
        Notification notification = builder
                .setSmallIcon(R.drawable.ic_launcher)
                .setContentTitle(getString(R.string.app_name))
                .setContentText(getString(R.string.autostart_running))
                .setOngoing(true)
                .build();
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
        } else {
            startForeground(NOTIFICATION_ID, notification);
        }
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Diag.log(this, "service start" + (intent != null && intent.getBooleanExtra(EXTRA_BOOT, false) ? " (boot)" : ""));
        if (!MainActivity.autostartEnabled(this)) {
            stopSelf();
            return START_NOT_STICKY;
        }
        if (intent != null && intent.getBooleanExtra(EXTRA_BOOT, false)) {
            long settle = settleMs(this);
            watch(Math.max(settle, 10_000) * 2, settle);
        }
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        handler.removeCallbacksAndMessages(null);
        if (wakeReceiver != null) {
            try { unregisterReceiver(wakeReceiver); } catch (RuntimeException ignored) { }
        }
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
