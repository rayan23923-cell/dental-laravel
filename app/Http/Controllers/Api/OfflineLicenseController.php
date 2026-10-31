<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\OfflineLicense;
use App\Support\OfflineLicensing;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Symfony\Component\HttpFoundation\Response;

/**
 * Hosted side of offline activation (2026-10-17, by request). Public: the
 * offline copy calls it once to activate (see App\Http\Controllers\Offline\
 * ActivationController) and its control panel calls `latest` to update.
 */
class OfflineLicenseController extends Controller
{
    public function activate(Request $request): JsonResponse
    {
        $data = $request->validate([
            'code' => ['required', 'string', 'max:40'],
            'machine_id' => ['required', 'string', 'regex:/^[A-F0-9]{4}(-[A-F0-9]{4}){3}$/'],
            'machine_name' => ['nullable', 'string', 'max:100'],
            'build' => ['nullable', 'integer', 'min:0'],
        ]);

        return DB::transaction(function () use ($data, $request) {
            $license = OfflineLicense::where('code', OfflineLicense::normalize($data['code']))->lockForUpdate()->first();

            if (! $license) {
                return response()->json(['message' => 'رمز التفعيل غير صحيح.'], 422);
            }
            if ($license->revoked_at) {
                return response()->json(['message' => 'رمز التفعيل هذا موقوف. راجع إدارة النظام.'], 422);
            }
            // Used once: from then on it only works again on the same computer.
            if ($license->machine_id && $license->machine_id !== $data['machine_id']) {
                return response()->json(['message' => 'رمز التفعيل هذا مستخدم على حاسوب آخر.'], 422);
            }
            // A new computer only while the university is under its device limit.
            $university = $license->machine_id ? null : $license->universityRecord()->lockForUpdate()->first();
            if ($university && ! $university->hasRoomFor($data['machine_id'])) {
                return response()->json(['message' => 'وصلت الجامعة إلى الحد الأقصى لعدد الأجهزة ('.$university->max_devices.'). راجع إدارة النظام.'], 422);
            }

            $license->forceFill([
                'machine_id' => $data['machine_id'],
                'machine_name' => $data['machine_name'] ?? $license->machine_name,
                'activated_at' => $license->activated_at ?? now(),
                'last_seen_at' => now(),
                'installed_build' => $data['build'] ?? $license->installed_build,
                'last_ip' => $request->ip(),
            ])->save();

            return response()->json(['license' => OfflineLicensing::issue($license)]);
        });
    }

    /**
     * The newest offline build, for an activated computer's updater, which
     * also reports the build it runs (`build`) for the licensing portal.
     */
    public function latest(Request $request): JsonResponse
    {
        $license = $this->activeLicense($request);
        if (! $license) {
            return response()->json(['message' => 'هذا الحاسوب غير مفعّل.'], 403);
        }
        $build = filter_var($request->query('build'), FILTER_VALIDATE_INT, ['options' => ['min_range' => 0]]);
        $license->forceFill([
            'last_seen_at' => now(),
            'installed_build' => $build === false ? $license->installed_build : $build,
            'last_ip' => $request->ip(),
        ])->save();

        $latest = OfflineLicensing::latestBuild();
        if (! $latest) {
            return response()->json(['build' => 0]);
        }
        // The package is no longer public (2026-10-24): this computer
        // downloads it with its own code, from `download` below.
        $latest['url'] = route('api.offline.download', ['code' => $license->code, 'machine' => $license->machine_id]);
        unset($latest['client_url']);

        return response()->json($latest);
    }

    /** The newest offline server package, for an activated computer's updater. */
    public function download(Request $request): Response
    {
        abort_unless($this->activeLicense($request), 403, 'هذا الحاسوب غير مفعّل.');

        return OfflineLicensing::packageDownload('server');
    }

    /**
     * The control panel reports its tunnel's current addresses (2026-10-31,
     * by request: reach and control the offline server online). A free
     * Cloudflare tunnel gets a new address on every start, so the hosting
     * keeps a fixed link, /go/{slug}, that leads to the latest one. Empty
     * addresses mean the tunnel was turned off.
     */
    public function tunnel(Request $request): JsonResponse
    {
        $data = $request->validate([
            'code' => ['required', 'string', 'max:40'],
            'machine' => ['required', 'string', 'max:32'],
            'url' => ['nullable', 'string', 'max:255', 'url:https'],
            'panel_url' => ['nullable', 'string', 'max:255', 'url:https'],
        ]);
        $license = $this->activeLicense($request, true);
        if (! $license) {
            return response()->json(['message' => 'هذا الحاسوب غير مفعّل.'], 403);
        }

        $license->forceFill([
            'tunnel_slug' => $license->tunnel_slug ?: self::newSlug(),
            'tunnel_url' => $data['url'] ?? null,
            'tunnel_panel_url' => $data['panel_url'] ?? null,
            'tunnel_seen_at' => ($data['url'] ?? null) ? now() : null,
            'last_seen_at' => now(),
            'last_ip' => $request->ip(),
        ])->save();

        return response()->json([
            'link' => $license->tunnelLink(),
            'panel_link' => $license->tunnelLink('control'),
        ]);
    }

    private static function newSlug(): string
    {
        do {
            $slug = strtolower(Str::random(12));
        } while (OfflineLicense::where('tunnel_slug', $slug)->exists());

        return $slug;
    }

    private function activeLicense(Request $request, bool $fromBody = false): ?OfflineLicense
    {
        $code = $fromBody ? $request->input('code') : $request->query('code');
        $machine = $fromBody ? $request->input('machine') : $request->query('machine');
        $license = OfflineLicense::where('code', OfflineLicense::normalize($code))->first();

        return $license && ! $license->revoked_at && $license->machine_id && is_string($machine) && $license->machine_id === $machine
            ? $license : null;
    }
}
