<?php

namespace App\Support;

use App\Models\WaitingScreenSetting;
use App\Services\Speech\SpeechSynthesizer;
use Illuminate\Validation\Rule;

/**
 * Calling patients by name on the waiting screen (2026-11-17, by request).
 * When a lab card turns green («النتيجة جاهزة») — and, if switched on,
 * when a patient is sent in for the test («بانتظار الفحص») — the screen
 * plays «{قبل الاسم} {الاسم}، {بعد الاسم}» made on the server
 * (App\Services\Speech\SpeechSynthesizer), the set number of times at the
 * set volume. TVs need no text-to-speech of their own.
 */
class VoiceCalls
{
    public const KINDS = ['ready', 'waiting'];

    public const DEFAULTS = [
        'voice_ready_before' => 'المريض',
        'voice_ready_after' => 'نتيجتك جاهزة، يرجى المراجعة إلى المختبر',
        'voice_waiting_before' => 'المريض',
        'voice_waiting_after' => 'يرجى التوجه إلى المختبر لإجراء الفحص',
    ];

    /** The settings form's fields, shared by the web page and the app. */
    public static function rules(): array
    {
        return [
            'voice_enabled' => ['sometimes', 'boolean'],
            'voice_engine' => ['sometimes', Rule::in(SpeechSynthesizer::ENGINES)],
            'voice_ready' => ['sometimes', 'boolean'],
            'voice_ready_before' => ['sometimes', 'nullable', 'string', 'max:150'],
            'voice_ready_after' => ['sometimes', 'nullable', 'string', 'max:150'],
            'voice_waiting' => ['sometimes', 'boolean'],
            'voice_waiting_before' => ['sometimes', 'nullable', 'string', 'max:150'],
            'voice_waiting_after' => ['sometimes', 'nullable', 'string', 'max:150'],
            'voice_repeat' => ['sometimes', 'integer', 'min:1', 'max:5'],
            'voice_volume' => ['sometimes', 'integer', 'min:0', 'max:100'],
            'voice_rate' => ['sometimes', 'integer', 'min:50', 'max:200'],
        ];
    }

    /** «تجربة الصوت»: a sample name and the form's unsaved wording. */
    public static function previewRules(): array
    {
        return [
            'name' => ['required', 'string', 'max:100'],
            'kind' => ['required', Rule::in(self::KINDS)],
            ...collect(self::rules())->only([
                'voice_engine', 'voice_ready_before', 'voice_ready_after', 'voice_waiting_before', 'voice_waiting_after', 'voice_rate',
            ])->all(),
        ];
    }

    /** Current values, with the default wording for anything left empty. */
    public static function settings(?WaitingScreenSetting $settings = null): array
    {
        $settings ??= WaitingScreenSetting::current();

        return [
            'voice_enabled' => (bool) ($settings->voice_enabled ?? true),
            'voice_engine' => $settings->voice_engine ?: 'piper',
            'voice_ready' => (bool) ($settings->voice_ready ?? true),
            'voice_ready_before' => $settings->voice_ready_before ?? self::DEFAULTS['voice_ready_before'],
            'voice_ready_after' => $settings->voice_ready_after ?? self::DEFAULTS['voice_ready_after'],
            'voice_waiting' => (bool) ($settings->voice_waiting ?? false),
            'voice_waiting_before' => $settings->voice_waiting_before ?? self::DEFAULTS['voice_waiting_before'],
            'voice_waiting_after' => $settings->voice_waiting_after ?? self::DEFAULTS['voice_waiting_after'],
            'voice_repeat' => (int) ($settings->voice_repeat ?: 2),
            'voice_volume' => (int) ($settings->voice_volume ?? 100),
            'voice_rate' => (int) ($settings->voice_rate ?: 100),
        ];
    }

    /** «المريض أحمد علي، نتيجتك جاهزة …» */
    public static function sentence(string $name, string $kind, array $settings): string
    {
        $before = trim((string) ($settings["voice_{$kind}_before"] ?? ''));
        $after = trim((string) ($settings["voice_{$kind}_after"] ?? ''));
        $name = trim($name);

        $text = trim($before.' '.$name);
        if ($after !== '') {
            $text .= (preg_match('/^[،,.؛:!؟?]/u', $after) ? '' : '، ').$after;
        }

        return $text;
    }

    /**
     * What the screen needs to call names: on/off per kind, how many
     * times, how loud, and a version that changes with the wording so the
     * screen never plays an old recording.
     */
    public static function forScreen(?WaitingScreenSetting $settings = null): array
    {
        $s = self::settings($settings);

        return [
            'enabled' => $s['voice_enabled'],
            'ready' => $s['voice_enabled'] && $s['voice_ready'],
            'waiting' => $s['voice_enabled'] && $s['voice_waiting'],
            'repeat' => $s['voice_repeat'],
            'volume' => $s['voice_volume'],
            'version' => substr(sha1(json_encode([$s['voice_engine'], $s['voice_rate'], $s['voice_ready_before'], $s['voice_ready_after'], $s['voice_waiting_before'], $s['voice_waiting_after']])), 0, 10),
        ];
    }
}
