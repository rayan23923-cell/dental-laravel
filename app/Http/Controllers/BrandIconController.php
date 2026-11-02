<?php

namespace App\Http\Controllers;

use App\Models\ClinicSetting;
use App\Support\BrandIcon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\BinaryFileResponse;

/** The clinic logo as app/share icons, and the name + logo for static pages (2026-11-02). */
class BrandIconController extends Controller
{
    public function show(Request $request, int $size): BinaryFileResponse
    {
        abort_unless(in_array($size, BrandIcon::SIZES, true), 404);
        $maskable = $request->boolean('maskable');
        $file = BrandIcon::path($size, $maskable) ?? BrandIcon::fallback($size, $maskable);

        return response()->file($file, [
            'Content-Type' => 'image/png',
            'Cache-Control' => 'public, max-age=3600',
        ]);
    }

    /** For the offline Wi-Fi pages, which are plain HTML. */
    public function brand(): JsonResponse
    {
        $settings = ClinicSetting::current();

        return response()->json([
            'name' => $settings->clinic_name ?: config('app.name', 'Dental Clinic'),
            'logo' => $settings->logoUrl() ? '/brand-icon/192.png' : null,
        ])->header('Cache-Control', 'no-cache');
    }
}
