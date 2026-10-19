<?php

namespace Tests\Feature;

use App\Models\CaseSheetType;
use App\Models\Task;
use App\Support\TaskScoring;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * A task on the surgery sheet gets the sheet's sections as steps graded
 * one by one (2026-10-19, by request).
 */
class SurgeryStepsTest extends TestCase
{
    use RefreshDatabase;

    private function task(int $typeId, ?array $scoring = null): Task
    {
        DB::statement('SET FOREIGN_KEY_CHECKS=0');
        $task = Task::create([
            'department_id' => 1, 'case_sheet_type_id' => $typeId, 'stage_id' => 1,
            'title' => 'Extraction', 'required_per_doctor' => 1, 'required_count' => 1,
            'scoring' => $scoring,
        ]);
        DB::statement('SET FOREIGN_KEY_CHECKS=1');

        return $task;
    }

    public function test_choosing_the_surgery_sheet_adds_its_graded_steps(): void
    {
        $surgery = CaseSheetType::firstOrCreate(['type_code' => 'surgery'], ['name_ar' => 'العمليات الجراحية', 'name_en' => 'Surgery']);
        $operative = CaseSheetType::firstOrCreate(['type_code' => 'operative'], ['name_ar' => 'المخطط السني', 'name_en' => 'Operative']);

        $task = $this->task($surgery->id);
        $steps = $task->fresh()->scoring['steps'];
        $this->assertSame(array_values(TaskScoring::SURGERY_STEPS), array_column($steps, 'label'));
        $this->assertEquals([10], array_values(array_unique(array_column($steps, 'max'))));
        $this->assertTrue($steps[0]['custom']);

        // A pediatric extraction keeps its kinds of work and gets the steps too.
        $kinds = $this->task($surgery->id, TaskScoring::normalize(['measure' => 'both', 'min_points' => 10, 'options' => [['label' => 'Extraction', 'points' => 5]]]));
        $this->assertCount(6, $kinds->fresh()->scoring['steps']);
        $this->assertCount(1, $kinds->fresh()->scoring['options']);

        // Other sheets get none, and steps removed later are not put back.
        $this->assertSame([], $this->task($operative->id)->fresh()->scoring['steps'] ?? []);
        $task->update(['scoring' => TaskScoring::normalize(['measure' => 'count'])]);
        $this->assertSame([], $task->fresh()->scoring['steps']);

        // Moving a task to the surgery sheet adds them.
        $moved = $this->task($operative->id);
        $moved->update(['case_sheet_type_id' => $surgery->id]);
        $this->assertCount(6, $moved->fresh()->scoring['steps']);
    }
}
