package com.dentalclinic.tv;

import android.app.Activity;
import android.app.admin.DeviceAdminReceiver;
import android.app.admin.DevicePolicyManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;

/**
 * Device admin with only the "lock screen" policy, copied from the adhan
 * app (rayan23923-cell/azan_tv AdminReceiver, 2026-11-03, by request). The
 * adhan app has it and opens itself after power-on on the clinic's TV;
 * TV memory cleaners leave device-admin apps alone, so the app is not left
 * force-stopped (a force-stopped app gets no boot broadcast). Nothing here
 * locks or wipes anything.
 */
public class AdminReceiver extends DeviceAdminReceiver {
    static ComponentName name(Context c) {
        return new ComponentName(c, AdminReceiver.class);
    }

    static boolean active(Context c) {
        try {
            DevicePolicyManager dpm = (DevicePolicyManager) c.getSystemService(Context.DEVICE_POLICY_SERVICE);
            return dpm != null && dpm.isAdminActive(name(c));
        } catch (RuntimeException e) {
            return false;
        }
    }

    static void request(Activity a) {
        Intent i = new Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
                .putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, name(a))
                .putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, a.getString(R.string.admin_explain));
        SystemLinks.openFirst(a, i, SystemLinks.appDetails(a));
    }
}
