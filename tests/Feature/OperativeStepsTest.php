<?php

namespace Tests\Feature;

use App\Models\CaseSheetType;
use App\Models\Doctor;
use App\Models\Task;
use App\Models\TaskInstance;
use App\Models\User;
use App\Support\TaskScoring;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Operative tasks get the sheet's sections as graded steps, and a case
 * can get steps of its own with their names and grades (2026-10-19, by
 * request).
 */
class OperativeStepsTest extends TestCase
{
    use RefreshDatabase;

    private function task(int $typeId, ?array $scoring = null): Task
    {
        DB::statement('SET FOREIGN_KEY_CHECKS=0');
        $task = Task::create([
            'department_id' => 1, 'case_sheet_type_id' => $typeId, 'stage_id' => 1,
            'title' => 'Cl II (composite)', 'required_per_doctor' => 1, 'required_count' => 1,
            'scoring' => $scoring,
        ]);
        DB::statement('SET FOREIGN_KEY_CHECKS=1');

        return $task;
    }

    private function caseOf(Task $task): TaskInstance
    {
        DB::statement('SET FOREIGN_KEY_CHECKS=0');
        $doctor = Doctor::create([
            'name' => 'د. مريم', 'username' => 'maryam', 'password' => 'secret', 'email' => 'maryam@example.com',
            'education_type_id' => 1, 'stage_id' => 1,
        ]);
        DB::statement('SET FOREIGN_KEY_CHECKS=1');

        return TaskInstance::create(['task_id' => $task->id, 'doctor_id' => $doctor->id, 'status' => 'assigned']);
    }

    public function test_operative_tasks_get_their_steps_and_a_case_can_add_its_own(): void
    {
        $operative = CaseSheetType::firstOrCreate(['type_code' => 'operative'], ['name_ar' => 'المخطط السني', 'name_en' => 'Operative']);
        $task = $this->task($operative->id);
        $this->assertSame(['Chief complaint and history', 'Clinical examination', 'Odontogram'], array_column($task->fresh()->scoring['steps'], 'label'));

        $instance = $this->caseOf($task);
        Sanctum::actingAs(User::factory()->create(['role' => 'super_admin', 'full_name' => 'المشرف']));
        $base = "/api/v1/case-sheets/instances/{$instance->id}";

        $this->postJson("$base/extra-steps", ['label' => '', 'max' => 5])->assertJsonValidationErrors('label');
        $this->postJson("$base/extra-steps", ['label' => 'Rubber dam', 'max' => 5])->assertOk()
            ->assertJsonPath('steps.3.key', 'x:1')->assertJsonPath('steps.3.label', 'Rubber dam')
            ->assertJsonPath('steps.3.max', 5)->assertJsonPath('steps.3.extra', true);

        foreach (['s:custom_cc_history' => 9, 's:custom_exam' => 8, 's:custom_odontogram' => 7] as $step => $grade) {
            $this->postJson("$base/steps", ['step' => $step, 'grade' => $grade])->assertOk();
        }
        $this->postJson("$base/steps", ['step' => 'x:1', 'grade' => 6])->assertJsonValidationErrors('grade');
        $this->postJson("$base/steps", ['step' => 'x:1', 'grade' => 4])->assertOk()
            ->assertJsonPath('points', 28)->assertJsonPath('steps.3.signed', true);
        $this->assertEqualsWithDelta(28, $instance->fresh()->points, 0.01);

        // A signed step stays; once taken back it can be removed, and its grade goes with it.
        $this->deleteJson("$base/extra-steps", ['step' => 'x:1'])->assertJsonValidationErrors('step');
        $this->deleteJson("$base/steps", ['step' => 'x:1'])->assertOk();
        $this->deleteJson("$base/extra-steps", ['step' => 'x:1'])->assertOk()->assertJsonCount(3, 'steps');
        $this->assertEqualsWithDelta(24, $instance->fresh()->points, 0.01);

        // The doctor cannot add steps.
        Sanctum::actingAs($instance->doctor);
        $this->postJson("$base/extra-steps", ['label' => 'Polish', 'max' => 5])->assertForbidden();
    }

    public function test_a_task_without_steps_counts_an_added_step_next_to_its_work(): void
    {
        $other = CaseSheetType::firstOrCreate(['type_code' => 'orthodontics'], ['name_ar' => 'التقويم', 'name_en' => 'Orthodontics']);
        $task = $this->task($other->id, TaskScoring::normalize(['measure' => 'count']));
        $instance = $this->caseOf($task);
        Sanctum::actingAs(User::factory()->create(['role' => 'super_admin', 'full_name' => 'المشرف']));
        $base = "/api/v1/case-sheets/instances/{$instance->id}";

        $this->postJson("$base/extra-steps", ['label' => 'Bracket bonding', 'max' => 10])->assertOk()->assertJsonPath('steps.0.key', 'x:1');
        $this->postJson("$base/steps", ['step' => 'x:1', 'grade' => 7])->assertOk()->assertJsonPath('points', 7);
        $this->assertSame('Bracket bonding', $instance->fresh()->work_items[0]['option']);
    }
}
