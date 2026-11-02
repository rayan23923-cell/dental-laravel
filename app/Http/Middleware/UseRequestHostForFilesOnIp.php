<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Symfony\Component\HttpFoundation\Response;

/**
 * Offline server opened by its IP (e.g. https://192.168.68.52) instead of
 * clinic.lan (2026-11-01, by request): uploaded files such as the clinic
 * logo got absolute links on APP_URL (clinic.lan). A device that cannot
 * resolve that name waited on it, so the logo never showed and the page was
 * slow. When the request came in on a bare IP, those links use the same
 * address as the page.
 *
 * Any address on the offline server (2026-11-02, by request): a TV that
 * opens the waiting screen over http://clinic.lan got logo links on
 * https://clinic.lan, whose certificate it does not trust, so the logo
 * never loaded. On the offline edition the links now always follow the
 * page's own scheme and host. The hosted system is unchanged.
 */
class UseRequestHostForFilesOnIp
{
    public function handle(Request $request, Closure $next): Response
    {
        $host = trim($request->getHost(), '[]');

        if (config('offline.edition') && $host !== '') {
            config(['filesystems.disks.public.url' => $request->getSchemeAndHttpHost().'/storage']);
            Storage::forgetDisk('public');
        }

        return $next($request);
    }
}
