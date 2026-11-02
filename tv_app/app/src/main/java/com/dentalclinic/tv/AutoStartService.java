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

    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Runnable open = () -> openScreen(this);
    private BroadcastReceiver wakeReceiver;

    /** Starts the service if auto-start is on; safe to call any time. */
    public static void start(Context context) {
        if (!MainActivity.autostartEnabled(context)) return;
        Intent intent = new Intent(context, AutoStartService.class);
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

    /** Brings the waiting screen to the front (no-op if it already is). */
    public static void openScreen(Context context) {
        Intent launch = new Intent(context, MainActivity.class);
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT);
        try {
            context.startActivity(launch);
        } catch (RuntimeException ignored) {
            // Blocked; the full-screen notification below still tries.
        }
        if (!MainActivity.canOpenFromBackground(context)) {
            openByNotification(context, launch);
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
                // Give the TV a moment to finish waking (and its own home
                // screen to appear) before coming to the front.
                handler.removeCallbacks(open);
                handler.postDelayed(open, 2500);
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
        if (!MainActivity.autostartEnabled(this)) {
            stopSelf();
            return START_NOT_STICKY;
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
