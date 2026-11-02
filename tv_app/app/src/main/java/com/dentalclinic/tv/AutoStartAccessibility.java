package com.dentalclinic.tv;

import android.accessibilityservice.AccessibilityService;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.text.TextUtils;
import android.view.accessibility.AccessibilityEvent;

/**
 * Auto-start for TVs that grey out "display over other apps" (2026-11-02,
 * by request). Android lets an app whose accessibility service is switched
 * on open its screen from the background, and the system starts this
 * service by itself after every boot, power cut included. So, once it is
 * switched on in the TV's accessibility settings, it opens the waiting
 * screen a few seconds after the TV starts and whenever the TV wakes.
 * It reads nothing on screen (no event types are requested).
 */
public class AutoStartAccessibility extends AccessibilityService {
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Runnable open = this::openScreen;
    private BroadcastReceiver wakeReceiver;

    /** True when this service is switched on in accessibility settings. */
    static boolean isEnabled(Context context) {
        String enabled = Settings.Secure.getString(context.getContentResolver(),
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
        if (TextUtils.isEmpty(enabled)) return false;
        ComponentName me = new ComponentName(context, AutoStartAccessibility.class);
        TextUtils.SimpleStringSplitter splitter = new TextUtils.SimpleStringSplitter(':');
        splitter.setString(enabled);
        while (splitter.hasNext()) {
            ComponentName c = ComponentName.unflattenFromString(splitter.next());
            if (me.equals(c)) return true;
        }
        return false;
    }

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        // Boot or power cut: give the TV time to show its home screen first.
        handler.postDelayed(open, 6000);
        wakeReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
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

    private void openScreen() {
        if (!MainActivity.autostartEnabled(this)) return;
        Intent launch = new Intent(this, MainActivity.class);
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT);
        try {
            startActivity(launch);
        } catch (RuntimeException ignored) {
            // Nothing else to try from here.
        }
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        // Not used: the service exists only so Android lets the app open itself.
    }

    @Override
    public void onInterrupt() {
    }

    @Override
    public void onDestroy() {
        handler.removeCallbacksAndMessages(null);
        if (wakeReceiver != null) {
            try { unregisterReceiver(wakeReceiver); } catch (RuntimeException ignored) { }
        }
        super.onDestroy();
    }
}
