package com.dentalclinic.tv;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/**
 * Opens the waiting screen when the TV boots (and after the app is
 * updated) and starts {@link AutoStartService}, which also reopens it every
 * time the TV wakes from standby. Android 10+ allows opening it only once
 * "display over other apps" is granted, which the app asks for.
 */
public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (!MainActivity.autostartEnabled(context)) return;
        AutoStartService.start(context);
        AutoStartService.openScreen(context);
    }
}
