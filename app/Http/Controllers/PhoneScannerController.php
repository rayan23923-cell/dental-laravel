<?php

namespace App\Http\Controllers;

use App\Models\ScannerPairing;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;
use Inertia\Inertia;
use Inertia\Response;

/**
 * The phone's side of "the phone as a QR scanner" (2026-10-12, by
 * request). No login: the phone reaches `/scan/{token}` from the
 * computer's QR, or types the six-digit code at `/scan`, and then sends
 * every code its camera reads. See App\Models\ScannerPairing.
 */
class PhoneScannerController extends Controller
{
    public function enter(): Response
    {
        return Inertia::render('PhoneScanner/Enter');
    }

    public function resolve(Request $request): RedirectResponse
    {
        $validated = $request->validate(['code' => ['required', 'digits:6']]);
        $pairing = ScannerPairing::findActiveByCode($validated['code']);

        if (! $pairing) {
            throw ValidationException::withMessages([
                'code' => 'رمز الاقتران غير صحيح أو منتهي. تحقق من الرمز الظاهر على الحاسوب.',
            ]);
        }

        return redirect()->route('phone-scanner.show', $pairing->token);
    }

    public function show(string $token): Response
    {
        $pairing = ScannerPairing::findActiveByToken($token);
        abort_unless($pairing, 404, 'رابط الماسح غير صالح أو منتهي.');

        $pairing->update(['phone_joined_at' => now()]);

        return Inertia::render('PhoneScanner/Scan', [
            'token' => $pairing->token,
            'userName' => $pairing->user?->full_name,
            'expiresAt' => $pairing->expires_at->toIso8601String(),
        ]);
    }

    public function store(Request $request, string $token): JsonResponse
    {
        $pairing = ScannerPairing::findActiveByToken($token);
        abort_unless($pairing, 410, 'انتهى الربط. امسح رمز الحاسوب من جديد.');

        $validated = $request->validate(['payload' => ['required', 'string', 'max:2000']]);
        $scan = $pairing->scans()->create(['payload' => $validated['payload']]);

        return response()->json(['data' => ['id' => $scan->id]], 201);
    }
}
