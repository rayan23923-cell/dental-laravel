<?php

namespace Tests\Feature;

use App\Models\CompleteDentureRecord;
use App\Models\Doctor;
use App\Models\ProsthodonticsRecord;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/** Grades take numbers only; Arabic digits and an old "9/10" are normalized. */
class CaseSheetGradesTest extends TestCase
{
    use RefreshDatabase;

    private function doctor(): Doctor
    {
        DB::statement('SET FOREIGN_KEY_CHECKS=0');
        $doctor = Doctor::create([
            'name' => 'د. علي', 'username' => 'ali', 'password' => 'secret', 'email' => 'ali@example.com',
            'education_type_id' => 1, 'stage_id' => 1,
        ]);
        DB::statement('SET FOREIGN_KEY_CHECKS=1');

        return $doctor;
    }

    public function test_supervisor_web_grades_keep_numbers_only(): void
    {
        $doctor = $this->doctor();
        $record = ProsthodonticsRecord::create(['doctor_id' => $doctor->id, 'patient_name' => 'مريض']);
        $this->actingAs(User::factory()->create(['role' => 'super_admin']));

        $this->put("/prosthodontics-records/{$record->id}", [
            'doctor_id' => $doctor->id, 'patient_name' => 'مريض',
            'stage_preliminary_grade' => '٩/10', 'diagnosis_grade' => '٧٫٥',
        ])->assertSessionHasNoErrors()->assertRedirect();

        $record->refresh();
        $this->assertSame('9', (string) $record->stage_preliminary_grade);
        $this->assertSame('7.5', (string) $record->diagnosis_grade);

        $this->put("/prosthodontics-records/{$record->id}", [
            'doctor_id' => $doctor->id, 'patient_name' => 'مريض',
            'stage_preliminary_grade' => 'ممتاز',
        ])->assertSessionHasErrors('stage_preliminary_grade');
    }

    public function test_supervisor_app_grades_keep_numbers_only(): void
    {
        $doctor = $this->doctor();
        $record = CompleteDentureRecord::create(['doctor_id' => $doctor->id, 'patient_name' => 'مريض']);
        Sanctum::actingAs(User::factory()->create(['role' => 'super_admin']));

        $this->putJson("/api/v1/complete-denture-records/{$record->id}", ['stage_trial_grade' => '٨'])->assertOk();
        $this->assertSame('8', (string) $record->refresh()->stage_trial_grade);

        $this->putJson("/api/v1/complete-denture-records/{$record->id}", ['stage_trial_grade' => 'جيد'])
            ->assertJsonValidationErrors('stage_trial_grade');
    }
}
