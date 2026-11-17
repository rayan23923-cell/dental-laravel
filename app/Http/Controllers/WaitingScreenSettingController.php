<?php

namespace App\Http\Controllers;

use App\Models\WaitingScreenSetting;
use App\Services\Speech\SpeechException;
use App\Services\Speech\SpeechSynthesizer;
use App\Support\VoiceCalls;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;
use Symfony\Component\HttpFoundation\BinaryFileResponse;

/**
 * Admin-facing controls for the public waiting-room display
 * (`/waiting-screen`, `Api\WaitingScreenController`). Mirrors
 * `ClinicSettingController`'s singleton edit/update shape.
 *
 * No stages or groups (2026-11-02, by request): the screen shows the lab
 * only, so the page only edits the display-tuning fields. `group_id` is
 * still accepted for old app builds but no longer used by the screen.
 */
class WaitingScreenSettingController extends Controller
{
    public function edit(): Response
    {
        return Inertia::render('WaitingScreenSettings/Edit', [
            'settings' => WaitingScreenSetting::current(),
            'screens' => \App\Support\WaitingScreenRemote::screens(),
            'returnMinutes' => \App\Models\WaitingScreenPairing::RETURN_MINUTES,
            // Calling names by voice (2026-11-17), see App\Support\VoiceCalls.
            'voice' => VoiceCalls::settings(),
            'voiceEngines' => app(SpeechSynthesizer::class)->available(),
            'voiceDefaults' => VoiceCalls::DEFAULTS,
        ]);
    }

    /**
     * «تجربة الصوت» (2026-11-17, by request): the sentence for a sample
     * name with the form's current wording, before it is saved.
     */
    public function voicePreview(Request $request, SpeechSynthesizer $speech): BinaryFileResponse|JsonResponse
    {
        $data = $request->validate(VoiceCalls::previewRules());
        $settings = array_merge(VoiceCalls::settings(), array_filter($data, fn ($v) => $v !== null));

        try {
            $path = $speech->wav(VoiceCalls::sentence($data['name'], $data['kind'], $settings), $settings['voice_engine'], (int) $settings['voice_rate']);
        } catch (SpeechException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->file($path, ['Content-Type' => 'audio/wav', 'Cache-Control' => 'no-store']);
    }

    public function update(Request $request): RedirectResponse
    {
        if ($request->input('group_id') === '') {
            $request->merge(['group_id' => null]);
        }

        $validated = $request->validate([
            'group_id' => ['nullable', 'exists:groups,id'],
            'patients_per_page' => ['required', 'integer', 'min:1', 'max:50'],
            'rotation_seconds' => ['required', 'integer', 'min:3', 'max:300'],
            // Optional so older app builds that don't send it keep working.
            'lab_scope' => ['sometimes', 'string', 'in:'.implode(',', WaitingScreenSetting::LAB_SCOPES)],
            ...VoiceCalls::rules(),
        ]);

        WaitingScreenSetting::current()->update($validated);

        return back()->with('success', 'Waiting screen settings updated.');
    }
}
