<?php

namespace Tests\Feature;

use App\Models\CaseSheetType;
use App\Models\Doctor;
use App\Models\ProsthodonticsRecord;
use App\Models\Task;
use App\Models\TaskInstance;
use App\Models\User;
use App\Support\TaskScoring;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * A case's steps signed one after another with their grades (2026-10-18,
 * by request), from the start dialog and afterwards.
 */
class TaskStepsSignoffTest extends TestCase
{
    use RefreshDatabase;

    private Doctor $doctor;

    protected function setUp(): void
    {
        parent::setUp();
        DB::statement('SET FOREIGN_KEY_CHECKS=0');
        $this->doctor = Doctor::create([
            'name' => 'د. مريم', 'username' => 'maryam', 'password' => 'secret', 'email' => 'maryam@example.com',
            'education_type_id' => 1, 'stage_id' => 1,
        ]);
        DB::statement('SET FOREIGN_KEY_CHECKS=1');
    }

    private function task(array $scoring, ?int $typeId = 1): Task
    {
        DB::statement('SET FOREIGN_KEY_CHECKS=0');
        $task = Task::create([
            'department_id' => 1, 'case_sheet_type_id' => $typeId, 'stage_id' => 1,
            'title' => 'طقم جزئي', 'required_per_doctor' => 2, 'required_count' => 2,
            'scoring' => TaskScoring::normalize($scoring),
        ]);
        DB::statement('SET FOREIGN_KEY_CHECKS=1');

        return $task;
    }

    public function test_steps_are_signed_in_order_with_their_grades(): void
    {
        $task = $this->task([
            'measure' => 'both',
            'steps' => [
                ['key' => 'custom_1', 'label' => 'صناعة الأسنان', 'max' => 10, 'enabled' => true, 'custom' => true],
                ['key' => 'custom_2', 'label' => 'التسليم', 'max' => 5, 'enabled' => true, 'custom' => true],
            ],
            'checklist' => [['label' => 'Photos', 'scored' => true, 'max' => 4], ['label' => 'Models']],
        ]);
        $instance = TaskInstance::create(['task_id' => $task->id, 'doctor_id' => $this->doctor->id, 'status' => 'assigned']);
        Sanctum::actingAs(User::factory()->create(['role' => 'super_admin', 'full_name' => 'المشرف']));
        $url = "/api/v1/case-sheets/instances/{$instance->id}/steps";

        $this->getJson("/api/v1/case-sheets/instances/{$instance->id}/work")
            ->assertOk()->assertJsonPath('can_sign', true)
            ->assertJsonPath('steps.0.label', 'صناعة الأسنان')->assertJsonPath('steps.2.key', 'c:0')->assertJsonPath('steps.3.max', null);

        // Not out of order, not without a grade, not above the max.
        $this->postJson($url, ['step' => 's:custom_2', 'grade' => 4])->assertJsonValidationErrors('step');
        $this->postJson($url, ['step' => 's:custom_1'])->assertJsonValidationErrors('grade');
        $this->postJson($url, ['step' => 's:custom_1', 'grade' => 11])->assertJsonValidationErrors('grade');

        $this->postJson($url, ['step' => 's:custom_1', 'grade' => 9])->assertOk()
            ->assertJsonPath('steps.0.signed', true)->assertJsonPath('steps.0.signed_by', 'المشرف')->assertJsonPath('points', 9);
        $this->postJson($url, ['step' => 's:custom_2', 'grade' => 5])->assertOk()->assertJsonPath('points', 14);
        $this->postJson($url, ['step' => 'c:0', 'grade' => 3])->assertOk();
        $this->postJson($url, ['step' => 'c:1'])->assertOk()->assertJsonPath('steps.3.signed', true);

        // The checklist parts are ticked for the complete dialog, with every grade in the points.
        $fresh = $instance->fresh();
        $this->assertEqualsWithDelta(17, $fresh->points, 0.01);
        $this->assertSame(['Photos', 'Models'], array_column(array_filter($fresh->work_items, fn ($w) => ! empty($w['check'])), 'option'));

        // Only the last signed step can be taken back.
        $this->deleteJson($url, ['step' => 'c:0'])->assertJsonValidationErrors('step');
        $this->deleteJson($url, ['step' => 'c:1'])->assertOk()->assertJsonPath('steps.3.signed', false);

        // The doctor sees the steps but cannot sign them.
        Sanctum::actingAs($this->doctor);
        $this->getJson("/api/v1/case-sheets/instances/{$instance->id}/work")->assertOk()->assertJsonPath('can_sign', false);
        $this->postJson($url, ['step' => 'c:1'])->assertForbidden();
    }

    public function test_the_start_dialog_signs_the_first_steps_and_the_case_sheet_shows_them(): void
    {
        $type = CaseSheetType::create(['type_code' => 'partial_denture', 'name_ar' => 'طقم جزئي', 'name_en' => 'Partial denture']);
        $task = $this->task(['measure' => 'both', 'steps' => [
            ['key' => 'diagnosis', 'label' => 'Diagnosis', 'max' => 10, 'enabled' => true],
            ['key' => 'preliminary', 'label' => 'Preliminary impression', 'max' => 10, 'enabled' => true],
        ]], $type->id);
        $this->actingAs(User::factory()->create(['role' => 'super_admin', 'full_name' => 'المشرف']));

        $this->post(route('task-progress.start'), [
            'doctor_id' => $this->doctor->id, 'task_id' => $task->id,
            'steps' => [['step' => 's:diagnosis', 'grade' => 8]],
        ])->assertSessionHasNoErrors();

        $instance = TaskInstance::where('task_id', $task->id)->where('status', 'assigned')->firstOrFail();
        $this->assertSame(8.0, (float) $instance->step_signoffs['s:diagnosis']['grade']);
        $this->assertEqualsWithDelta(8, $instance->points, 0.01);

        // Once the sheet exists, the next step is written on it, signature included.
        $record = ProsthodonticsRecord::create(['doctor_id' => $this->doctor->id, 'patient_name' => 'مريض', 'task_instances_id' => $instance->id]);
        $this->postJson("/case-sheets/instances/{$instance->id}/steps", ['step' => 's:preliminary', 'grade' => 7])->assertOk()
            ->assertJsonPath('points', 15);
        $record->refresh();
        $this->assertSame('7', (string) (float) $record->stage_preliminary_grade);
        $this->assertStringStartsWith('المشرف — ', $record->stage_preliminary_signature);
        $this->assertNotNull($record->stage_preliminary_date);

        // A step signed on the sheet cannot be taken back from here.
        $this->deleteJson("/case-sheets/instances/{$instance->id}/steps", ['step' => 's:preliminary'])->assertJsonValidationErrors('step');
    }
}
