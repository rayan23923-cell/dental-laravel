package com.dentalclinic.tv;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/**
 * Opens the waiting screen when the TV is switched on (and after the app
 * is updated). Android 10+ allows this only once "display over other apps"
 * is granted, which the app's menu asks for.
 */
public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        Intent launch = new Intent(context, MainActivity.class);
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT);
        try {
            context.startActivity(launch);
        } catch (RuntimeException ignored) {
            // Not allowed yet (permission missing): the user opens it once.
        }
    }
}
