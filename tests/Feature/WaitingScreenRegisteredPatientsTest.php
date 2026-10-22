<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\WaitingScreenPairing;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Today's registered patients on the waiting screen (2026-10-22).
 */
class WaitingScreenRegisteredPatientsTest extends TestCase
{
    use RefreshDatabase;

    private function register(string $name, $createdAt, $deletedAt = null): int
    {
        return DB::table('patients_simple')->insertGetId([
            'name' => $name, 'phone' => '0770', 'screening_status' => 'pending',
            'created_at' => $createdAt, 'deleted_at' => $deletedAt,
        ]);
    }

    public function test_the_screen_lists_patients_registered_today(): void
    {
        $this->register('مريض اليوم الأول', now()->startOfDay()->addHours(8));
        $this->register('مريض اليوم الثاني', now()->startOfDay()->addHours(9));
        $this->register('مريض الأمس', now()->subDay());
        $this->register('مريض مؤرشف', now(), now());
        $booked = $this->register('مريض بموعد', now());
        Appointment::create([
            'full_name' => 'مريض بموعد', 'patient_registration_id' => $booked,
            'appointment_date' => now(),
        ]);

        $pairing = WaitingScreenPairing::createNew();
        $pairing->update(['confirmed_at' => now()]);

        $names = collect($this->getJson('/api/v1/waiting-screen?token='.$pairing->token)
            ->assertOk()
            ->assertJsonPath('paired', true)
            ->json('appointments'))->pluck('patient_name')->all();

        $this->assertSame(['مريض بموعد', 'مريض اليوم الأول', 'مريض اليوم الثاني'], $names);
    }
}
