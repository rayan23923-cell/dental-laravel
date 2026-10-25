<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Browser security headers on every page and API answer (2026-10-25,
 * security review): no framing by other sites (clickjacking), no MIME
 * sniffing, no full URLs leaked to other sites, and on the hosted HTTPS
 * site HSTS. The offline copy gets no HSTS: its CA certificate is fetched
 * over plain http://clinic.lan/ca.crt before the browser trusts HTTPS there.
 * The camera stays allowed for this site (phone scanner, photos).
 */
class SecurityHeaders
{
    public function handle(Request $request, Closure $next): Response
    {
        $response = $next($request);
        $headers = $response->headers;

        $headers->set('X-Frame-Options', 'SAMEORIGIN', false);
        $headers->set('X-Content-Type-Options', 'nosniff', false);
        $headers->set('Referrer-Policy', 'strict-origin-when-cross-origin', false);
        $headers->set('Permissions-Policy', 'camera=(self), microphone=(), geolocation=(), payment=()', false);

        if ($request->isSecure() && ! config('offline.edition')) {
            $headers->set('Strict-Transport-Security', 'max-age=31536000', false);
        }

        return $response;
    }
}
