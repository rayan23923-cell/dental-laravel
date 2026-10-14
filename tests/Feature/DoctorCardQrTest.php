<?php

namespace Tests\Feature;

use App\Models\Doctor;
use App\Models\EducationType;
use App\Models\Stage;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The doctor's ID card carries their QR, and the task-progress scanner
 * opens it as that doctor (2026-10-14, by request).
 */
class DoctorCardQrTest extends TestCase
{
    use RefreshDatabase;

    public function test_the_card_shows_a_qr_that_the_scanner_opens(): void
    {
        EducationType::create(['id' => 1, 'name' => 'الدراسات الأولية']);
        Stage::create(['id' => 1, 'name' => 'الرابعة', 'education_type_id' => 1]);
        $doctor = Doctor::create([
            'name' => 'د. علي', 'username' => 'ali', 'password' => 'secret', 'email' => 'ali@example.com',
            'education_type_id' => 1, 'stage_id' => 1,
        ]);
        $this->actingAs(User::factory()->create(['role' => 'super_admin']));

        $this->get(route('doctors.card', $doctor))->assertOk()->assertSee('data:image/png;base64,', false);

        $this->postJson(route('task-progress.scan'), ['payload' => json_encode(['type' => 'doctor', 'id' => $doctor->id])])
            ->assertOk()
            ->assertJsonPath('kind', 'doctor')
            ->assertJsonPath('doctor.name', 'د. علي')
            ->assertJsonPath('progress_url', route('doctors.progress', $doctor->id));
    }
}
