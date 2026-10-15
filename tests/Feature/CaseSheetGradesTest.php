<?php

namespace Tests\Feature;

use App\Models\CompleteDentureRecord;
use App\Models\Doctor;
use App\Models\ProsthodonticsRecord;
use App\Models\Task;
use App\Models\TaskInstance;
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

    public function test_a_stage_field_saves_on_its_own_and_stays_within_its_step_max(): void
    {
        $doctor = $this->doctor();
        DB::statement('SET FOREIGN_KEY_CHECKS=0');
        $task = Task::create([
            'department_id' => 1, 'case_sheet_type_id' => 1, 'stage_id' => 1,
            'title' => 'طقم جزئي', 'required_per_doctor' => 1, 'required_count' => 1,
            'scoring' => ['measure' => 'both', 'steps' => [['key' => 'trial', 'label' => 'Trial denture', 'max' => 5, 'enabled' => true]]],
        ]);
        DB::statement('SET FOREIGN_KEY_CHECKS=1');
        $instance = TaskInstance::create(['task_id' => $task->id, 'doctor_id' => $doctor->id, 'status' => 'assigned']);
        $record = ProsthodonticsRecord::create(['doctor_id' => $doctor->id, 'patient_name' => 'مريض', 'task_instances_id' => $instance->id]);
        $admin = User::factory()->create(['role' => 'super_admin']);

        // The page shows each step's max: the task's 5 for "trial", 10 elsewhere.
        $this->actingAs($admin)->get("/prosthodontics-records/{$record->id}/edit")
            ->assertInertia(fn ($page) => $page->where('stageMaxes.stage_trial_grade', 5)->where('stageMaxes.stage_final_grade', 10));

        $this->patchJson("/prosthodontics-records/{$record->id}/stage-field", ['stage_trial_grade' => '٧'])
            ->assertOk()->assertJsonPath('value', '5');
        $this->patchJson("/prosthodontics-records/{$record->id}/stage-field", ['stage_trial_date' => '2026-10-15'])->assertOk();
        $record->refresh();
        $this->assertSame('5', (string) $record->stage_trial_grade);
        $this->assertStringStartsWith('2026-10-15', (string) $record->stage_trial_date);

        // Only one stage column per call, and never a doctor's own field.
        $this->patchJson("/prosthodontics-records/{$record->id}/stage-field", ['patient_name' => 'آخر'])->assertStatus(403);
        $this->patchJson("/prosthodontics-records/{$record->id}/stage-field", ['stage_final_grade' => '1', 'stage_final_date' => '2026-10-15'])->assertJsonValidationErrors('field');

        // A doctor can't grade their own sheet.
        $this->actingAs($doctor, 'doctor')
            ->patchJson("/prosthodontics-records/{$record->id}/stage-field", ['stage_final_grade' => '9'])->assertStatus(403);
    }
}
