<?php

namespace App\Services\Speech;

use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Http;
use Throwable;

/**
 * Voices downloaded when picked (2026-11-17, by request): the Windows
 * package carries the default voice only («دي» since 2026-11-18), so it stays small; another voice is fetched
 * from the hosting (/downloads/voices, published by deploy/vps/deploy.sh
 * with a manifest of sizes and SHA-256 sums) the first time it is chosen.
 *
 * The settings page calls `step()` again and again: each call fetches the
 * next piece with an HTTP Range request and appends it, so no request runs
 * long, a lost connection resumes where it stopped, and a progress bar can
 * follow. The finished file is checked against its SHA-256 before use.
 * Downloads live in storage/app/voices, which program updates keep.
 */
class VoiceDownloads
{
    private const CHUNK = 6 * 1024 * 1024;

    public static function dir(): string
    {
        return storage_path('app/voices');
    }

    /** Whether this server downloads voices (the Windows server) or has them all (the hosting). */
    public static function needed(): bool
    {
        return blank(config('services.tts.url'));
    }

    /** voice => ['size' => bytes, 'sha256' => hex] from the hosting, or [] offline. */
    public function manifest(): array
    {
        return cache()->remember('tts.voice-manifest', 600, function () {
            try {
                $data = Http::timeout(10)->get($this->baseUrl().'/voices.json')->json();
            } catch (Throwable) {
                return [];
            }

            return is_array($data) ? array_intersect_key($data, array_flip(SpeechSynthesizer::VOICES)) : [];
        });
    }

    /**
     * Fetches the next piece of $voice. Returns ['received', 'total', 'done'].
     * Throws SpeechException with an Arabic reason.
     */
    public function step(string $voice): array
    {
        if (! in_array($voice, SpeechSynthesizer::VOICES, true)) {
            throw new SpeechException('صوت غير معروف.');
        }
        $dir = self::dir();
        $model = "$dir/$voice.onnx";
        if (is_file($model) && is_file("$model.json")) {
            return ['received' => filesize($model), 'total' => filesize($model), 'done' => true];
        }

        cache()->forget('tts.voice-manifest');
        $info = $this->manifest()[$voice] ?? null;
        if (! $info || empty($info['size']) || empty($info['sha256'])) {
            throw new SpeechException('تعذر الوصول إلى سيرفر التنزيل. تأكد من اتصال هذه الحاسبة بالإنترنت.');
        }
        $total = (int) $info['size'];
        File::ensureDirectoryExists($dir);
        $part = "$model.part";
        $received = is_file($part) ? filesize($part) : 0;
        if ($received > $total) {
            @unlink($part);
            $received = 0;
        }

        if ($received < $total) {
            $end = min($received + self::CHUNK, $total) - 1;
            try {
                $response = Http::timeout(120)->withHeaders(['Range' => "bytes=$received-$end"])
                    ->get($this->baseUrl()."/$voice.onnx");
            } catch (Throwable) {
                throw new SpeechException('انقطع التنزيل. اضغط «تنزيل» مرة أخرى ليكمل من حيث توقف.');
            }
            $body = $response->body();
            if ($response->status() === 200 && $received > 0) {
                // The server ignored the range: start again from the whole file.
                file_put_contents($part, $body);
            } elseif (in_array($response->status(), [200, 206], true) && $body !== '') {
                file_put_contents($part, $body, FILE_APPEND);
            } else {
                throw new SpeechException('سيرفر التنزيل لم يرسل الصوت ('.$response->status().').');
            }
            clearstatcache(true, $part);
            $received = filesize($part);
        }

        if ($received < $total) {
            return ['received' => $received, 'total' => $total, 'done' => false];
        }

        if (! hash_equals(strtolower($info['sha256']), hash_file('sha256', $part))) {
            @unlink($part);
            throw new SpeechException('الملف المنزّل تالف، فحُذف. اضغط «تنزيل» لإعادة تنزيله.');
        }
        try {
            $json = Http::timeout(30)->get($this->baseUrl()."/$voice.onnx.json");
        } catch (Throwable) {
            throw new SpeechException('انقطع التنزيل. اضغط «تنزيل» مرة أخرى ليكمل من حيث توقف.');
        }
        if (! $json->successful() || ! is_array($json->json())) {
            throw new SpeechException('تعذر تنزيل إعدادات الصوت.');
        }
        file_put_contents("$model.json", $json->body());
        rename($part, $model);

        return ['received' => $total, 'total' => $total, 'done' => true];
    }

    private function baseUrl(): string
    {
        return rtrim(config('services.tts.voices_url') ?: 'https://dental.azoclinic.duckdns.org/downloads/voices', '/');
    }
}
