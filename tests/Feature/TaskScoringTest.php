<?php

namespace Tests\Feature;

use App\Models\Department;
use App\Models\Doctor;
use App\Models\EducationType;
use App\Models\Group;
use App\Models\Stage;
use App\Models\Task;
use App\Models\TaskInstance;
use App\Models\User;
use App\Services\TaskProgressGroupSummary;
use App\Support\TaskScoring;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Points-based requirements from a case-sheet type's table (2026-10-14,
 * by request): preventive dentistry is passed at 30% of the weighted total.
 */
class TaskScoringTest extends TestCase
{
    use RefreshDatabase;

    public function test_the_prevention_table_creates_tasks_and_scores_a_doctor(): void
    {
        EducationType::create(['id' => 1, 'name' => 'صباحي']);
        Stage::create(['id' => 1, 'name' => 'الخامسة', 'education_type_id' => 1]);
        $department = Department::create(['name' => 'الوقائي', 'stage_id' => 1, 'education_type_id' => 1]);
        $sheet = DB::table('case_sheet_types')->where('type_code', 'prevention')->value('id')
            ?? DB::table('case_sheet_types')->insertGetId(['type_code' => 'prevention', 'name_ar' => 'الوقاية', 'name_en' => 'Prevention', 'is_active' => 1]);
        $this->actingAs(User::factory()->create(['role' => 'super_admin']));

        $rows = TaskScoring::templates()['prevention']['rows'];
        $rows[4]['enabled'] = false; // "Finished case + report" switched off
        $this->post('/tasks', [
            'department_id' => $department->id, 'case_sheet_type_id' => $sheet, 'stage_id' => 1,
            'notes' => 'متطلبات', 'grade' => 10, 'rows' => $rows, 'pass_percent' => 30,
        ])->assertSessionHasNoErrors();

        $this->assertSame(4, Task::count());
        $this->assertEquals(30, $department->fresh()->pass_percent);
        $secondary = Task::where('title', 'Secondary prevention')->firstOrFail();
        $this->assertSame(200.0, (float) $secondary->scoring['min_points']);

        $doctor = Doctor::create([
            'name' => 'د. سارة', 'username' => 'sara', 'password' => 'secret', 'email' => 's@example.com',
            'education_type_id' => 1, 'stage_id' => 1,
        ]);
        $instance = TaskInstance::create(['task_id' => $secondary->id, 'doctor_id' => $doctor->id, 'status' => 'assigned']);

        // Class II (15) with GIC (×2/3) within a finished case (×1.5) = 15,
        // plus two extractions (5 × 2) = 10 → 25 points.
        $this->put(route('task-progress.complete', $instance), [
            'work_items' => [
                ['option' => 1, 'qty' => 1, 'modifiers' => [0, 2]],
                ['option' => 4, 'qty' => 2],
            ],
        ])->assertSessionHasNoErrors();
        $this->assertEqualsWithDelta(25, $instance->fresh()->points, 0.05);

        // An option the task doesn't have is refused.
        $other = TaskInstance::create(['task_id' => $secondary->id, 'doctor_id' => $doctor->id, 'status' => 'assigned']);
        $this->put(route('task-progress.complete', $other), ['work_items' => [['option' => 9]]])
            ->assertSessionHasErrors('work_items.0.option');

        // 8/8 prophylaxis cases.
        $prophylaxis = Task::where('title', 'Prophylaxis with fluoride')->firstOrFail();
        foreach (range(1, 8) as $i) {
            TaskInstance::create(['task_id' => $prophylaxis->id, 'doctor_id' => $doctor->id, 'status' => 'completed']);
        }

        $group = Group::create(['name' => 'أ', 'stage_id' => 1]);
        $group->doctors()->attach($doctor->id);
        $summary = TaskProgressGroupSummary::build($group, User::first());
        $score = $summary['departments'][0]['doctors'][0]['score'];

        // 5% (prophylaxis) + 25/200 × 75% = 9.375% of the 95% weighed here.
        $this->assertEqualsWithDelta(round((5 + 25 / 200 * 75) / 95 * 100, 1), $score['percent'], 0.05);
        $this->assertFalse($score['passed']);
        $this->assertEquals(30, $score['pass_percent']);
    }

    public function test_each_table_row_can_use_its_own_case_sheet(): void
    {
        EducationType::create(['id' => 1, 'name' => 'صباحي']);
        Stage::create(['id' => 1, 'name' => 'الرابعة', 'education_type_id' => 1]);
        $department = Department::create(['name' => 'صناعة الأسنان', 'stage_id' => 1, 'education_type_id' => 1]);
        foreach (['prosthodontics', 'partial_denture', 'complete_denture'] as $code) {
            DB::table('case_sheet_types')->insertOrIgnore(['type_code' => $code, 'name_ar' => $code, 'name_en' => $code, 'is_active' => 1]);
        }
        $ids = DB::table('case_sheet_types')->pluck('id', 'type_code');
        $this->actingAs(User::factory()->create(['role' => 'super_admin']));

        $template = TaskScoring::templatesByTypeId()[$ids['prosthodontics']];
        $this->assertSame($ids['partial_denture'], $template['rows'][0]['case_sheet_type_id']);

        $rows = array_map(fn ($r) => ['enabled' => str_contains($r['title'], 'الرابع')] + $r, $template['rows']);
        $this->post('/tasks', [
            'department_id' => $department->id, 'case_sheet_type_id' => $ids['prosthodontics'], 'stage_id' => 1,
            'notes' => 'متطلبات', 'grade' => 10, 'rows' => $rows,
        ])->assertSessionHasNoErrors();

        $this->assertSame(3, Task::count());
        $this->assertEquals(
            [$ids['partial_denture'], $ids['partial_denture'], $ids['prosthodontics']],
            Task::orderBy('id')->pluck('case_sheet_type_id')->map(fn ($id) => (int) $id)->all()
        );
        // The case's points are its step grades on the case sheet, each up to its max (10).
        $task = Task::orderBy('id')->first();
        $this->assertCount(10, $task->scoring['steps']);
        $doctor = Doctor::create([
            'name' => 'د. علي', 'username' => 'ali', 'password' => 'secret', 'email' => 'a@example.com',
            'education_type_id' => 1, 'stage_id' => 1,
        ]);
        $instance = TaskInstance::create(['task_id' => $task->id, 'doctor_id' => $doctor->id, 'status' => 'assigned']);
        \App\Models\ProsthodonticsRecord::create([
            'doctor_id' => $doctor->id, 'task_instances_id' => $instance->id,
            'diagnosis_grade' => '9', 'stage_preliminary_grade' => '8', 'stage_trial_grade' => '15', 'stage_final_grade' => 'جيد',
        ]);
        $this->put(route('task-progress.complete', $instance), [])->assertSessionHasNoErrors();
        $this->assertEqualsWithDelta(27, $instance->fresh()->points, 0.01);
    }
}
