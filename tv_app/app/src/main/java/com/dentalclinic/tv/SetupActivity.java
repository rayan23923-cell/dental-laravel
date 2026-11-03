package com.dentalclinic.tv;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.StateListDrawable;
import android.net.Uri;
import android.os.Bundle;
import android.provider.Settings;
import android.text.InputType;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

/**
 * First-run setup wizard (2026-11-03, by request). Shown when the app is
 * opened for the first time; no step can be skipped until it is done:
 * choose the server, allow "display over other apps" (needed to open by
 * itself when the TV is switched on), battery-saving exemption and device
 * admin. A step whose settings screen does not exist on this TV counts as
 * done once the app has tried to open it. Everything can be changed later
 * from the settings page.
 */
public class SetupActivity extends Activity {
    private static final String KEY_DONE = "setup_done";
    private static final int STEPS = 5;

    private float u;
    private int step;
    /** Steps whose system screen is missing on this TV (cannot be done here). */
    private final boolean[] unavailable = new boolean[STEPS];

    private LinearLayout dots;
    private TextView counter;
    private TextView title;
    private TextView body;
    private TextView status;
    private LinearLayout actions;
    private Button next;
    private Button back;

    static boolean done(Context c) {
        return c.getSharedPreferences(MainActivity.PREFS, MODE_PRIVATE).getBoolean(KEY_DONE, false);
    }

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        u = Math.max(0.6f, getResources().getDisplayMetrics().widthPixels / 1366f);
        if (b != null) step = b.getInt("step", 0);

        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        page.setGravity(Gravity.CENTER_HORIZONTAL);
        page.setPadding((int) (220 * u), (int) (40 * u), (int) (220 * u), (int) (30 * u));
        page.setBackground(new GradientDrawable(GradientDrawable.Orientation.TL_BR,
                new int[]{0xFF0B3D47, 0xFF072A31, 0xFF041A1F}));

        TextView heading = text(getString(R.string.setup_heading), 40, Color.WHITE);
        heading.setGravity(Gravity.CENTER);
        page.addView(heading, wide());

        dots = new LinearLayout(this);
        dots.setGravity(Gravity.CENTER);
        dots.setPadding(0, (int) (14 * u), 0, (int) (4 * u));
        page.addView(dots, wide());
        counter = text("", 22, 0xFF7FE0DC);
        counter.setGravity(Gravity.CENTER);
        page.addView(counter, wide());

        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding((int) (36 * u), (int) (28 * u), (int) (36 * u), (int) (28 * u));
        card.setBackground(SettingsActivity.panel(u, false));
        LinearLayout.LayoutParams cardLp = new LinearLayout.LayoutParams(-1, 0, 1f);
        cardLp.setMargins(0, (int) (20 * u), 0, (int) (20 * u));
        page.addView(card, cardLp);

        title = text("", 34, Color.WHITE);
        card.addView(title, wide());
        body = text("", 24, 0xD9FFFFFF);
        body.setPadding(0, (int) (10 * u), 0, (int) (16 * u));
        body.setLineSpacing(0, 1.2f);
        card.addView(body, wide());
        actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.VERTICAL);
        card.addView(actions, wide());
        status = text("", 26, Color.WHITE);
        status.setPadding(0, (int) (16 * u), 0, 0);
        card.addView(status, wide());

        LinearLayout nav = new LinearLayout(this);
        nav.setGravity(Gravity.CENTER);
        back = button(getString(R.string.setup_back), v -> go(step - 1));
        next = button("", v -> onNext());
        LinearLayout.LayoutParams navLp = new LinearLayout.LayoutParams(0, -2, 1f);
        navLp.setMargins((int) (8 * u), 0, (int) (8 * u), 0);
        nav.addView(next, navLp);
        nav.addView(back, new LinearLayout.LayoutParams(navLp));
        page.addView(nav, wide());

        setContentView(page);
    }

    @Override
    protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        out.putInt("step", step);
    }

    @Override
    protected void onResume() {
        super.onResume();
        render(); // back from a system screen: show the new state
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            // The wizard cannot be left: BACK only goes to the previous step.
            if (step > 0) go(step - 1);
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    private void go(int to) {
        step = Math.max(0, Math.min(STEPS - 1, to));
        render();
    }

    private boolean stepDone(int s) {
        switch (s) {
            case 0: return !server().isEmpty();
            case 1: return MainActivity.canOpenFromBackground(this) || unavailable[1];
            case 2: return SystemLinks.batteryExempt(this) || unavailable[2];
            case 3: return AdminReceiver.active(this) || unavailable[3];
            default: return true;
        }
    }

    private void onNext() {
        if (!stepDone(step)) {
            Toast.makeText(this, R.string.setup_need_step, Toast.LENGTH_LONG).show();
            return;
        }
        if (step == STEPS - 1) {
            getSharedPreferences(MainActivity.PREFS, MODE_PRIVATE).edit().putBoolean(KEY_DONE, true).apply();
            AutoStartService.start(this);
            setResult(RESULT_OK);
            finish();
            return;
        }
        go(step + 1);
    }

    private void render() {
        dots.removeAllViews();
        for (int i = 0; i < STEPS; i++) {
            View d = new View(this);
            GradientDrawable g = new GradientDrawable();
            g.setCornerRadius(8 * u);
            g.setColor(i < step ? 0xFF13A3A8 : i == step ? Color.WHITE : 0x40FFFFFF);
            d.setBackground(g);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams((int) ((i == step ? 46 : 16) * u), (int) (16 * u));
            lp.setMargins((int) (6 * u), 0, (int) (6 * u), 0);
            dots.addView(d, lp);
        }
        counter.setText(getString(R.string.setup_counter, step + 1, STEPS));
        actions.removeAllViews();
        back.setVisibility(step == 0 ? View.INVISIBLE : View.VISIBLE);
        next.setText(step == STEPS - 1 ? R.string.setup_start : R.string.setup_next);

        switch (step) {
            case 0:
                title.setText(R.string.setup_server_title);
                body.setText(R.string.setup_server_body);
                String current = server();
                action((MainActivity.CLINIC_SERVER.equals(current) ? "✓  " : "") + getString(R.string.server_clinic),
                        () -> saveServer(MainActivity.CLINIC_SERVER));
                action((MainActivity.HOSTING_SERVER.equals(current) ? "✓  " : "") + getString(R.string.server_hosting),
                        () -> saveServer(MainActivity.HOSTING_SERVER));
                boolean custom = !current.isEmpty() && !MainActivity.CLINIC_SERVER.equals(current)
                        && !MainActivity.HOSTING_SERVER.equals(current);
                action((custom ? "✓  " : "") + getString(R.string.server_custom), this::askCustom);
                statusLine(current.isEmpty() ? getString(R.string.setup_server_none) : getString(R.string.set_server, current), !current.isEmpty());
                break;
            case 1:
                title.setText(R.string.setup_overlay_title);
                body.setText(R.string.setup_overlay_body);
                action(getString(R.string.setup_open_settings), () -> {
                    Toast.makeText(this, R.string.overlay_steps, Toast.LENGTH_LONG).show();
                    if (!SystemLinks.open(this, new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:" + getPackageName())))
                            && !SystemLinks.open(this, new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION))) {
                        SystemLinks.openFirst(this, SystemLinks.appDetails(this));
                        unavailable[1] = true;
                        render();
                    }
                });
                skipAction(1);
                statusFor(1);
                break;
            case 2:
                title.setText(R.string.setup_battery_title);
                body.setText(R.string.setup_battery_body);
                action(getString(R.string.setup_open_settings), () -> {
                    if (!SystemLinks.requestBatteryExempt(this)) {
                        unavailable[2] = true;
                        render();
                    }
                });
                skipAction(2);
                statusFor(2);
                break;
            case 3:
                title.setText(R.string.setup_admin_title);
                body.setText(R.string.setup_admin_body);
                action(getString(R.string.setup_open_settings), () -> {
                    if (!AdminReceiver.request(this)) {
                        unavailable[3] = true;
                        render();
                    }
                });
                skipAction(3);
                statusFor(3);
                break;
            default:
                title.setText(R.string.setup_done_title);
                body.setText(R.string.setup_done_body);
                statusLine(getString(R.string.set_server, server()), true);
                break;
        }
        next.setAlpha(stepDone(step) ? 1f : 0.45f);
        View first = actions.getChildCount() > 0 ? actions.getChildAt(0) : next;
        if (stepDone(step) && step != 0) first = next;
        first.requestFocus();
    }

    /**
     * Some TVs never show these system screens (2026-11-03, by request):
     * the permission steps can be skipped; the server step cannot.
     */
    private void skipAction(int s) {
        if (stepDone(s)) return;
        action(getString(R.string.setup_skip), () -> {
            unavailable[s] = true;
            go(s + 1);
        });
    }

    private void statusFor(int s) {
        boolean ok = stepDone(s);
        if (ok && unavailable[s]) statusLine(getString(R.string.setup_unavailable), true);
        else statusLine(getString(ok ? R.string.setup_step_ok : R.string.setup_step_missing), ok);
    }

    private void statusLine(String text, boolean ok) {
        status.setText((ok ? "✓  " : "✗  ") + text);
        status.setTextColor(ok ? 0xFF7FE0DC : 0xFFFFB4A8);
    }

    // ---- server ----------------------------------------------------------

    private String server() {
        return getSharedPreferences(MainActivity.PREFS, MODE_PRIVATE).getString(MainActivity.KEY_SERVER, "");
    }

    private void saveServer(String value) {
        String v = MainActivity.normalizeServer(value);
        if (v.isEmpty()) return;
        getSharedPreferences(MainActivity.PREFS, MODE_PRIVATE).edit().putString(MainActivity.KEY_SERVER, v).apply();
        render();
        next.requestFocus();
    }

    private void askCustom() {
        EditText input = new EditText(this);
        input.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI);
        input.setHint(R.string.custom_hint);
        input.setText(server());
        new AlertDialog.Builder(this, android.R.style.Theme_Material_Dialog_Alert)
                .setTitle(R.string.server_custom)
                .setView(input)
                .setPositiveButton(R.string.save, (d, w) -> saveServer(input.getText().toString()))
                .setNegativeButton(R.string.cancel, null)
                .show();
    }

    // ---- views -------------------------------------------------------------

    private void action(String label, Runnable run) {
        Button btn = button(label, v -> run.run());
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(0, (int) (6 * u), 0, (int) (6 * u));
        actions.addView(btn, lp);
    }

    private Button button(String label, View.OnClickListener click) {
        Button btn = new Button(this);
        btn.setText(label);
        btn.setAllCaps(false);
        btn.setTextColor(Color.WHITE);
        btn.setTextSize(TypedValue.COMPLEX_UNIT_PX, 27 * u);
        btn.setPadding((int) (26 * u), (int) (14 * u), (int) (26 * u), (int) (14 * u));
        StateListDrawable sl = new StateListDrawable();
        sl.addState(new int[]{android.R.attr.state_focused}, SettingsActivity.panel(u, true));
        sl.addState(new int[]{android.R.attr.state_pressed}, SettingsActivity.panel(u, true));
        sl.addState(new int[]{}, SettingsActivity.panel(u, false));
        btn.setBackground(sl);
        btn.setStateListAnimator(null);
        btn.setOnFocusChangeListener((v, has) -> v.animate().scaleX(has ? 1.02f : 1f).scaleY(has ? 1.05f : 1f)
                .setDuration(120).start());
        btn.setOnClickListener(click);
        return btn;
    }

    private TextView text(String s, int size, int color) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextColor(color);
        t.setTextSize(TypedValue.COMPLEX_UNIT_PX, size * u);
        return t;
    }

    private static LinearLayout.LayoutParams wide() {
        return new LinearLayout.LayoutParams(-1, -2);
    }
}
