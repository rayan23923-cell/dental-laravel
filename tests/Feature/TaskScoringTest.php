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

    public function test_periodontics_grades_items_and_requires_every_session(): void
    {
        EducationType::create(['id' => 1, 'name' => 'صباحي']);
        Stage::create(['id' => 1, 'name' => 'الرابعة', 'education_type_id' => 1]);
        $department = Department::create(['name' => 'اللثة', 'stage_id' => 1, 'education_type_id' => 1]);
        $sheet = DB::table('case_sheet_types')->where('type_code', 'periodontal')->value('id')
            ?? DB::table('case_sheet_types')->insertGetId(['type_code' => 'periodontal', 'name_ar' => 'اللثة', 'name_en' => 'Periodontal', 'is_active' => 1]);
        $this->actingAs(User::factory()->create(['role' => 'super_admin']));

        $rows = TaskScoring::templatesByTypeId()[$sheet]['rows'];
        $this->assertSame([4, 5, 5], array_column($rows, 'stage'));
        $this->post('/tasks', [
            'department_id' => $department->id, 'case_sheet_type_id' => $sheet, 'stage_id' => 1,
            'notes' => 'متطلبات', 'grade' => 10, 'rows' => $rows,
        ])->assertSessionHasNoErrors();

        $doctor = Doctor::create([
            'name' => 'د. زينب', 'username' => 'zainab', 'password' => 'secret', 'email' => 'z@example.com',
            'education_type_id' => 1, 'stage_id' => 1,
        ]);

        // Graded: each item scores the supervisor's grade, up to its max.
        $points = Task::where('title', 'like', '%1000%')->firstOrFail();
        $this->assertTrue($points->scoring['graded']);
        $instance = TaskInstance::create(['task_id' => $points->id, 'doctor_id' => $doctor->id, 'status' => 'assigned']);
        $this->put(route('task-progress.complete', $instance), [
            'work_items' => [
                ['option' => 0, 'grade' => 8],
                ['option' => 4, 'grade' => 99], // Scaling, max 40
                ['option' => 5, 'grade' => 120],
            ],
        ])->assertSessionHasNoErrors();
        $this->assertEqualsWithDelta(168, $instance->fresh()->points, 0.01);

        // Checklist: both sessions must be ticked.
        $sessions = Task::where('title', 'like', '%جلستين%')->firstOrFail();
        $case = TaskInstance::create(['task_id' => $sessions->id, 'doctor_id' => $doctor->id, 'status' => 'assigned']);
        $this->put(route('task-progress.complete', $case), ['work_items' => [['check' => 0]]])
            ->assertSessionHasErrors('work_items');
        $this->assertSame('assigned', $case->fresh()->status);
        $this->put(route('task-progress.complete', $case), ['work_items' => [['check' => 0], ['check' => 1]]])
            ->assertSessionHasNoErrors();
        $this->assertSame('completed', $case->fresh()->status);
        $this->assertNull($case->fresh()->points);
        $this->assertCount(2, $case->fresh()->work_items);
    }

    public function test_an_operative_root_filling_opens_with_endodontics_on(): void
    {
        EducationType::create(['id' => 1, 'name' => 'صباحي']);
        Stage::create(['id' => 1, 'name' => 'الخامسة', 'education_type_id' => 1]);
        $department = Department::create(['name' => 'المعالجة', 'stage_id' => 1, 'education_type_id' => 1]);
        $sheet = DB::table('case_sheet_types')->where('type_code', 'operative')->value('id')
            ?? DB::table('case_sheet_types')->insertGetId(['type_code' => 'operative', 'name_ar' => 'المعالجة', 'name_en' => 'Operative', 'is_active' => 1]);
        $this->actingAs(User::factory()->create(['role' => 'super_admin']));

        // The fifth stage's rows only, as the form leaves them.
        $rows = array_map(fn ($r) => ['enabled' => $r['stage'] === 5] + $r, TaskScoring::templatesByTypeId()[$sheet]['rows']);
        $this->assertSame(13, array_sum(array_map(fn ($r) => $r['enabled'] && ! str_contains($r['title'], 'crown') && ! $r['scoring']['endo'] ? $r['required_count'] : 0, $rows)));
        $this->post('/tasks', [
            'department_id' => $department->id, 'case_sheet_type_id' => $sheet, 'stage_id' => 1,
            'notes' => 'متطلبات', 'grade' => 10, 'rows' => $rows,
        ])->assertSessionHasNoErrors();
        $this->assertSame(9, Task::count());

        $doctor = Doctor::create([
            'name' => 'د. حسين', 'username' => 'hussein', 'password' => 'secret', 'email' => 'h@example.com',
            'education_type_id' => 1, 'stage_id' => 1,
        ]);
        $endo = TaskInstance::create(['task_id' => Task::where('title', 'like', 'Endo%')->value('id'), 'doctor_id' => $doctor->id, 'status' => 'assigned']);
        $filling = TaskInstance::create(['task_id' => Task::where('title', 'like', 'Cl III%')->value('id'), 'doctor_id' => $doctor->id, 'status' => 'assigned']);

        $this->get(route('dental-charts.create', ['task_instances_id' => $endo->id]))
            ->assertInertia(fn ($page) => $page->where('rootFilling', true));
        $this->get(route('dental-charts.create', ['task_instances_id' => $filling->id]))
            ->assertInertia(fn ($page) => $page->where('rootFilling', false));
    }

    public function test_the_case_sheet_shows_and_saves_the_tasks_points(): void
    {
        EducationType::create(['id' => 1, 'name' => 'صباحي']);
        Stage::create(['id' => 1, 'name' => 'الرابعة', 'education_type_id' => 1]);
        $department = Department::create(['name' => 'اللثة', 'stage_id' => 1, 'education_type_id' => 1]);
        $sheet = DB::table('case_sheet_types')->where('type_code', 'periodontal')->value('id')
            ?? DB::table('case_sheet_types')->insertGetId(['type_code' => 'periodontal', 'name_ar' => 'اللثة', 'name_en' => 'Periodontal', 'is_active' => 1]);
        $admin = User::factory()->create(['role' => 'super_admin']);
        $this->actingAs($admin);
        $this->post('/tasks', [
            'department_id' => $department->id, 'case_sheet_type_id' => $sheet, 'stage_id' => 1,
            'notes' => 'متطلبات', 'grade' => 10, 'rows' => TaskScoring::templatesByTypeId()[$sheet]['rows'],
        ])->assertSessionHasNoErrors();

        $doctor = Doctor::create([
            'name' => 'د. مريم', 'username' => 'maryam', 'password' => 'secret', 'email' => 'm@example.com',
            'education_type_id' => 1, 'stage_id' => 1,
        ]);
        $graded = TaskInstance::create(['task_id' => Task::where('title', 'like', '%1000%')->value('id'), 'doctor_id' => $doctor->id, 'status' => 'assigned']);
        $sessions = TaskInstance::create(['task_id' => Task::where('title', 'like', '%جلستين%')->value('id'), 'doctor_id' => $doctor->id, 'status' => 'assigned']);

        // The supervisor grades on the case sheet; task progress sees the same points.
        $this->getJson(route('case-sheets.instance-work', $graded))->assertOk()->assertJsonPath('can_edit', true)->assertJsonPath('scoring.graded', true);
        $this->putJson(route('case-sheets.instance-work.update', $graded), ['work_items' => [['option' => 4, 'grade' => 30]]])
            ->assertOk()->assertJsonPath('points', 30);
        $this->assertEqualsWithDelta(30, $graded->fresh()->points, 0.01);

        // One session ticked so far is saved as progress, before completion.
        $this->putJson(route('case-sheets.instance-work.update', $sessions), ['work_items' => [['check' => 0]]])->assertOk();
        $this->assertCount(1, $sessions->fresh()->work_items);
        $this->assertSame('assigned', $sessions->fresh()->status);

        // The doctor sees their own case's points but cannot change them.
        auth()->logout();
        $this->actingAs($doctor, 'doctor');
        $this->getJson(route('case-sheets.instance-work', $graded))->assertOk()->assertJsonPath('can_edit', false)->assertJsonPath('points', 30);
        $this->putJson(route('case-sheets.instance-work.update', $graded), ['work_items' => [['option' => 4, 'grade' => 40]]])->assertForbidden();
    }
}
