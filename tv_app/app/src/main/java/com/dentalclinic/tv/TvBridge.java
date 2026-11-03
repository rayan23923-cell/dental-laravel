package com.dentalclinic.tv;

import android.os.Build;
import android.webkit.JavascriptInterface;

import org.json.JSONObject;

/**
 * Remote control from the server (2026-11-03, by request): the waiting
 * screen page reads {@link #info()} and reports it to the server, and passes
 * on commands staff send from the settings page (web or app) once the TV is
 * paired: check for update, open on power-on / standby wake, and how soon the
 * app returns after someone leaves it. ("reload" is done by the page.)
 */
final class TvBridge {
    private final MainActivity activity;

    TvBridge(MainActivity activity) {
        this.activity = activity;
    }

    @JavascriptInterface
    public String info() {
        try {
            JSONObject o = new JSONObject();
            o.put("app", "tv");
            o.put("version", activity.getPackageManager().getPackageInfo(activity.getPackageName(), 0).versionName);
            o.put("open_on_boot", MainActivity.autostartEnabled(activity));
            o.put("open_on_wake", MainActivity.wakeEnabled(activity));
            o.put("return_minutes", AutoStartService.RETURN_MINUTES[AutoStartService.returnChoice(activity)]);
            o.put("overlay", MainActivity.canOpenFromBackground(activity));
            o.put("model", Build.MANUFACTURER + " " + Build.MODEL);
            o.put("android", Build.VERSION.RELEASE);
            return o.toString();
        } catch (Exception e) {
            return "{\"app\":\"tv\"}";
        }
    }

    @JavascriptInterface
    public void command(String json) {
        try {
            JSONObject cmd = new JSONObject(json);
            String type = cmd.optString("type");
            Diag.log(activity, "remote " + type);
            switch (type) {
                case "check_update":
                    activity.runOnUiThread(activity::checkForUpdateFromServer);
                    break;
                case "open_on_boot":
                    MainActivity.setAutostartEnabled(activity, cmd.optBoolean("value", true));
                    syncService();
                    break;
                case "open_on_wake":
                    MainActivity.setWakeEnabled(activity, cmd.optBoolean("value", true));
                    syncService();
                    break;
                case "return_minutes":
                    int minutes = cmd.optInt("value", 5);
                    for (int i = 0; i < AutoStartService.RETURN_MINUTES.length; i++) {
                        if (AutoStartService.RETURN_MINUTES[i] == minutes) AutoStartService.setReturnChoice(activity, i);
                    }
                    break;
                default:
                    break;
            }
        } catch (Exception e) {
            Diag.log(activity, "remote failed: " + e.getClass().getSimpleName());
        }
    }

    private void syncService() {
        if (MainActivity.anyAutoOpen(activity)) AutoStartService.start(activity);
        else AutoStartService.stop(activity);
    }
}
