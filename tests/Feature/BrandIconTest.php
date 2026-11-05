<?php

namespace Tests\Feature;

use App\Models\ClinicSetting;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

/** Install/share icons come from the uploaded logo (2026-11-02). */
class BrandIconTest extends TestCase
{
    use RefreshDatabase;

    public function test_icons_are_square_pngs_from_the_logo_and_manifest_points_at_them(): void
    {
        Storage::fake('public');
        $path = UploadedFile::fake()->image('logo.jpg', 300, 150)->store('logos', 'public');
        ClinicSetting::current()->update(['clinic_logo' => $path, 'clinic_name' => 'عيادة الاختبار']);

        foreach ([32, 180, 192, 512] as $size) {
            $response = $this->get("/brand-icon/{$size}.png")->assertOk();
            [$w, $h, $type] = getimagesize($response->baseResponse->getFile()->getPathname());
            $this->assertSame([$size, $size, IMAGETYPE_PNG], [$w, $h, $type]);
        }
        $this->get('/brand-icon/64.png')->assertNotFound();

        $this->getJson('/manifest.webmanifest')->assertOk()
            ->assertJsonPath('start_url', './start')
            ->assertJsonPath('icons.0.src', 'brand-icon/192.png');
        $this->getJson('/brand.json')->assertOk()
            ->assertJsonPath('name', 'عيادة الاختبار')
            ->assertJsonPath('logo', '/brand-icon/192.png');
    }

    public function test_without_a_logo_the_tooth_icon_is_sent(): void
    {
        $this->get('/brand-icon/192.png')->assertOk()->assertHeader('Content-Type', 'image/png');
        $this->getJson('/brand.json')->assertOk()->assertJsonPath('logo', null);
    }
}
