<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Group;
use App\Models\WaitingScreenSetting;
use App\Services\Speech\SpeechException;
use App\Services\Speech\SpeechSynthesizer;
use App\Services\Speech\VoiceDownloads;
use App\Support\VoiceCalls;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Mirrors App\Http\Controllers\WaitingScreenSettingController for the
 * Flutter client (2026-10-17): the public waiting screen's group, page
 * size and rotation. Which stage a TV shows is chosen when pairing it
 * (Api\WaitingScreenPairingController), not here.
 */
class WaitingScreenSettingController extends Controller
{
    public function show(): JsonResponse
    {
        return response()->json([
            'data' => [
                'settings' => $this->settings(),
                'groups' => Group::orderBy('name')->with('stage:id,name')->get(['id', 'name', 'stage_id'])
                    ->map(fn (Group $group) => [
                        'id' => $group->id,
                        'name' => $group->name,
                        'stage_name' => $group->stage?->name,
                    ])->values(),
            ],
        ]);
    }

    public function update(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'group_id' => ['nullable', 'exists:groups,id'],
            'patients_per_page' => ['required', 'integer', 'min:1', 'max:50'],
            'rotation_seconds' => ['required', 'integer', 'min:3', 'max:300'],
            // Optional so older app builds that don't send it keep working.
            'lab_scope' => ['sometimes', 'string', 'in:'.implode(',', WaitingScreenSetting::LAB_SCOPES)],
            // Calling names by voice (2026-11-17); optional for older app builds.
            ...VoiceCalls::rules(),
        ]);

        $this->ensureVoiceInstalled($validated);
        WaitingScreenSetting::current()->update($validated);

        return response()->json(['data' => ['settings' => $this->settings()]]);
    }

    private function settings(): array
    {
        $settings = WaitingScreenSetting::current();

        return [
            'group_id' => $settings->group_id,
            'patients_per_page' => $settings->patients_per_page,
            'rotation_seconds' => $settings->rotation_seconds,
            'lab_scope' => $settings->lab_scope ?: 'today',
        ] + VoiceCalls::settings($settings) + [
            'voice_engines' => app(SpeechSynthesizer::class)->available(),
            'voice_names' => SpeechSynthesizer::VOICES,
            'voice_installed' => app(SpeechSynthesizer::class)->voices(),
            'voice_downloadable' => VoiceDownloads::needed(),
        ];
    }

    /** «تجربة الصوت» for the app (2026-11-17): same as the web page's. */
    public function voicePreview(Request $request, SpeechSynthesizer $speech)
    {
        $data = $request->validate(VoiceCalls::previewRules());
        $settings = array_merge(VoiceCalls::settings(), array_filter($data, fn ($v) => $v !== null));

        try {
            $path = $speech->wav(VoiceCalls::sentence($data['name'], $data['kind'], $settings), $settings['voice_engine'], (int) $settings['voice_rate'], $settings['voice_name']);
        } catch (SpeechException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->file($path, ['Content-Type' => 'audio/wav', 'Cache-Control' => 'no-store']);
    }

    /**
     * «تنزيل الصوت» (2026-11-17, by request): the next piece of a voice this
     * Windows server does not carry yet; the page calls it until `done`.
     */
    public function downloadVoice(string $voice, VoiceDownloads $downloads): JsonResponse
    {
        try {
            return response()->json(['data' => $downloads->step($voice)]);
        } catch (SpeechException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }
    }

    /** A voice must be on this server before it is saved as the one that calls. */
    private function ensureVoiceInstalled(array $validated): void
    {
        $voice = $validated['voice_name'] ?? null;
        $engine = $validated['voice_engine'] ?? WaitingScreenSetting::current()->voice_engine ?? 'piper';
        if ($voice && $engine === 'piper' && VoiceDownloads::needed() && ! in_array($voice, app(SpeechSynthesizer::class)->voices(), true)) {
            throw \Illuminate\Validation\ValidationException::withMessages(['voice_name' => 'نزّل هذا الصوت أولًا من زر «تنزيل الصوت».']);
        }
    }
}
