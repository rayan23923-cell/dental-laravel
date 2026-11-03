<?php

namespace Tests\Feature;

use App\Models\PatientRegistration;
use App\Models\User;
use App\Models\WaitingScreenPairing;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * "بانتظار الفحص" on the waiting screen (2026-11-02): patients whose lab
 * samples sheet was printed and whose result is not yet recorded.
 */
class WaitingScreenLabWaitingTest extends TestCase
{
    use RefreshDatabase;

    private function registration(string $name): PatientRegistration
    {
        return PatientRegistration::create(['name' => $name, 'phone' => '0770', 'screening_status' => 'pending']);
    }

    private function labWaiting(string $key = 'lab_waiting'): array
    {
        $pairing = WaitingScreenPairing::createNew();
        $pairing->update(['confirmed_at' => now()]);

        return collect($this->getJson('/api/v1/waiting-screen?token='.$pairing->token)
            ->assertOk()
            ->json($key))->pluck('patient_name')->all();
    }

    public function test_receive_turns_the_card_green_until_the_result_is_printed(): void
    {
        $admin = User::factory()->create(['role' => 'super_admin']);
        $web = $this->registration('مريض الويب');
        $app = $this->registration('مريض التطبيق');
        $web->markLabSamplePrinted();
        $app->markLabSamplePrinted();

        Sanctum::actingAs($admin);
        $this->actingAs($admin)->postJson("/lab/{$web->id}/received")->assertOk();
        $this->postJson("/api/v1/lab/{$app->id}/result-received")
            ->assertOk()
            ->assertJsonPath('data.registration.id', $app->id);

        // Green "النتيجة جاهزة", still on the screen.
        $this->assertSame([], $this->labWaiting());
        $this->assertSame(['مريض الويب', 'مريض التطبيق'], $this->labWaiting('lab_ready'));
        $this->assertSame('pending', $web->fresh()->screening_status);

        // Recording the result prints it: the patient has it, so they leave.
        $this->postJson("/api/v1/patient-registrations/{$web->id}/screening", ['screening_status' => 'clear'])->assertOk();
        $this->assertSame(['مريض التطبيق'], $this->labWaiting('lab_ready'));
        $this->postJson("/api/v1/patient-registrations/{$app->id}/screening", ['screening_status' => 'flagged'])->assertOk();
        $this->assertSame([], $this->labWaiting('lab_ready'));
    }

    public function test_printed_samples_sheet_shows_until_the_result_is_recorded(): void
    {
        $admin = User::factory()->create(['role' => 'super_admin']);
        $web = $this->registration('مريض الويب');
        $app = $this->registration('مريض التطبيق');
        $this->registration('مريض لم يبدأ');

        $this->assertSame([], $this->labWaiting());

        // Web "بدء الفحص" opens the sheet; the app reports its own print.
        $this->actingAs($admin)->get("/lab/{$web->id}/sample?autoprint=1")->assertOk();
        Sanctum::actingAs($admin);
        $this->postJson("/api/v1/lab/{$app->id}/sample-printed")->assertOk();

        $this->assertSame(['مريض الويب', 'مريض التطبيق'], $this->labWaiting());

        $this->postJson("/api/v1/patient-registrations/{$web->id}/screening", ['screening_status' => 'clear'])->assertOk();
        $this->assertSame(['مريض التطبيق'], $this->labWaiting());

        // A recorded result never puts the patient back on the list.
        $this->postJson("/api/v1/lab/{$web->id}/sample-printed")->assertOk();
        $this->assertSame(['مريض التطبيق'], $this->labWaiting());
    }

    public function test_lab_cards_carry_the_registration_id_for_the_glow(): void
    {
        $patient = $this->registration('مريض جديد');
        $patient->markLabSamplePrinted();

        $pairing = WaitingScreenPairing::createNew();
        $pairing->update(['confirmed_at' => now()]);

        $this->getJson('/api/v1/waiting-screen?token='.$pairing->token)
            ->assertOk()
            ->assertJsonPath('lab.0.id', $patient->id)
            ->assertJsonPath('lab.0.status', 'waiting');
    }

    public function test_yesterdays_printed_sheet_is_not_shown(): void
    {
        $old = $this->registration('مريض الأمس');
        $old->forceFill(['lab_sample_printed_at' => now()->subDay()])->save();

        $this->assertSame([], $this->labWaiting());
    }

    public function test_lab_scope_today_starts_at_midnight_clinic_time_and_all_shows_every_pending(): void
    {
        $this->travelTo(\Illuminate\Support\Carbon::parse('2026-11-03 09:00:00', 'UTC'));
        \App\Models\ClinicSetting::current()->update(['clinic_timezone' => 'Asia/Baghdad']);

        // 22:30 UTC yesterday = 01:30 today in Baghdad; 20:30 UTC = 23:30 yesterday there.
        $this->registration('بعد منتصف الليل')->forceFill(['lab_sample_printed_at' => '2026-11-02 22:30:00'])->save();
        $this->registration('قبل منتصف الليل')->forceFill(['lab_sample_printed_at' => '2026-11-02 20:30:00'])->save();
        $this->registration('الأسبوع الماضي')->forceFill(['lab_sample_printed_at' => '2026-10-27 08:00:00'])->save();
        $done = $this->registration('منتهي');
        $done->forceFill(['lab_sample_printed_at' => '2026-11-01 08:00:00', 'screening_status' => 'clear'])->save();

        $this->assertSame(['بعد منتصف الليل'], $this->labWaiting());

        \App\Models\WaitingScreenSetting::current()->update(['lab_scope' => 'all']);
        $this->assertSame(['الأسبوع الماضي', 'قبل منتصف الليل', 'بعد منتصف الليل'], $this->labWaiting());
    }

    public function test_lab_scope_is_saved_from_web_and_app(): void
    {
        $admin = User::factory()->create(['role' => 'super_admin']);

        $this->withoutExceptionHandling();
        $this->actingAs($admin)->put('/waiting-screen-settings', [
            'patients_per_page' => 8, 'rotation_seconds' => 12, 'lab_scope' => 'all',
        ])->assertSessionHasNoErrors()->assertRedirect();
        $this->withExceptionHandling();
        $this->assertSame('all', \App\Models\WaitingScreenSetting::current()->lab_scope);

        Sanctum::actingAs($admin);
        $this->putJson('/api/v1/waiting-screen-settings', [
            'patients_per_page' => 8, 'rotation_seconds' => 12, 'lab_scope' => 'today',
        ])->assertOk()->assertJsonPath('data.settings.lab_scope', 'today');

        $this->putJson('/api/v1/waiting-screen-settings', [
            'patients_per_page' => 8, 'rotation_seconds' => 12, 'lab_scope' => 'week',
        ])->assertStatus(422);

        // Older app builds without the field keep the current choice.
        $this->putJson('/api/v1/waiting-screen-settings', ['patients_per_page' => 8, 'rotation_seconds' => 12])
            ->assertOk()->assertJsonPath('data.settings.lab_scope', 'today');
    }
}
