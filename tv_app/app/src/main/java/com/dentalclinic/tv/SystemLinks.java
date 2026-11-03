package com.dentalclinic.tv;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.PowerManager;
import android.provider.Settings;
import android.widget.Toast;

/**
 * System screens that TV skins hide from their menus, as in the user's own
 * azan_tv app (2026-11-02, by request): that app opens by itself on the same
 * TV because it was allowed in the TV maker's "auto start" manager. Opens
 * the first such screen that exists on this TV, else the app's details.
 */
final class SystemLinks {
    private SystemLinks() {
    }

    /** Vendor "auto start" / "startup manager" screens; the first one that exists is used. */
    private static final String[][] AUTOSTART = {
        {"com.tcl.guard", "com.tcl.guard.activity.AutoStartActivity"},
        {"com.tcl.packageinstaller", "com.tcl.packageinstaller.autostart.AutoStartActivity"},
        {"com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"},
        {"com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"},
        {"com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity"},
        {"com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity"},
        {"com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity"},
        {"com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"},
        {"com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"},
        {"com.letv.android.letvsafe", "com.letv.android.letvsafe.AutobootManageActivity"},
        {"com.asus.mobilemanager", "com.asus.mobilemanager.autostart.AutoStartActivity"},
        {"com.samsung.android.lool", "com.samsung.android.sm.ui.battery.BatteryActivity"},
        {"com.android.settings", "com.android.settings.Settings$AppAndNotificationDashboardActivity"},
    };

    static boolean open(Activity a, Intent i) {
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            a.startActivity(i);
            return true;
        } catch (RuntimeException e) {
            return false;
        }
    }

    /** Opens the first screen that exists; false (with a message) when this TV has none of them. */
    static boolean openFirst(Activity a, Intent... intents) {
        for (Intent i : intents) if (i != null && open(a, i)) return true;
        Toast.makeText(a, R.string.screen_missing, Toast.LENGTH_LONG).show();
        return false;
    }

    static Intent appDetails(Context c) {
        return new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + c.getPackageName()));
    }

    /** The TV maker's auto-start manager, else this app's details page. */
    static void openAutostart(Activity a) {
        PackageManager pm = a.getPackageManager();
        for (String[] s : AUTOSTART) {
            Intent i = new Intent().setComponent(new ComponentName(s[0], s[1]));
            if (i.resolveActivity(pm) != null && open(a, i)) {
                Toast.makeText(a, R.string.autostart_manager_hint, Toast.LENGTH_LONG).show();
                return;
            }
        }
        openFirst(a, appDetails(a), new Intent(Settings.ACTION_SETTINGS));
    }

    static boolean batteryExempt(Context c) {
        if (Build.VERSION.SDK_INT < 23) return true;
        PowerManager pm = (PowerManager) c.getSystemService(Context.POWER_SERVICE);
        return pm != null && pm.isIgnoringBatteryOptimizations(c.getPackageName());
    }

    /** Asks to be left out of battery saving, so the TV does not stop the app in standby. */
    static boolean requestBatteryExempt(Activity a) {
        if (Build.VERSION.SDK_INT < 23) return true;
        if (open(a, new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:" + a.getPackageName())))
                || open(a, new Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))) return true;
        openFirst(a, appDetails(a));
        return false; // this TV has no battery-saving screen
    }

    // ---- "use as home screen": a HOME alias that is off unless turned on ----

    static ComponentName homeAlias(Context c) {
        return new ComponentName(c, c.getPackageName() + ".HomeAlias");
    }

    static boolean homeEnabled(Context c) {
        return c.getPackageManager().getComponentEnabledSetting(homeAlias(c))
                == PackageManager.COMPONENT_ENABLED_STATE_ENABLED;
    }

    static void setHomeEnabled(Context c, boolean on) {
        c.getPackageManager().setComponentEnabledSetting(homeAlias(c),
                on ? PackageManager.COMPONENT_ENABLED_STATE_ENABLED : PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP);
    }
}
