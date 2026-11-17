<?php

namespace App\Services\Speech;

use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Http;
use Symfony\Component\Process\Process;
use Throwable;

/**
 * Text to a WAV file on the server (2026-11-17, by request), so the
 * waiting screen can call names on TVs that have no text-to-speech.
 *
 * Engines:
 * - `piper`: the Piper neural voice (MIT build 2023.11.14-2) with the
 *   Arabic voice «كريم». On the VPS it runs in its own small container
 *   (`deploy/vps/tts`, reached at `services.tts.url`); on the Windows
 *   server the package ships `piper\piper.exe` beside the app, which is
 *   run once per sentence. It only works while a sentence is made.
 * - `windows`: the voice built into Windows (System.Speech), when the
 *   Arabic speech pack is installed. Windows servers only.
 *
 * Every sentence is kept under storage/app/tts, so calling the same
 * patient again, or on several screens, makes it once.
 */
class SpeechSynthesizer
{
    public const ENGINES = ['piper', 'windows'];

    /**
     * Piper's Arabic voices (2026-11-17, by request), see
     * deploy/voices/voices.json; «ميرو» is the default.
     */
    public const VOICES = ['miro', 'miro_v2', 'dii', 'kareem', 'emirati'];

    public const DEFAULT_VOICE = 'miro';

    private const MAX_CHARS = 400;

    /** Engines this server can run, for the settings page. */
    public function available(): array
    {
        return array_values(array_filter(self::ENGINES, fn ($e) => $this->supports($e)));
    }

    public function supports(string $engine): bool
    {
        return match ($engine) {
            'piper' => filled(config('services.tts.url')) || $this->piperBinary() !== null,
            'windows' => PHP_OS_FAMILY === 'Windows',
            default => false,
        };
    }

    /**
     * Path of the WAV for $text. $rate is the speed in percent (100 =
     * normal). Throws SpeechException with an Arabic reason.
     */
    public function wav(string $text, string $engine = 'piper', int $rate = 100, string $voice = self::DEFAULT_VOICE): string
    {
        $voice = in_array($voice, self::VOICES, true) ? $voice : self::DEFAULT_VOICE;
        $text = trim(preg_replace('/\s+/u', ' ', $text));
        if ($text === '') {
            throw new SpeechException('لا يوجد نص للنطق.');
        }
        $text = mb_substr($text, 0, self::MAX_CHARS);
        $rate = max(50, min(200, $rate));
        if (! in_array($engine, self::ENGINES, true) || ! $this->supports($engine)) {
            throw new SpeechException($engine === 'windows'
                ? 'صوت ويندوز يعمل على سيرفر ويندوز فقط.'
                : 'محرك الصوت Piper غير مثبت على هذا السيرفر.');
        }

        $dir = storage_path('app/tts');
        $path = $dir.'/'.sha1($engine.'|'.($engine === 'piper' ? $voice : '').'|'.$rate.'|'.$text).'.wav';
        if (is_file($path) && filesize($path) > 44) {
            @touch($path);

            return $path;
        }

        File::ensureDirectoryExists($dir);
        $tmp = $path.'.'.bin2hex(random_bytes(4)).'.tmp';
        try {
            match ($engine) {
                'windows' => $this->windows($text, $rate, $tmp),
                default => filled(config('services.tts.url')) ? $this->piperHttp($text, $rate, $voice, $tmp) : $this->piperCli($text, $rate, $voice, $tmp),
            };
            if (! is_file($tmp) || filesize($tmp) <= 44) {
                throw new SpeechException('لم يُنتج محرك الصوت ملفًا.');
            }
            rename($tmp, $path);
        } catch (SpeechException $e) {
            throw $e;
        } catch (Throwable $e) {
            report($e);
            throw new SpeechException('تعذر توليد الصوت: '.$e->getMessage());
        } finally {
            @unlink($tmp);
        }

        $this->prune($dir);

        return $path;
    }

    private function piperHttp(string $text, int $rate, string $voice, string $out): void
    {
        $response = Http::timeout(30)->post(rtrim(config('services.tts.url'), '/').'/synthesize', [
            'text' => $text,
            'length_scale' => round(100 / $rate, 3),
            'voice' => $voice,
        ]);
        if ($response->status() === 404) {
            throw new SpeechException('هذا الصوت غير مثبت على السيرفر.');
        }
        if (! $response->successful()) {
            throw new SpeechException('خدمة الصوت لم تستجب ('.$response->status().').');
        }
        file_put_contents($out, $response->body());
    }

    private function piperCli(string $text, int $rate, string $voice, string $out): void
    {
        $bin = $this->piperBinary();
        $model = $this->piperModel($voice);
        if ($bin === null) {
            throw new SpeechException('محرك الصوت Piper غير موجود على هذا السيرفر.');
        }
        if ($model === null) {
            throw new SpeechException('هذا الصوت غير موجود على هذا السيرفر. حدّث البرنامج إلى آخر نسخة.');
        }
        $process = new Process([$bin, '--model', $model, '--output_file', $out, '--length_scale', (string) round(100 / $rate, 3)]);
        $process->setInput($text);
        $process->setTimeout(60);
        $process->run();
        if (! $process->isSuccessful()) {
            throw new SpeechException('فشل محرك الصوت Piper: '.mb_substr(trim($process->getErrorOutput()), -200));
        }
    }

    /** The Windows voice: System.Speech, an Arabic voice when installed. */
    private function windows(string $text, int $rate, string $out): void
    {
        $input = $out.'.txt';
        file_put_contents($input, $text);
        // -10..10; 100% = 0.
        $winRate = (int) max(-10, min(10, round(($rate - 100) / 10)));
        $script = <<<'PS'
            param([string]$In, [string]$Out, [int]$Rate)
            $ErrorActionPreference = 'Stop'
            Add-Type -AssemblyName System.Speech
            $s = New-Object System.Speech.Synthesis.SpeechSynthesizer
            $voice = $s.GetInstalledVoices() | Where-Object { $_.Enabled -and $_.VoiceInfo.Culture.TwoLetterISOLanguageName -eq 'ar' } | Select-Object -First 1
            if (-not $voice) { Write-Error 'NO_ARABIC_VOICE'; exit 3 }
            $s.SelectVoice($voice.VoiceInfo.Name)
            $s.Rate = $Rate
            $s.SetOutputToWaveFile($Out)
            $s.Speak([IO.File]::ReadAllText($In, [Text.Encoding]::UTF8))
            $s.Dispose()
            PS;
        $ps1 = $out.'.ps1';
        file_put_contents($ps1, "\u{FEFF}".$script);
        try {
            $process = new Process(['powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $ps1, '-In', $input, '-Out', $out, '-Rate', (string) $winRate]);
            $process->setTimeout(60);
            $process->run();
            if (! $process->isSuccessful()) {
                throw new SpeechException(str_contains($process->getErrorOutput(), 'NO_ARABIC_VOICE')
                    ? 'لا يوجد صوت عربي في ويندوز. أضِف اللغة العربية مع «تحويل النص إلى كلام» من إعدادات ويندوز ← الوقت واللغة.'
                    : 'فشل صوت ويندوز: '.mb_substr(trim($process->getErrorOutput()), -200));
            }
        } finally {
            @unlink($ps1);
            @unlink($input);
        }
    }

    private function piperBinary(): ?string
    {
        $candidates = array_filter([
            config('services.tts.piper_bin'),
            base_path('../piper/piper.exe'),
            base_path('../piper/piper'),
        ]);
        foreach ($candidates as $path) {
            if (is_file($path)) {
                return $path;
            }
        }

        return null;
    }

    /** Voices installed for Piper on this server. */
    public function voices(): array
    {
        if (filled(config('services.tts.url'))) {
            return cache()->remember('tts.voices', 600, function () {
                try {
                    $names = Http::timeout(5)->get(rtrim(config('services.tts.url'), '/').'/voices')->json();
                } catch (Throwable) {
                    return [];
                }

                return array_values(array_intersect(self::VOICES, is_array($names) ? $names : []));
            });
        }

        return array_values(array_filter(self::VOICES, fn ($v) => $this->piperModel($v) !== null));
    }

    private function voicesDir(): string
    {
        return config('services.tts.piper_voices') ?: base_path('../piper/voices');
    }

    private function piperModel(string $voice): ?string
    {
        $dir = $this->voicesDir();
        $candidates = array_filter([
            $dir.'/'.$voice.'.onnx',
            // The first Windows package named «كريم» after its file (2026-11-17).
            $voice === 'kareem' ? $dir.'/ar_JO-kareem-medium.onnx' : null,
        ]);
        foreach ($candidates as $path) {
            if (is_file($path) && is_file($path.'.json')) {
                return $path;
            }
        }

        return null;
    }

    /** Sentences not played for a week are removed, now and then. */
    private function prune(string $dir): void
    {
        if (random_int(1, 50) !== 1) {
            return;
        }
        foreach (glob($dir.'/*.wav') ?: [] as $file) {
            if (@filemtime($file) < time() - 7 * 86400) {
                @unlink($file);
            }
        }
    }
}
