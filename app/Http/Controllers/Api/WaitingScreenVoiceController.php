<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\PatientRegistration;
use App\Models\WaitingScreenPairing;
use App\Models\WaitingScreenSetting;
use App\Services\Speech\SpeechException;
use App\Services\Speech\SpeechSynthesizer;
use App\Support\VoiceCalls;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\BinaryFileResponse;

/**
 * The spoken call for one lab patient (2026-11-17, by request): «المريض
 * أحمد علي، نتيجتك جاهزة …» as a WAV the waiting screen plays, so TVs
 * without text-to-speech can call names. Public like the feed, but only
 * for a confirmed screen's token, and only for a patient that screen is
 * showing in that state, so it cannot be used to read out anyone else.
 */
class WaitingScreenVoiceController extends Controller
{
    public function __invoke(Request $request, PatientRegistration $patientRegistration, SpeechSynthesizer $speech): BinaryFileResponse|JsonResponse
    {
        $kind = $request->string('kind')->toString();
        $token = $request->string('token')->toString();
        $pairing = $token !== '' ? WaitingScreenPairing::where('token', $token)->first() : null;
        abort_unless($pairing && ! $pairing->isStale() && $pairing->isConfirmed(), 403);

        $settings = VoiceCalls::settings(WaitingScreenSetting::current());
        abort_unless(in_array($kind, VoiceCalls::KINDS, true) && $settings['voice_enabled'] && $settings["voice_{$kind}"], 404);

        $shown = $patientRegistration->screening_status === 'pending'
            && $patientRegistration->lab_archived_at === null
            && $patientRegistration->lab_deleted_at === null
            && ($kind === 'ready'
                ? $patientRegistration->lab_result_received_at !== null
                : $patientRegistration->lab_sample_printed_at !== null && $patientRegistration->lab_result_received_at === null);
        abort_unless($shown, 404);

        try {
            $path = $speech->wav(VoiceCalls::sentence($patientRegistration->name, $kind, $settings), $settings['voice_engine'], $settings['voice_rate'], $settings['voice_name']);
        } catch (SpeechException $e) {
            return response()->json(['message' => $e->getMessage()], 503);
        }

        return response()->file($path, ['Content-Type' => 'audio/wav', 'Cache-Control' => 'private, max-age=3600']);
    }
}
