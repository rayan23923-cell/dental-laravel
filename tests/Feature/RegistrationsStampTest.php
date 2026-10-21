<?php

namespace Tests\Feature;

use App\Models\PatientRegistration;
use App\Models\Payment;
use App\Models\User;
use App\Support\RolePresets;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * The registrations fingerprint the ticket desk and lab lists poll to
 * update by themselves (2026-10-19).
 */
class RegistrationsStampTest extends TestCase
{
    use RefreshDatabase;

    private function registration(string $name): PatientRegistration
    {
        $id = DB::table('patients_simple')->insertGetId([
            'name' => $name, 'phone' => '0770', 'screening_status' => 'pending', 'created_at' => now(),
        ]);

        return PatientRegistration::findOrFail($id);
    }

    private function deskUser(string $role): User
    {
        $user = User::factory()->create(['role' => $role]);
        RolePresets::apply($user);

        return $user;
    }

    public function test_the_stamp_changes_when_a_patient_is_registered_screened_or_paid(): void
    {
        $this->actingAs($this->deskUser('reception'));
        $stamp = fn () => $this->getJson(route('patient-registrations.stamp'))->assertOk()->json('stamp');

        $empty = $stamp();
        $this->assertSame($empty, $stamp());

        $ali = $this->registration('Ali');
        $registered = $stamp();
        $this->assertNotSame($empty, $registered);

        Payment::create(['patient_registration_id' => $ali->id, 'amount' => 10000, 'paid_at' => now(), 'type' => 'lab']);
        $paid = $stamp();
        $this->assertNotSame($registered, $paid);

        DB::table('patients_simple')->where('id', $ali->id)->update(['screening_status' => 'clear', 'screening_checked_at' => now()]);
        $screened = $stamp();
        $this->assertNotSame($paid, $screened);
        $paid = $screened;

        $ali->delete();
        $this->assertNotSame($paid, $stamp());
    }

    public function test_the_stamp_changes_when_a_service_its_price_or_the_lab_fee_changes(): void
    {
        $this->actingAs($this->deskUser('reception'));
        $stamp = fn () => $this->getJson(route('patient-registrations.stamp'))->assertOk()->json('stamp');

        $before = $stamp();
        $service = \App\Models\Service::create(['name' => 'حشوة جذر', 'price' => 16000]);
        $added = $stamp();
        $this->assertNotSame($before, $added);

        $service->update(['price' => 18000]);
        $priced = $stamp();
        $this->assertNotSame($added, $priced);

        \App\Models\ClinicSetting::current()->update(['lab_fee' => 7000]);
        $this->assertNotSame($priced, $stamp());
    }

    public function test_the_lab_and_the_app_can_read_it_but_others_cannot(): void
    {
        $this->actingAs($this->deskUser('lab'))->getJson(route('patient-registrations.stamp'))->assertOk();

        Sanctum::actingAs($this->deskUser('lab'));
        $this->getJson('/api/v1/patient-registrations-stamp')->assertOk()->assertJsonStructure(['stamp']);

        Sanctum::actingAs(User::factory()->create(['role' => 'doctor']));
        $this->getJson('/api/v1/patient-registrations-stamp')->assertForbidden();
    }
}
