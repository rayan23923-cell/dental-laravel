<?php

namespace Tests\Feature;

use App\Models\ClinicSetting;
use App\Models\PatientRegistration;
use App\Models\Payment;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * The app's payments and lab screens get what the web pages show
 * (2026-10-17): the income overview, archived patients, no hand edits,
 * and who recorded a lab result and when.
 */
class ApiPaymentsAndLabParityTest extends TestCase
{
    use RefreshDatabase;

    private function admin(): User
    {
        return User::factory()->create(['role' => 'super_admin', 'full_name' => 'Lab Hana']);
    }

    private function registration(string $name, string $phone = '0770'): PatientRegistration
    {
        $id = DB::table('patients_simple')->insertGetId([
            'name' => $name, 'phone' => $phone, 'screening_status' => 'pending', 'created_at' => now(),
        ]);

        return PatientRegistration::findOrFail($id);
    }

    public function test_stats_mirror_the_web_overview_and_follow_the_filters(): void
    {
        $ali = $this->registration('Ali');
        Payment::create(['patient_registration_id' => $ali->id, 'amount' => 25000, 'paid_at' => now(), 'type' => 'service']);
        Payment::create(['patient_registration_id' => $ali->id, 'amount' => 10000, 'paid_at' => now(), 'type' => 'lab']);
        Payment::create(['patient_registration_id' => $ali->id, 'amount' => 5000, 'paid_at' => now()->subYears(2), 'type' => 'service']);
        Sanctum::actingAs($this->admin());

        $this->getJson('/api/v1/payments/stats')->assertOk()
            ->assertJsonPath('data.periods.today.total', 35000)
            ->assertJsonPath('data.periods.today.count', 2)
            ->assertJsonPath('data.periods.year.total', 35000)
            ->assertJsonPath('data.filtered_total', 40000)
            ->assertJsonPath('data.by_source.0.source', 'registration')
            ->assertJsonPath('data.by_source.0.total', 30000)
            ->assertJsonPath('data.by_source.1.total', 10000)
            ->assertJsonPath('data.currency', ClinicSetting::current()->clinic_currency)
            ->assertJsonCount(30, 'data.daily')
            ->assertJsonCount(12, 'data.monthly');

        // The total follows the list's filters; the periods don't.
        $this->getJson('/api/v1/payments/stats?source=lab')->assertOk()
            ->assertJsonPath('data.filtered_total', 10000)
            ->assertJsonPath('data.periods.today.total', 35000);

        $this->getJson('/api/v1/payments?source=lab')->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.type', 'lab');
    }

    public function test_archived_patients_are_marked_and_payments_cannot_be_edited(): void
    {
        $ali = $this->registration('Ali');
        $payment = Payment::create(['patient_registration_id' => $ali->id, 'amount' => 25000, 'paid_at' => now(), 'type' => 'service']);
        $ali->delete();
        Sanctum::actingAs($this->admin());

        $this->getJson('/api/v1/payments')->assertOk()
            ->assertJsonPath('data.0.patient_registration.name', 'Ali')
            ->assertJsonPath('data.0.patient_registration.deleted_at', fn ($v) => $v !== null);

        $this->putJson("/api/v1/payments/{$payment->id}", ['amount' => 1])->assertStatus(405);
        $this->assertSame('25000.00', $payment->fresh()->amount);

        $this->deleteJson("/api/v1/payments/{$payment->id}")->assertNoContent();
        $this->assertSame(0, Payment::count());
    }

    public function test_screening_state_names_who_checked_and_the_reused_test(): void
    {
        ClinicSetting::current()->update(['lab_validity_days' => 90]);
        $earlier = $this->registration('Ali', '07701112233');
        $admin = $this->admin();
        Sanctum::actingAs($admin);

        $this->postJson("/api/v1/patient-registrations/{$earlier->id}/screening", ['screening_status' => 'clear'])->assertOk()
            ->assertJsonPath('data.registration.screening_checked_by.full_name', 'Lab Hana')
            ->assertJsonPath('data.registration.screening_checked_at', fn ($v) => $v !== null)
            ->assertJsonPath('data.registration.screening_reused_from_checked_at', null);

        $again = $this->registration('Ali', '07701112233');
        $this->postJson("/api/v1/patient-registrations/{$again->id}/screening/reuse")->assertOk()
            ->assertJsonPath('data.registration.screening_reused_from', $earlier->id)
            ->assertJsonPath('data.registration.screening_reused_from_checked_at', fn ($v) => $v !== null)
            ->assertJsonPath('data.registration.screening_checked_by.full_name', 'Lab Hana');

        $this->getJson("/api/v1/patient-registrations/{$again->id}/status")->assertOk()
            ->assertJsonPath('data.registration.screening_checked_by.full_name', 'Lab Hana');
    }
}
