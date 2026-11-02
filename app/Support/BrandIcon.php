<?php

namespace App\Support;

use App\Models\ClinicSetting;
use Illuminate\Support\Facades\Storage;

/**
 * Square PNG icons made from the uploaded clinic logo (2026-11-02, by
 * request: installing or sharing the web app showed no logo). Browsers
 * want real square PNGs of the declared sizes on the page's own origin;
 * the raw upload could be any shape, type or URL host. Made once per logo
 * and size, kept in storage/app/brand-icons. Without a logo, the stock
 * tooth icons.
 */
class BrandIcon
{
    public const SIZES = [32, 180, 192, 512];

    /** Absolute path of the PNG to send, or null for the stock icon. */
    public static function path(int $size, bool $maskable = false): ?string
    {
        $settings = ClinicSetting::current();
        $logo = $settings->clinic_logo;
        $disk = Storage::disk('public');
        if (! $logo || ! $disk->exists($logo) || ! function_exists('imagecreatefromstring')) {
            return null;
        }

        $key = md5($logo.'|'.$disk->lastModified($logo).'|'.$disk->size($logo));
        $file = storage_path("app/brand-icons/{$key}-{$size}".($maskable ? '-m' : '').'.png');
        if (is_file($file)) {
            return $file;
        }

        $source = @imagecreatefromstring($disk->get($logo));
        if (! $source) {
            return null;
        }

        $canvas = imagecreatetruecolor($size, $size);
        imagealphablending($canvas, true);
        imagesavealpha($canvas, true);
        imagefill($canvas, 0, 0, imagecolorallocate($canvas, 255, 255, 255));

        // Maskable icons keep the logo inside the central safe zone (80%).
        $box = (int) round($size * ($maskable ? 0.72 : 0.92));
        $w = imagesx($source);
        $h = imagesy($source);
        $scale = min($box / $w, $box / $h);
        $dw = max(1, (int) round($w * $scale));
        $dh = max(1, (int) round($h * $scale));
        imagecopyresampled($canvas, $source, (int) (($size - $dw) / 2), (int) (($size - $dh) / 2), 0, 0, $dw, $dh, $w, $h);

        if (! is_dir(dirname($file))) {
            @mkdir(dirname($file), 0775, true);
        }
        imagepng($canvas, $file);
        imagedestroy($canvas);
        imagedestroy($source);

        return is_file($file) ? $file : null;
    }

    /** The stock tooth icon closest to $size. */
    public static function fallback(int $size, bool $maskable = false): string
    {
        if ($maskable) {
            return public_path('icons/icon-512-maskable.png');
        }

        return public_path($size > 192 ? 'icons/icon-512.png' : 'icons/icon-192.png');
    }
}
