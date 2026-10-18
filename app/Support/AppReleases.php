<?php

namespace App\Support;

/**
 * The app builds offered on /download and to the Windows self-updater.
 *
 * config/desktop_releases.php holds the fallback; the Flutter workflow
 * (.github/workflows/flutter-apps.yml) uploads each new build from main to
 * public/downloads/ together with releases.json, which overrides it per
 * platform. Read at request time because the config is cached at boot.
 */
class AppReleases
{
    public static function all(): array
    {
        $releases = config('desktop_releases');
        $path = public_path('downloads/releases.json');
        $published = is_file($path) ? json_decode((string) file_get_contents($path), true) : null;

        // *_offline: the same apps built to start on the clinic's offline server.
        foreach (['windows', 'android', 'ios', 'windows_offline', 'android_offline'] as $platform) {
            if (is_array($published[$platform] ?? null)) {
                $releases[$platform] = array_merge($releases[$platform] ?? [], $published[$platform]);
            }
        }

        return $releases;
    }

    public static function for(string $platform): array
    {
        return self::all()[$platform] ?? [];
    }
}
