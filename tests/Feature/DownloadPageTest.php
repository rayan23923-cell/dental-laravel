<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\File;
use Tests\TestCase;

/** /download (2026-10-18): store-style rows, with the offline apps when published. */
class DownloadPageTest extends TestCase
{
    use RefreshDatabase;

    private string $manifest;

    protected function setUp(): void
    {
        parent::setUp();
        $this->manifest = public_path('downloads/releases.json');
        File::ensureDirectoryExists(dirname($this->manifest));
        File::delete($this->manifest);
    }

    protected function tearDown(): void
    {
        File::delete($this->manifest);
        parent::tearDown();
    }

    public function test_it_lists_the_apps_and_the_offline_builds_when_published(): void
    {
        $this->get('/download')->assertOk()->assertSee('تطبيقات العيادة')->assertDontSee('أندرويد أوفلاين');

        File::put($this->manifest, json_encode([
            'android' => ['version' => '1.1.130', 'url' => 'https://example.test/DentalClinicApp-1.1.130.apk'],
            'android_offline' => ['version' => '1.1.130', 'url' => 'https://example.test/DentalClinicApp-offline-1.1.130.apk'],
            'windows_offline' => ['version' => '1.1.130', 'url' => 'https://example.test/DentalClinicSetup-offline-1.1.130.exe'],
        ]));

        $this->get('/download')->assertOk()
            ->assertSee('أندرويد أوفلاين')
            ->assertSee('ويندوز أوفلاين')
            ->assertSee('https://example.test/DentalClinicApp-offline-1.1.130.apk')
            ->assertSee('https://example.test/DentalClinicSetup-offline-1.1.130.exe');
    }
}
