<?php

namespace Tests\Feature;

use App\Models\Doctor;
use App\Models\Task;
use App\Models\TaskInstance;
use App\Models\User;
use App\Services\PermissionManager;
use App\Support\TaskScoring;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * The app's case sheet shows and saves its task's points (2026-10-17)
 * through the same TaskWorkController as the web, under Sanctum.
 */
class TaskWorkApiTest extends TestCase
{
    use RefreshDatabase;

    private function doctor(string $username): Doctor
    {
        return Doctor::create([
            'name' => "د. $username", 'username' => $username, 'password' => 'secret', 'email' => "$username@example.com",
            'education_type_id' => 1, 'stage_id' => 1,
        ]);
    }

    private function task(array $scoring): Task
    {
        DB::statement('SET FOREIGN_KEY_CHECKS=0');
        $task = Task::create([
            'department_id' => 1, 'case_sheet_type_id' => 1, 'stage_id' => 1,
            'title' => 'Secondary prevention', 'required_per_doctor' => 2, 'required_count' => 2,
            'scoring' => TaskScoring::normalize($scoring),
        ]);
        DB::statement('SET FOREIGN_KEY_CHECKS=1');

        return $task;
    }

    public function test_staff_save_the_work_and_the_doctor_reads_their_own_case_only(): void
    {
        DB::statement('SET FOREIGN_KEY_CHECKS=0');
        $doctor = $this->doctor('maryam');
        $other = $this->doctor('ali');
        DB::statement('SET FOREIGN_KEY_CHECKS=1');
        $task = $this->task([
            'measure' => 'points', 'min_points' => 50,
            'options' => [['label' => 'Class I', 'points' => 10], ['label' => 'Class II', 'points' => 15]],
            'modifiers' => [['label' => 'GIC', 'factor' => 0.5]],
            'checklist' => [['label' => 'Photos', 'scored' => true, 'max' => 5]],
        ]);
        $instance = TaskInstance::create(['task_id' => $task->id, 'doctor_id' => $doctor->id, 'status' => 'assigned']);

        Sanctum::actingAs(User::factory()->create(['role' => 'super_admin']));
        $this->getJson("/api/v1/case-sheets/instances/{$instance->id}/work")
            ->assertOk()
            ->assertJsonPath('can_edit', true)
            ->assertJsonPath('from_sheet', false)
            ->assertJsonPath('scoring.options.1.label', 'Class II');

        // 2 × Class II at ×0.5 plus the photos part graded 4 of 5.
        $this->putJson("/api/v1/case-sheets/instances/{$instance->id}/work", ['work_items' => [
            ['option' => 1, 'qty' => 2, 'modifiers' => [0]],
            ['check' => 0, 'grade' => 4],
        ]])->assertOk()->assertJsonPath('points', 19);
        $this->assertEqualsWithDelta(19, $instance->fresh()->points, 0.01);
        $this->assertSame('assigned', $instance->fresh()->status);

        // A kind of work the task does not have is refused.
        $this->putJson("/api/v1/case-sheets/instances/{$instance->id}/work", ['work_items' => [['option' => 7]]])
            ->assertJsonValidationErrors('work_items.0.option');

        // The doctor sees the points but cannot change them, and never sees another doctor's case.
        Sanctum::actingAs($doctor);
        $this->getJson("/api/v1/case-sheets/instances/{$instance->id}/work")
            ->assertOk()->assertJsonPath('can_edit', false)->assertJsonPath('points', 19);
        $this->putJson("/api/v1/case-sheets/instances/{$instance->id}/work", ['work_items' => []])->assertForbidden();
        Sanctum::actingAs($other);
        $this->getJson("/api/v1/case-sheets/instances/{$instance->id}/work")->assertForbidden();
    }

    public function test_staff_without_the_finish_permission_cannot_save(): void
    {
        DB::statement('SET FOREIGN_KEY_CHECKS=0');
        $doctor = $this->doctor('sara');
        DB::statement('SET FOREIGN_KEY_CHECKS=1');
        $task = $this->task(['measure' => 'count', 'checklist' => [['label' => 'Session 1'], ['label' => 'Session 2']]]);
        $instance = TaskInstance::create(['task_id' => $task->id, 'doctor_id' => $doctor->id, 'status' => 'assigned']);

        // Reading needs the "open case sheet" grant (2026-10-18), saving finish.
        $editor = User::factory()->create(['role' => 'editor']);
        Sanctum::actingAs($editor);
        $this->getJson("/api/v1/case-sheets/instances/{$instance->id}/work")->assertForbidden();
        PermissionManager::syncGrants($editor, ['task_progress.open_case_sheet']);
        $this->getJson("/api/v1/case-sheets/instances/{$instance->id}/work")->assertOk()->assertJsonPath('can_edit', false);
        $this->putJson("/api/v1/case-sheets/instances/{$instance->id}/work", ['work_items' => [['check' => 0]]])->assertForbidden();
    }

    public function test_hand_added_steps_are_graded_from_the_app(): void
    {
        DB::statement('SET FOREIGN_KEY_CHECKS=0');
        $doctor = $this->doctor('huda');
        DB::statement('SET FOREIGN_KEY_CHECKS=1');
        $task = $this->task(['measure' => 'both', 'steps' => [
            ['key' => 'custom_1', 'label' => 'Shade selection', 'max' => 5, 'enabled' => true, 'custom' => true],
            ['key' => 'custom_2', 'label' => 'Polishing', 'max' => 10, 'enabled' => true, 'custom' => true],
        ]]);
        $instance = TaskInstance::create(['task_id' => $task->id, 'doctor_id' => $doctor->id, 'status' => 'assigned']);

        Sanctum::actingAs(User::factory()->create(['role' => 'super_admin']));
        $this->getJson("/api/v1/case-sheets/instances/{$instance->id}/work")->assertOk()->assertJsonPath('from_sheet', true);
        $this->putJson("/api/v1/case-sheets/instances/{$instance->id}/work", ['step_grades' => ['custom_1' => 9, 'custom_2' => 7.5]])
            ->assertOk()->assertJsonPath('points', 12.5);
        $this->assertEqualsWithDelta(12.5, $instance->fresh()->points, 0.01);
    }
}
