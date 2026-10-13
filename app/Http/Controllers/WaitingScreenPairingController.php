<?php

namespace App\Http\Controllers;

use App\Models\Stage;
use App\Models\WaitingScreenPairing;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;
use Inertia\Inertia;
use Inertia\Response;

/**
 * The "system" side of the waiting-screen pairing code — the web
 * equivalent of the Flutter app's `WaitingScreenPairingConfirmScreen`,
 * for a staff member sitting at a computer near the TV rather than
 * scanning its QR from a phone (2026-09-09, "مثل يوتيوب": both a QR scan
 * and a typed code should activate the same pairing). See
 * `App\Models\WaitingScreenPairing`'s own docblock for the code's shape,
 * and `Api\WaitingScreenPairingController` for the app's QR-scan/
 * enter-code twin of this same flow.
 */
class WaitingScreenPairingController extends Controller
{
    public function create(): Response
    {
        return Inertia::render('WaitingScreenPairing/Enter', [
            'stages' => Stage::orderBy('name')->get(['id', 'name']),
        ]);
    }

    public function store(Request $request): RedirectResponse
    {
        $validated = $request->validate([
            'code' => ['required', 'digits:4'],
            'stage_id' => ['nullable', 'exists:stages,id'],
        ]);

        $pairing = WaitingScreenPairing::findPendingByCode($validated['code']);

        if (! $pairing) {
            throw ValidationException::withMessages([
                'code' => 'رمز غير صحيح أو منتهي الصلاحية — تحقق من الشاشة وأعد المحاولة.',
            ]);
        }

        $pairing->update([
            'stage_id' => $validated['stage_id'] ?? null,
            'confirmed_at' => now(),
        ]);

        return back()->with('success', 'تم تفعيل شاشة الانتظار بنجاح.');
    }
}
