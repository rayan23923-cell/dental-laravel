<?php

namespace App\Http\Controllers;

use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Symfony\Component\HttpFoundation\Response;

/**
 * Opens the system on its own when a device joins the clinic Wi-Fi
 * (2026-10-12, by request; offline package only). The offline DNS points
 * the phones' and computers' "is there internet?" check addresses at this
 * computer; Caddy passes them to the app untouched and the
 * AnswerConnectivityChecks middleware hands them here by host name.
 *
 * A device that has not opened the system yet gets a redirect, which makes
 * it show the "sign in to network" page with our setup page in it. Once it
 * has opened that page, its checks get the normal success answer, so the
 * device treats the Wi-Fi as connected and keeps using it (Android would
 * otherwise move to mobile data, where clinic.lan does not exist).
 */
class CaptivePortalController extends Controller
{
    /** How long a device counts as having seen the page (then it opens again). */
    public const SEEN_HOURS = 12;

    /** Kept in step with $captiveHosts in offline/windows/prepare.ps1. */
    public const HOSTS = [
        'connectivitycheck.gstatic.com', 'connectivitycheck.android.com', 'clients1.google.com', 'clients3.google.com',
        'connectivitycheck.samsung.com', 'connect.rom.miui.com', 'conn1.oppomobile.com', 'conn2.oppomobile.com',
        'connectivitycheck.platform.hicloud.com', 'cp.cloudflare.com',
        'captive.apple.com', 'www.appleiphonecell.com', 'www.itools.info', 'www.ibook.info', 'www.airport.us', 'www.thinkdifferent.us',
        'www.msftconnecttest.com', 'msftconnecttest.com', 'www.msftncsi.com', 'detectportal.firefox.com',
        'nmcheck.gnome.org', 'connectivity-check.ubuntu.com',
    ];

    public function check(Request $request): Response
    {
        if (Cache::has($this->key($request))) {
            return $this->success($request->getHost(), $request->path());
        }

        return redirect()->away('http://'.$this->serverHost().'/portal', 302);
    }

    public function portal(Request $request): RedirectResponse
    {
        Cache::put($this->key($request), true, now()->addHours(self::SEEN_HOURS));

        return redirect()->away('http://'.$this->serverHost().'/setup', 302);
    }

    private function key(Request $request): string
    {
        return 'captive-seen:'.$request->ip();
    }

    /**
     * Where the "sign in to network" page sends the device: this computer's
     * network address, which prepare.ps1 writes to lan-ip.txt next to the
     * app folder. The address works even when the device's name lookup is
     * slow or not ours (2026-10-19: clinic.lan did not open on first join);
     * without the file, the name APP_URL has (clinic.lan).
     */
    private function serverHost(): string
    {
        $file = config('app.lan_ip_file') ?: base_path('../lan-ip.txt');
        $ip = is_file($file) ? trim((string) file_get_contents($file)) : '';
        if (filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4) && ! str_starts_with($ip, '127.')) {
            return $ip;
        }

        return parse_url(config('app.url'), PHP_URL_HOST) ?: 'clinic.lan';
    }

    /** What each kind of device expects when the internet is reachable. */
    private function success(string $host, string $path): Response
    {
        $host = strtolower($host);
        $path = strtolower($path);

        if (str_contains($host, 'apple') || in_array($host, ['www.itools.info', 'www.ibook.info', 'www.airport.us', 'www.thinkdifferent.us'], true)) {
            return response('<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>', 200, ['Content-Type' => 'text/html']);
        }
        if (str_contains($host, 'msftconnecttest')) {
            return response('Microsoft Connect Test', 200, ['Content-Type' => 'text/plain']);
        }
        if (str_contains($host, 'msftncsi')) {
            return response('Microsoft NCSI', 200, ['Content-Type' => 'text/plain']);
        }
        if (str_contains($host, 'detectportal.firefox')) {
            return str_contains($path, 'canonical')
                ? response('<meta http-equiv="refresh" content="0;url=https://support.mozilla.org/kb/captive-portal"/>', 200, ['Content-Type' => 'text/html'])
                : response("success\n", 200, ['Content-Type' => 'text/plain']);
        }
        if (str_contains($host, 'nmcheck.gnome') || str_contains($host, 'connectivity-check.ubuntu')) {
            return response('NetworkManager is online', 200, ['Content-Type' => 'text/plain', 'X-NetworkManager-Status' => 'online']);
        }

        // Android (Google, Samsung, Xiaomi, Oppo, Huawei) and the rest: an empty 204.
        return response('', 204);
    }
}
