package com.dentalclinic.tv;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.Uri;
import android.net.http.SslError;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.text.InputType;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowManager;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.SslErrorHandler;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.TextView;
import android.widget.Toast;

import java.net.InetAddress;

/**
 * The clinic's waiting screen on an Android TV (2026-11-02, by request): a
 * full-screen WebView on {server}/waiting-screen, separate from the phone
 * app. The page itself keeps the list fresh; this app makes sure it is
 * always up: it reconnects by itself when the network or the server is
 * down (3, 5, 10, 20, then every 30 s, and at once when the network comes
 * back), keeps the TV awake, recreates the page if the WebView crashes, and
 * starts with the TV (BootReceiver). Plain http is allowed so the clinic's
 * offline server works as http://clinic.lan or by its IP.
 */
public class MainActivity extends Activity {
    private static final String PREFS = "tv";
    private static final String KEY_SERVER = "server";
    private static final String CLINIC_SERVER = "http://clinic.lan";
    private static final String HOSTING_SERVER = "https://dental.azoclinic.duckdns.org";
    private static final int[] RETRY_SECONDS = {3, 5, 10, 20, 30};
    private static final long UPDATE_EVERY_MS = 6 * 60 * 60 * 1000L;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private FrameLayout root;
    private WebView webView;
    private TextView overlay;
    private int failures = 0;
    private boolean mainFrameFailed = false;
    private int countdown = 0;
    private ConnectivityManager.NetworkCallback networkCallback;
    private TextView updateBadge;

    private final Runnable updateCheck = new Runnable() {
        @Override
        public void run() {
            checkForUpdate(false);
            handler.postDelayed(this, UPDATE_EVERY_MS);
        }
    };

    private final Runnable retryTick = new Runnable() {
        @Override
        public void run() {
            if (countdown <= 0) {
                load();
                return;
            }
            showOverlay(getString(R.string.retrying, server(), countdown));
            countdown--;
            handler.postDelayed(this, 1000);
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        root = new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);
        overlay = new TextView(this);
        overlay.setTextColor(Color.WHITE);
        overlay.setTextSize(28);
        overlay.setGravity(Gravity.CENTER);
        overlay.setBackgroundColor(Color.parseColor("#0E7C86"));
        overlay.setPadding(48, 48, 48, 48);
        setContentView(root);
        createWebView();
        root.addView(overlay, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        updateBadge = new TextView(this);
        updateBadge.setTextColor(Color.WHITE);
        updateBadge.setTextSize(16);
        updateBadge.setBackgroundColor(Color.parseColor("#CC0E7C86"));
        updateBadge.setPadding(24, 12, 24, 12);
        updateBadge.setVisibility(View.GONE);
        FrameLayout.LayoutParams badgeParams = new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM | Gravity.START);
        badgeParams.setMargins(24, 24, 24, 24);
        root.addView(updateBadge, badgeParams);
        hideSystemUi();
        watchNetwork();
        // First check a minute after start, then every 6 hours.
        handler.postDelayed(updateCheck, 60_000);

        if (server().isEmpty()) {
            chooseServer();
        } else {
            load();
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private void createWebView() {
        if (webView != null) {
            root.removeView(webView);
            webView.destroy();
        }
        webView = new WebView(this);
        WebSettings s = webView.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true); // keeps the screen's pairing (localStorage)
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        s.setLoadWithOverviewMode(true);
        s.setUseWideViewPort(true);
        s.setCacheMode(WebSettings.LOAD_DEFAULT);
        webView.setBackgroundColor(Color.BLACK);
        webView.setWebViewClient(new Client());
        root.addView(webView, 0, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
    }

    private SharedPreferences prefs() {
        return getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    /** The chosen server, else the build's own (the offline build: clinic.lan). */
    private String server() {
        return prefs().getString(KEY_SERVER, getString(R.string.default_server));
    }

    private void saveServer(String value) {
        String v = value.trim();
        if (v.isEmpty()) return;
        if (!v.startsWith("http://") && !v.startsWith("https://")) v = "http://" + v;
        while (v.endsWith("/")) v = v.substring(0, v.length() - 1);
        if (v.endsWith("/waiting-screen")) v = v.substring(0, v.length() - "/waiting-screen".length());
        prefs().edit().putString(KEY_SERVER, v).apply();
        failures = 0;
        load();
    }

    private void load() {
        handler.removeCallbacks(retryTick);
        if (server().isEmpty()) return;
        mainFrameFailed = false;
        showOverlay(getString(R.string.connecting, server()));
        webView.loadUrl(server() + "/waiting-screen");
    }

    private void checkForUpdate(boolean manual) {
        if (server().isEmpty()) return;
        Updater.check(this, server(), manual, text -> {
            if (text == null) {
                updateBadge.setVisibility(View.GONE);
            } else {
                updateBadge.setText(text);
                updateBadge.setVisibility(View.VISIBLE);
            }
        });
    }

    private void scheduleRetry() {
        handler.removeCallbacks(retryTick);
        countdown = RETRY_SECONDS[Math.min(failures, RETRY_SECONDS.length - 1)];
        failures++;
        handler.post(retryTick);
    }

    private void showOverlay(String text) {
        overlay.setText(text);
        overlay.setVisibility(View.VISIBLE);
    }

    private void hideOverlay() {
        overlay.setVisibility(View.GONE);
    }

    private void watchNetwork() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return;
        ConnectivityManager cm = (ConnectivityManager) getSystemService(Context.CONNECTIVITY_SERVICE);
        if (cm == null) return;
        networkCallback = new ConnectivityManager.NetworkCallback() {
            @Override
            public void onAvailable(Network network) {
                handler.post(() -> {
                    if (mainFrameFailed) {
                        failures = 0;
                        load();
                    }
                });
            }
        };
        try {
            cm.registerDefaultNetworkCallback(networkCallback);
        } catch (RuntimeException ignored) {
            networkCallback = null;
        }
    }

    /** Self-signed certificates are accepted only for the clinic's own LAN server. */
    private static boolean isLanHost(String host) {
        if (host == null) return false;
        if (host.equals("clinic.lan") || host.endsWith(".lan") || host.endsWith(".local")) return true;
        if (!host.matches("[0-9.]+")) return false;
        try {
            InetAddress a = InetAddress.getByName(host);
            return a.isSiteLocalAddress() || a.isLoopbackAddress() || a.isLinkLocalAddress();
        } catch (Exception e) {
            return false;
        }
    }

    private class Client extends WebViewClient {
        @Override
        public void onPageFinished(WebView view, String url) {
            if (!mainFrameFailed) {
                failures = 0;
                hideOverlay();
            }
        }

        @Override
        public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
            if (request.isForMainFrame()) {
                mainFrameFailed = true;
                scheduleRetry();
            }
        }

        @Override
        public void onReceivedHttpError(WebView view, WebResourceRequest request, WebResourceResponse response) {
            if (request.isForMainFrame() && response.getStatusCode() >= 500) {
                mainFrameFailed = true;
                scheduleRetry();
            }
        }

        @SuppressLint("WebViewClientOnReceivedSslError")
        @Override
        public void onReceivedSslError(WebView view, SslErrorHandler handler, SslError error) {
            if (isLanHost(Uri.parse(error.getUrl()).getHost())) {
                handler.proceed();
            } else {
                handler.cancel();
            }
        }

        @Override
        public boolean onRenderProcessGone(WebView view, RenderProcessGoneDetail detail) {
            // The page crashed or was killed for memory: start it again.
            createWebView();
            load();
            return true;
        }
    }

    private void chooseServer() {
        String[] items = {
                getString(R.string.server_clinic),
                getString(R.string.server_hosting),
                getString(R.string.server_custom),
        };
        new AlertDialog.Builder(this)
                .setTitle(R.string.choose_server)
                .setItems(items, (d, which) -> {
                    if (which == 0) saveServer(CLINIC_SERVER);
                    else if (which == 1) saveServer(HOSTING_SERVER);
                    else askCustomServer();
                })
                .setCancelable(!server().isEmpty())
                .show();
    }

    private void askCustomServer() {
        EditText input = new EditText(this);
        input.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI);
        input.setHint(R.string.custom_hint);
        input.setText(server());
        new AlertDialog.Builder(this)
                .setTitle(R.string.server_custom)
                .setView(input)
                .setPositiveButton(R.string.save, (d, w) -> saveServer(input.getText().toString()))
                .setNegativeButton(R.string.cancel, (d, w) -> {
                    if (server().isEmpty()) chooseServer();
                })
                .show();
    }

    private void showMenu() {
        String[] items = {
                getString(R.string.menu_reload),
                getString(R.string.menu_server),
                getString(R.string.menu_autostart),
                getString(R.string.menu_update),
                getString(R.string.menu_exit),
        };
        new AlertDialog.Builder(this)
                .setTitle(R.string.menu_title)
                .setItems(items, (d, which) -> {
                    if (which == 0) { failures = 0; load(); }
                    else if (which == 1) chooseServer();
                    else if (which == 2) allowAutostart();
                    else if (which == 3) checkForUpdate(true);
                    else finish();
                })
                .show();
    }

    /** Android 10+ starts an app after boot only with "display over other apps". */
    private void allowAutostart() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)) {
            Toast.makeText(this, R.string.autostart_ok, Toast.LENGTH_LONG).show();
            return;
        }
        try {
            startActivity(new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:" + getPackageName())));
        } catch (ActivityNotFoundException e) {
            Toast.makeText(this, R.string.autostart_unavailable, Toast.LENGTH_LONG).show();
        }
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_MENU || keyCode == KeyEvent.KEYCODE_SETTINGS
                || keyCode == KeyEvent.KEYCODE_BACK) {
            showMenu();
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) hideSystemUi();
    }

    @SuppressWarnings("deprecation")
    private void hideSystemUi() {
        getWindow().getDecorView().setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                        | View.SYSTEM_UI_FLAG_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                        | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                        | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                        | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN);
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (webView != null) webView.onResume();
        if (mainFrameFailed) { failures = 0; load(); }
    }

    @Override
    protected void onPause() {
        if (webView != null) webView.onPause();
        super.onPause();
    }

    @Override
    protected void onDestroy() {
        handler.removeCallbacksAndMessages(null);
        if (networkCallback != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            ConnectivityManager cm = (ConnectivityManager) getSystemService(Context.CONNECTIVITY_SERVICE);
            try { cm.unregisterNetworkCallback(networkCallback); } catch (RuntimeException ignored) { }
        }
        if (webView != null) webView.destroy();
        super.onDestroy();
    }
}
