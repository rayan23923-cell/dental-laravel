<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Models\WaitingScreenPairing;
use App\Services\PermissionManager;
use App\Support\QrCodeFactory;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;

/**
 * The pairing half of the waiting-screen privacy gate — see
 * `Api\WaitingScreenController` (the feed itself, which creates/reads
 * pairings by token) and the migration's own docblock for the full flow.
 *
 * This controller only has the two pieces the TV can't do itself: the QR
 * image (`qr()`, public — the TV has no login), and confirming a scanned
 * pairing with a chosen stage (`confirm()`, Sanctum-authenticated — only
 * someone logged into the Flutter app can do this, which is the actual
 * privacy boundary: anyone can *see* the QR, but only a logged-in staff
 * member/doctor can resolve it into a live appointments feed).
 */
class WaitingScreenPairingController extends Controller
{
    public function qr(Request $request, string $token): Response
    {
        WaitingScreenPairing::where('token', $token)->firstOrFail();

        return QrCodeFactory::pngResponse(
            QrCodeFactory::rawPayload(['type' => 'waiting_screen_pairing', 'token' => $token]),
            (int) $request->integer('size', 320),
        );
    }

    /**
     * The "enter the code instead of scanning" alternative — resolves a
     * typed 4-digit code to its pairing's token, so the app can then call
     * `confirm()` exactly the same way the QR-scan flow does. Kept
     * separate from `confirm()` rather than accepting either a token or a
     * code there: this way the route/URL structure (`{token}` as a path
     * segment) never has to distinguish the two shapes.
     */
    public function resolveCode(Request $request): JsonResponse
    {
        $this->authorizePairing($request);
        $validated = $request->validate(['code' => ['required', 'digits:4']]);

        $pairing = WaitingScreenPairing::findPendingByCode($validated['code']);

        abort_if(! $pairing, 404, 'رمز غير صحيح أو منتهي الصلاحية.');

        return response()->json(['data' => ['token' => $pairing->token]]);
    }

    public function confirm(Request $request, string $token): JsonResponse
    {
        $this->authorizePairing($request);
        $validated = $request->validate([
            'stage_id' => ['nullable', 'exists:stages,id'],
        ]);

        $pairing = WaitingScreenPairing::where('token', $token)->firstOrFail();

        abort_if($pairing->isStale(), 410, 'انتهت صلاحية هذا الرمز — أعد فتح الشاشة وامسح الرمز الجديد.');

        $pairing->update([
            'stage_id' => $validated['stage_id'] ?? null,
            'confirmed_at' => now(),
        ]);

        return response()->json([
            'data' => [
                'stage_name' => $pairing->stage?->name,
            ],
        ]);
    }

    /**
     * Staff accounts pair a TV with the waiting_screen.pair permission
     * (2026-10-24, by request); doctors keep pairing as before.
     */
    private function authorizePairing(Request $request): void
    {
        $user = $request->user();
        abort_if($user instanceof User && ! (new PermissionManager($user))->can('waiting_screen', 'pair'), 403);
    }
}
