<?php

namespace App\Http\Controllers;

use App\Models\OfflineLicense;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Response;

/**
 * The fixed link to an offline server over the internet (2026-10-31, by
 * request). The server's control panel runs a free Cloudflare tunnel, whose
 * address changes on every start, and reports it to the hosting (see
 * Api\OfflineLicenseController::tunnel); /go/{slug} leads to the clinic
 * system there and /go/{slug}/control to the panel's remote control page.
 */
class TunnelLinkController extends Controller
{
    public function __invoke(string $slug, ?string $to = null): RedirectResponse|Response
    {
        $license = OfflineLicense::where('tunnel_slug', $slug)->first();
        abort_unless($license && ! $license->revoked_at, 404);

        $target = $to === 'control' ? $license->tunnel_panel_url : $license->tunnel_url;
        if (! $target || ! $license->tunnelOnline()) {
            return response()->view('tunnel-offline', ['license' => $license], 503)
                ->header('Cache-Control', 'no-store')
                ->header('Retry-After', '60');
        }

        return redirect()->away($target)->header('Cache-Control', 'no-store');
    }
}
