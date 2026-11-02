package com.dentalclinic.tv;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

/**
 * Opens the waiting screen when the TV boots, the way the adhan TV app does
 * (2026-11-02, by request): it listens to the early LOCKED_BOOT_COMPLETED
 * too (before the TV's memory manager stops background apps), starts
 * {@link AutoStartService} with a boot watch that keeps bringing the screen
 * back while the TV's own home screen comes up, and sets two alarms that
 * try again at 10 s and 30 s in case the service was stopped.
 */
public class BootReceiver extends BroadcastReceiver {
    static final String ACTION_LAUNCH = "com.dentalclinic.tv.LAUNCH";

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        try {
            if (Intent.ACTION_LOCKED_BOOT_COMPLETED.equals(action)) {
                // Storage is still locked: touch no preferences here.
                AutoStartService.startAfterBoot(context);
                return;
            }
            if (!MainActivity.autostartEnabled(context)) return;
            if (ACTION_LAUNCH.equals(action)) {
                if (!MainActivity.visible) AutoStartService.bringToFront(context);
                return;
            }
            boolean boot = Intent.ACTION_BOOT_COMPLETED.equals(action)
                    || "android.intent.action.QUICKBOOT_POWERON".equals(action)
                    || "com.htc.intent.action.QUICKBOOT_POWERON".equals(action)
                    || "android.intent.action.REBOOT".equals(action);
            if (boot) {
                AutoStartService.startAfterBoot(context);
                AutoStartService.bringToFront(context);
                long settle = AutoStartService.settleMs(context);
                relaunchAt(context, Math.min(10_000, settle), 2);
                if (settle > 20_000) relaunchAt(context, Math.min(30_000, settle - 2_000), 3);
            } else {
                // App updated: just keep the service running.
                AutoStartService.start(context);
            }
        } catch (RuntimeException ignored) {
        }
    }

    private static void relaunchAt(Context context, long delay, int code) {
        Intent intent = new Intent(context, BootReceiver.class).setAction(ACTION_LAUNCH);
        int flags = PendingIntent.FLAG_UPDATE_CURRENT
                | (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ? PendingIntent.FLAG_IMMUTABLE : 0);
        PendingIntent pending = PendingIntent.getBroadcast(context, code, intent, flags);
        AlarmManager am = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        am.set(AlarmManager.RTC_WAKEUP, System.currentTimeMillis() + delay, pending);
    }
}
