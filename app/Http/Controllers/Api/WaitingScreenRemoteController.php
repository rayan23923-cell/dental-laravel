<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\WaitingScreenPairing;
use App\Support\WaitingScreenRemote;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/** App side of controlling paired waiting screens (2026-11-03), see WaitingScreenRemote. */
class WaitingScreenRemoteController extends Controller
{
    public function index(): JsonResponse
    {
        return response()->json(['data' => WaitingScreenRemote::screens()]);
    }

    public function command(Request $request, WaitingScreenPairing $pairing): JsonResponse
    {
        WaitingScreenRemote::command($request, $pairing);

        return response()->json(['data' => $pairing->fresh()->toScreenArray()]);
    }

    public function update(Request $request, WaitingScreenPairing $pairing): JsonResponse
    {
        WaitingScreenRemote::rename($request, $pairing);

        return response()->json(['data' => $pairing->fresh()->toScreenArray()]);
    }

    public function destroy(WaitingScreenPairing $pairing): JsonResponse
    {
        WaitingScreenRemote::unpair($pairing);

        return response()->json(['data' => null]);
    }
}
