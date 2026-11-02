<?php

namespace Tests\Feature;

use App\Models\ClinicSetting;
use App\Models\EducationType;
use App\Models\Stage;
use App\Models\User;
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

    public function test_pairing_ignores_stages_since_the_screen_is_lab_only(): void
    {
        EducationType::create(['id' => 1, 'name' => 'صباحي']);
        $stage = Stage::create(['name' => 'الرابعة', 'education_type_id' => 1]);
        $pairing = WaitingScreenPairing::createNew();

        $this->actingAs(User::factory()->create(['role' => 'super_admin']))
            ->post('/waiting-screen/pair', ['code' => $pairing->code, 'stage_id' => $stage->id])
            ->assertSessionHasNoErrors();

        $pairing->refresh();
        $this->assertNotNull($pairing->confirmed_at);
        $this->assertNull($pairing->stage_id);

        $this->getJson('/api/v1/waiting-screen?token='.$pairing->token)
            ->assertOk()
            ->assertJsonPath('paired', true)
            ->assertJsonPath('stage_name', null)
            ->assertJsonPath('group_name', null);
    }

    public function test_the_tv_app_version_is_served_for_its_updater(): void
    {
        $this->getJson('/api/v1/app/version?platform=android_tv')->assertOk();
    }

    public function test_offline_logo_link_follows_the_page_host_over_http(): void
    {
        // The middleware alone: the full offline stack also needs an activation.
        config(['offline.edition' => true, 'filesystems.disks.public.url' => 'https://clinic.lan/storage']);
        Storage::forgetDisk('public');

        $url = null;
        (new \App\Http\Middleware\UseRequestHostForFilesOnIp())->handle(
            \Illuminate\Http\Request::create('http://clinic.lan/waiting-screen'),
            function () use (&$url) {
                $url = Storage::disk('public')->url('logos/logo.png');

                return response('ok');
            },
        );

        $this->assertSame('http://clinic.lan/storage/logos/logo.png', $url);
    }
}
