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

    private function labWaiting(): array
    {
        $pairing = WaitingScreenPairing::createNew();
        $pairing->update(['confirmed_at' => now()]);

        return collect($this->getJson('/api/v1/waiting-screen?token='.$pairing->token)
            ->assertOk()
            ->json('lab_waiting'))->pluck('patient_name')->all();
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

    public function test_yesterdays_printed_sheet_is_not_shown(): void
    {
        $old = $this->registration('مريض الأمس');
        $old->forceFill(['lab_sample_printed_at' => now()->subDay()])->save();

        $this->assertSame([], $this->labWaiting());
    }
}
