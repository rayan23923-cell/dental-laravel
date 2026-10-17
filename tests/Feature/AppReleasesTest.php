<?php

namespace Tests\Feature;

use Illuminate\Support\Facades\File;
use Tests\TestCase;

class AppReleasesTest extends TestCase
{
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

    public function test_the_update_check_falls_back_to_the_config(): void
    {
        $this->getJson('/api/v1/desktop/version')
            ->assertOk()
            ->assertJsonPath('version', config('desktop_releases.windows.version'));
    }

    public function test_a_published_build_overrides_the_config(): void
    {
        File::put($this->manifest, json_encode([
            'windows' => ['version' => '1.1.9', 'url' => 'https://example.test/DentalClinicSetup-1.1.9.exe'],
        ]));

        $this->getJson('/api/v1/desktop/version')
            ->assertOk()
            ->assertJsonPath('version', '1.1.9')
            ->assertJsonPath('url', 'https://example.test/DentalClinicSetup-1.1.9.exe')
            ->assertJsonPath('zip_url', config('desktop_releases.windows.zip_url'));
    }

    public function test_the_phone_app_asks_for_its_own_platform(): void
    {
        File::put($this->manifest, json_encode([
            'windows' => ['version' => '1.1.9', 'url' => 'https://example.test/DentalClinicSetup-1.1.9.exe'],
            'android' => ['version' => '1.1.10', 'url' => 'https://example.test/DentalClinicApp-1.1.10.apk'],
        ]));

        $this->getJson('/api/v1/app/version?platform=android')
            ->assertOk()
            ->assertJsonPath('version', '1.1.10')
            ->assertJsonPath('url', 'https://example.test/DentalClinicApp-1.1.10.apk');
        $this->getJson('/api/v1/app/version')->assertOk()->assertJsonPath('version', '1.1.9');
    }
}
