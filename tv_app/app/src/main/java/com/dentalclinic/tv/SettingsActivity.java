package com.dentalclinic.tv;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.graphics.Color;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.LayerDrawable;
import android.graphics.drawable.StateListDrawable;
import android.net.ConnectivityManager;
import android.net.LinkAddress;
import android.net.LinkProperties;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.wifi.WifiInfo;
import android.net.wifi.WifiManager;
import android.os.Bundle;
import android.provider.Settings;
import android.text.format.DateFormat;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.net.Inet4Address;
import java.util.Date;

/**
 * The TV app's settings page (2026-11-03, by request), laid out like the
 * user's adhan app settings: glass rows that light up under the remote's
 * focus, grouped into sections (the screen, auto-start, network, TV
 * settings). Actions that need the waiting screen itself (reload, change
 * server, update, exit) are handed back to MainActivity.
 */
public class SettingsActivity extends Activity {
    static final String EXTRA_ACTION = "action";
    static final String ACTION_RELOAD = "reload";
    static final String ACTION_SERVER = "server";
    static final String ACTION_UPDATE = "update";
    static final String ACTION_EXIT = "exit";
    static final String EXTRA_SERVER = "server";

    private static final int TEAL = 0xFF13A3A8;
    private static final int TEAL_LIGHT = 0xFF7FE0DC;

    /** Choices for how long after power-on the app keeps coming back to the front; 0 = by the TV's memory. */
    static final int[] SETTLE_SECONDS = {0, 5, 10, 20, 45, 90};

    private float u;
    private LinearLayout list;
    private View focusAfterBuild;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        u = Math.max(0.6f, getResources().getDisplayMetrics().widthPixels / 1366f);
        ScrollView sv = new ScrollView(this);
        sv.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        sv.setBackground(new GradientDrawable(GradientDrawable.Orientation.TL_BR,
                new int[]{0xFF0B3D47, 0xFF072A31, 0xFF041A1F}));
        sv.setFillViewport(true);
        list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        list.setPadding((int) (170 * u), (int) (30 * u), (int) (170 * u), (int) (40 * u));
        sv.addView(list);
        setContentView(sv);
    }

    @Override
    protected void onResume() {
        super.onResume();
        build();
    }

    private void build() {
        View focused = getCurrentFocus();
        Object focusTag = focused != null ? focused.getTag() : null;
        list.removeAllViews();
        focusAfterBuild = null;

        header();

        section(getString(R.string.set_section_screen));
        String server = getIntent().getStringExtra(EXTRA_SERVER);
        row("server", getString(R.string.set_server, server == null || server.isEmpty() ? "—" : server),
                () -> finishWith(ACTION_SERVER));
        row("reload", getString(R.string.menu_reload), () -> finishWith(ACTION_RELOAD));
        row("update", getString(R.string.set_update, version()), () -> finishWith(ACTION_UPDATE));

        section(getString(R.string.set_section_autostart));
        row("boot", check(MainActivity.autostartEnabled(this)) + getString(R.string.set_open_on_boot), () -> {
            boolean on = !MainActivity.autostartEnabled(this);
            MainActivity.setAutostartEnabled(this, on);
            syncService();
            build();
        });
        row("wake", check(MainActivity.wakeEnabled(this)) + getString(R.string.set_open_on_wake), () -> {
            MainActivity.setWakeEnabled(this, !MainActivity.wakeEnabled(this));
            syncService();
            build();
        });
        row("settle", getString(R.string.set_settle, settleName(AutoStartService.settleChoice(this))), this::chooseSettle);
        row("overlay", check(MainActivity.canOpenFromBackground(this)) + getString(R.string.set_overlay), () -> {
            android.widget.Toast.makeText(this, R.string.overlay_steps, android.widget.Toast.LENGTH_LONG).show();
            SystemLinks.openFirst(this,
                    new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, android.net.Uri.parse("package:" + getPackageName())),
                    new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION),
                    SystemLinks.appDetails(this));
        });
        row("battery", check(SystemLinks.batteryExempt(this)) + getString(R.string.set_battery),
                () -> SystemLinks.requestBatteryExempt(this));
        row("admin", check(AdminReceiver.active(this)) + getString(R.string.set_admin), () -> AdminReceiver.request(this));
        row("autostart", getString(R.string.set_autostart_manager), () -> SystemLinks.openAutostart(this));
        row("home", check(SystemLinks.homeEnabled(this)) + getString(R.string.set_home), () -> {
            boolean on = !SystemLinks.homeEnabled(this);
            SystemLinks.setHomeEnabled(this, on);
            if (on) {
                android.widget.Toast.makeText(this, R.string.home_pick, android.widget.Toast.LENGTH_LONG).show();
                SystemLinks.openFirst(this, new Intent(Settings.ACTION_HOME_SETTINGS),
                        new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME));
            }
            build();
        });
        row("homepick", getString(R.string.set_home_pick), () -> SystemLinks.openFirst(this,
                new Intent(Settings.ACTION_HOME_SETTINGS), new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)));
        row("appinfo", getString(R.string.set_app_info), () -> SystemLinks.openFirst(this, SystemLinks.appDetails(this)));
        note(lastAutoOpen());
        row("diag", getString(R.string.menu_diag), () -> new AlertDialog.Builder(this, android.R.style.Theme_Material_Dialog_Alert)
                .setTitle(R.string.menu_diag)
                .setMessage(Diag.report(this))
                .setPositiveButton(android.R.string.ok, null)
                .show());

        section(getString(R.string.set_section_network));
        note(networkStatus());
        sys("wifi", getString(R.string.set_wifi), Settings.ACTION_WIFI_SETTINGS);
        sys("network", getString(R.string.set_network), Settings.ACTION_WIRELESS_SETTINGS);

        section(getString(R.string.set_section_tv));
        sys("tvsettings", getString(R.string.set_tv_settings), Settings.ACTION_SETTINGS);
        sys("date", getString(R.string.set_date), Settings.ACTION_DATE_SETTINGS);
        sys("sound", getString(R.string.set_sound), Settings.ACTION_SOUND_SETTINGS);
        sys("display", getString(R.string.set_display), Settings.ACTION_DISPLAY_SETTINGS);
        sys("apps", getString(R.string.set_apps), Settings.ACTION_MANAGE_APPLICATIONS_SETTINGS);
        sys("storage", getString(R.string.set_storage), Settings.ACTION_INTERNAL_STORAGE_SETTINGS);
        sys("lang", getString(R.string.set_language), Settings.ACTION_LOCALE_SETTINGS);
        sys("about", getString(R.string.set_about), Settings.ACTION_DEVICE_INFO_SETTINGS);
        sys("dev", getString(R.string.set_developer), Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS);

        section("");
        row("back", getString(R.string.set_back), this::finish);
        row("exit", getString(SystemLinks.homeEnabled(this) ? R.string.menu_tv_home : R.string.menu_exit),
                () -> finishWith(ACTION_EXIT));

        if (focusTag != null) {
            View again = list.findViewWithTag(focusTag);
            if (again != null) focusAfterBuild = again;
        }
        if (focusAfterBuild != null) focusAfterBuild.requestFocus();
    }

    private void syncService() {
        if (MainActivity.anyAutoOpen(this)) AutoStartService.start(this); else AutoStartService.stop(this);
    }

    private void finishWith(String action) {
        setResult(RESULT_OK, new Intent().putExtra(EXTRA_ACTION, action));
        finish();
    }

    // ---- pieces --------------------------------------------------------

    private void header() {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setGravity(Gravity.CENTER);
        box.setPadding(0, 0, 0, (int) (14 * u));
        TextView title = new TextView(this);
        title.setText(R.string.set_title);
        title.setTextColor(Color.WHITE);
        title.setTextSize(TypedValue.COMPLEX_UNIT_PX, 46 * u);
        title.setGravity(Gravity.CENTER);
        box.addView(title);
        TextView sub = new TextView(this);
        sub.setText(getString(R.string.app_name) + "  •  " + version());
        sub.setTextColor(TEAL_LIGHT);
        sub.setTextSize(TypedValue.COMPLEX_UNIT_PX, 24 * u);
        sub.setGravity(Gravity.CENTER);
        box.addView(sub);
        list.addView(box);
    }

    private void section(String label) {
        TextView t = new TextView(this);
        t.setText(label);
        t.setTextColor(TEAL_LIGHT);
        t.setTextSize(TypedValue.COMPLEX_UNIT_PX, 30 * u);
        t.setPadding((int) (8 * u), (int) (24 * u), (int) (8 * u), (int) (6 * u));
        list.addView(t);
    }

    private void note(String text) {
        TextView t = new TextView(this);
        t.setText(text);
        t.setTextColor(0xB3FFFFFF);
        t.setTextSize(TypedValue.COMPLEX_UNIT_PX, 22 * u);
        t.setPadding((int) (12 * u), (int) (4 * u), (int) (12 * u), (int) (6 * u));
        list.addView(t);
    }

    private void sys(String tag, String label, String action) {
        row(tag, label, () -> SystemLinks.openFirst(this, new Intent(action)));
    }

    private Button row(String tag, String label, Runnable action) {
        Button btn = new Button(this);
        btn.setTag(tag);
        btn.setText(label);
        btn.setAllCaps(false);
        btn.setTextColor(Color.WHITE);
        btn.setTextSize(TypedValue.COMPLEX_UNIT_PX, 27 * u);
        btn.setGravity(Gravity.CENTER_VERTICAL | Gravity.START);
        btn.setPadding((int) (26 * u), (int) (14 * u), (int) (26 * u), (int) (14 * u));
        StateListDrawable sl = new StateListDrawable();
        sl.addState(new int[]{android.R.attr.state_focused}, panel(true));
        sl.addState(new int[]{android.R.attr.state_pressed}, panel(true));
        sl.addState(new int[]{}, panel(false));
        btn.setBackground(sl);
        btn.setStateListAnimator(null);
        btn.setOnFocusChangeListener((v, has) -> v.animate().scaleX(has ? 1.02f : 1f).scaleY(has ? 1.04f : 1f)
                .setDuration(120).start());
        btn.setOnClickListener(v -> action.run());
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(0, (int) (5 * u), 0, (int) (5 * u));
        list.addView(btn, lp);
        if (focusAfterBuild == null) focusAfterBuild = btn;
        return btn;
    }

    /** Frosted glass panel; the focused row glows in the clinic's teal. */
    private Drawable panel(boolean focused) {
        float r = 18 * u;
        GradientDrawable base = focused
                ? new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, new int[]{0xFF19B5B3, 0xFF0E8A8F, 0xFF0A6C72})
                : new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, new int[]{0x33FFFFFF, 0x1AFFFFFF, 0x22FFFFFF});
        base.setCornerRadius(r);
        GradientDrawable sheen = new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,
                new int[]{focused ? 0x55FFFFFF : 0x22FFFFFF, 0x08FFFFFF, 0x00FFFFFF, 0x00FFFFFF});
        sheen.setCornerRadius(r);
        GradientDrawable rim = new GradientDrawable();
        rim.setCornerRadius(r);
        rim.setColor(0);
        rim.setStroke(Math.max(1, (int) ((focused ? 2.5f : 1.5f) * u)), focused ? 0xCCB8FFF9 : 0x40FFFFFF);
        return new LayerDrawable(new Drawable[]{base, sheen, rim});
    }

    private static String check(boolean ok) {
        return ok ? "✓  " : "✗  ";
    }

    // ---- values --------------------------------------------------------

    private String version() {
        try {
            PackageInfo info = getPackageManager().getPackageInfo(getPackageName(), 0);
            return info.versionName;
        } catch (Exception e) {
            return "";
        }
    }

    private String settleName(int choice) {
        int s = SETTLE_SECONDS[choice];
        return s == 0 ? getString(R.string.set_settle_auto) : getString(R.string.set_seconds, s);
    }

    private void chooseSettle() {
        String[] names = new String[SETTLE_SECONDS.length];
        for (int i = 0; i < names.length; i++) names[i] = settleName(i);
        new AlertDialog.Builder(this, android.R.style.Theme_Material_Dialog_Alert)
                .setTitle(R.string.set_settle_title)
                .setSingleChoiceItems(names, AutoStartService.settleChoice(this), (d, which) -> {
                    AutoStartService.setSettleChoice(this, which);
                    d.dismiss();
                    build();
                })
                .show();
    }

    private String lastAutoOpen() {
        long at = AutoStartService.lastAutoOpenAt(this);
        if (at <= 0) return getString(R.string.set_last_open_none);
        String when = DateFormat.format("d/M  hh:mm a", new Date(at)).toString();
        long after = AutoStartService.lastAutoOpenSeconds(this);
        return after > 0 ? getString(R.string.set_last_open_after, when, after) : getString(R.string.set_last_open, when);
    }

    private String networkStatus() {
        try {
            ConnectivityManager cm = (ConnectivityManager) getSystemService(Context.CONNECTIVITY_SERVICE);
            Network n = cm.getActiveNetwork();
            NetworkCapabilities caps = n == null ? null : cm.getNetworkCapabilities(n);
            if (caps == null) return getString(R.string.set_net_none);
            String ip = "";
            LinkProperties lp = cm.getLinkProperties(n);
            if (lp != null) {
                for (LinkAddress a : lp.getLinkAddresses()) {
                    if (a.getAddress() instanceof Inet4Address) ip = a.getAddress().getHostAddress();
                }
            }
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) {
                return getString(R.string.set_net_ethernet, ip);
            }
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                String ssid = "";
                try {
                    WifiInfo wi = ((WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE)).getConnectionInfo();
                    if (wi != null && wi.getSSID() != null && !wi.getSSID().contains("unknown")) {
                        ssid = wi.getSSID().replace("\"", "");
                    }
                } catch (RuntimeException ignored) {
                }
                return getString(R.string.set_net_wifi, ssid.isEmpty() ? "Wi-Fi" : ssid, ip);
            }
            return getString(R.string.set_net_other, ip);
        } catch (RuntimeException e) {
            return getString(R.string.set_net_none);
        }
    }
}
