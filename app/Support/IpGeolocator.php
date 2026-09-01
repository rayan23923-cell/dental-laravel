<?php

namespace App\Support;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Best-effort "city, country" for an IP address — used once at login
 * (`Api\AuthController::login()`) to label a new session for the
 * Instagram-style "Active sessions" screen, matching the "الموقع"
 * (location) the user asked for. Never blocks or fails the login itself:
 * any failure (unreachable service, rate limit, private/local IP) just
 * means the session shows no location, not an error.
 */
class IpGeolocator
{
    /**
     * Private/loopback/reserved ranges never resolve to a real location —
     * skip the network call entirely for them rather than spending a
     * request on a guaranteed-empty result (also covers every local dev
     * environment, where every login would otherwise hit the API).
     */
    public static function locate(?string $ip): ?string
    {
        if (! $ip || self::isPrivate($ip)) {
            return null;
        }

        try {
            $response = Http::timeout(2)->get("http://ip-api.com/json/{$ip}", [
                'fields' => 'status,city,country',
            ]);

            if (! $response->ok() || $response->json('status') !== 'success') {
                return null;
            }

            $city = $response->json('city');
            $country = $response->json('country');

            return collect([$city, $country])->filter()->implode(', ') ?: null;
        } catch (\Throwable $e) {
            // Network hiccup, DNS failure, timeout — never let a
            // best-effort location lookup break login itself.
            Log::info('IpGeolocator: lookup failed', ['ip' => $ip, 'error' => $e->getMessage()]);

            return null;
        }
    }

    private static function isPrivate(string $ip): bool
    {
        return filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE) === false;
    }
}
