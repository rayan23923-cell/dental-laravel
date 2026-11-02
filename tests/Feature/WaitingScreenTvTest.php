<?php

namespace Tests\Feature;

use App\Models\ClinicSetting;
use App\Models\WaitingScreenPairing;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

/**
 * Waiting screen on an unattended TV (2026-11-02): the clock follows the
 * server, and on the offline server the logo link follows the page's own
 * scheme and host (http://clinic.lan, an IP…).
 */
class WaitingScreenTvTest extends TestCase
{
    use RefreshDatabase;

    public function test_the_feed_carries_the_server_time_and_clinic_timezone(): void
    {
        $pairing = WaitingScreenPairing::createNew();
        $pairing->update(['confirmed_at' => now()]);

        $data = $this->getJson('/api/v1/waiting-screen?token='.$pairing->token)->assertOk()->json();

        $this->assertEqualsWithDelta(now()->getTimestampMs(), $data['server_time'], 5000);
        $this->assertSame(ClinicSetting::current()->clinic_timezone ?: 'Asia/Baghdad', $data['timezone']);

        // Unpaired screens get it too (their QR page shows the clock).
        $this->getJson('/api/v1/waiting-screen')->assertOk()->assertJsonStructure(['server_time', 'timezone']);
    }

    public function test_the_tv_app_version_is_served_for_its_updater(): void
    {
        $this->getJson('/api/v1/app/version?platform=android_tv')->assertOk();
    }

    public function test_offline_logo_link_follows_the_page_host_over_http(): void
    {
        config(['offline.edition' => true, 'app.url' => 'https://clinic.lan', 'filesystems.disks.public.url' => 'https://clinic.lan/storage']);
        Storage::forgetDisk('public');
        Storage::disk('public')->put('waiting-screen-tv-test/logo.png', 'x');
        ClinicSetting::current()->update(['clinic_logo' => 'waiting-screen-tv-test/logo.png']);

        $pairing = WaitingScreenPairing::createNew();
        $pairing->update(['confirmed_at' => now()]);

        $logo = $this->getJson('http://clinic.lan/api/v1/waiting-screen?token='.$pairing->token)->assertOk()->json('logo_url');

        Storage::disk('public')->deleteDirectory('waiting-screen-tv-test');

        $this->assertStringStartsWith('http://clinic.lan/storage/', (string) $logo);
    }
}
