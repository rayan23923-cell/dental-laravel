<?php

namespace App\Http\Controllers;

use App\Models\ScannerPairing;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * The computer's side of "the phone as a QR scanner" (2026-10-12): open a
 * pairing, poll it for what the phone scanned, end it. Shared by the web
 * app (session) and the Windows app (Sanctum, routes/api.php); see
 * App\Models\ScannerPairing for the flow and PhoneScannerController for the
 * phone's side.
 */
class ScannerPairingController extends Controller
{
    public function store(Request $request): JsonResponse
    {
        // Staff accounts only: a Doctor token on the API has no `users` row.
        abort_unless($request->user() instanceof User, 403);

        return response()->json(['data' => ScannerPairing::open($request->user())->forDesktop()], 201);
    }

    public function show(Request $request, ScannerPairing $scannerPairing): JsonResponse
    {
        $this->authorizeOwner($request, $scannerPairing);

        return response()->json(['data' => $scannerPairing->forDesktop()]);
    }

    public function scans(Request $request, ScannerPairing $scannerPairing): JsonResponse
    {
        $this->authorizeOwner($request, $scannerPairing);

        return response()->json(['data' => $scannerPairing->scansAfter($request->integer('after'))]);
    }

    public function destroy(Request $request, ScannerPairing $scannerPairing): JsonResponse
    {
        $this->authorizeOwner($request, $scannerPairing);
        $scannerPairing->delete();

        return response()->json(['data' => null]);
    }

    /** Only the computer that opened it, and only while it is live (410 once expired). */
    private function authorizeOwner(Request $request, ScannerPairing $pairing): void
    {
        abort_unless($request->user() instanceof User && $pairing->user_id === $request->user()->id, 404);
        abort_if($pairing->expires_at->isPast(), 410, 'انتهت صلاحية ربط الموبايل.');
    }
}
