<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\DeviceToken;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Registers/unregisters the current device's FCM token against whichever
 * principal is logged in (Doctor or User) — see `App\Services\PushNotifier`
 * for how these get used once a real Firebase project is configured.
 */
class DeviceTokenController extends Controller
{
    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'token' => ['required', 'string'],
            'platform' => ['nullable', 'string'],
        ]);

        $principal = $request->user();

        DeviceToken::updateOrCreate(
            ['token' => $validated['token']],
            [
                'tokenable_type' => $principal::class,
                'tokenable_id' => $principal->id,
                'platform' => $validated['platform'] ?? 'android',
            ],
        );

        return response()->json(['message' => 'ok'], 201);
    }

    public function destroy(Request $request): JsonResponse
    {
        $validated = $request->validate(['token' => ['required', 'string']]);

        DeviceToken::where('token', $validated['token'])->delete();

        return response()->json(null, 204);
    }
}
