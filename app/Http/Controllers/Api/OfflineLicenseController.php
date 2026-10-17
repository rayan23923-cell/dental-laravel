<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\OfflineLicense;
use App\Support\OfflineLicensing;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

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
        ]);

        return DB::transaction(function () use ($data) {
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

            $license->forceFill([
                'machine_id' => $data['machine_id'],
                'machine_name' => $data['machine_name'] ?? $license->machine_name,
                'activated_at' => $license->activated_at ?? now(),
                'last_seen_at' => now(),
            ])->save();

            return response()->json(['license' => OfflineLicensing::issue($license)]);
        });
    }

    /** The newest offline build, for an activated computer's updater. */
    public function latest(Request $request): JsonResponse
    {
        $license = OfflineLicense::where('code', OfflineLicense::normalize($request->query('code')))->first();
        if (! $license || $license->revoked_at || ! $license->machine_id || $license->machine_id !== $request->query('machine')) {
            return response()->json(['message' => 'هذا الحاسوب غير مفعّل.'], 403);
        }
        $license->forceFill(['last_seen_at' => now()])->save();

        return response()->json(OfflineLicensing::latestBuild() ?? ['build' => 0]);
    }
}
