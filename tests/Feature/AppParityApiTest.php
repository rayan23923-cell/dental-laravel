<?php

namespace Tests\Feature;

use App\Models\Department;
use App\Models\Doctor;
use App\Models\EducationType;
use App\Models\PreventionRecord;
use App\Models\Stage;
use App\Models\Task;
use App\Models\TaskInstance;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/** Web features ported to the app (2026-10-17): the API side of each. */
class AppParityApiTest extends TestCase
{
    use RefreshDatabase;

    private Department $department;

    private int $sheet;

    protected function setUp(): void
    {
        parent::setUp();
        EducationType::create(['id' => 1, 'name' => 'صباحي']);
        Stage::create(['id' => 1, 'name' => 'الرابعة', 'education_type_id' => 1]);
        $this->department = Department::create(['name' => 'اللثة', 'stage_id' => 1, 'education_type_id' => 1]);
        $this->sheet = DB::table('case_sheet_types')->insertGetId(['type_code' => 'x', 'name_ar' => 'س', 'name_en' => 'x', 'is_active' => 1]);
        Sanctum::actingAs(User::factory()->create(['role' => 'super_admin']));
    }

    public function test_api_asks_before_adding_a_task_that_already_exists(): void
    {
        $task = fn (array $extra = []) => $extra + [
            'title' => 'Scaling', 'required_count' => 2, 'department_id' => $this->department->id,
            'case_sheet_type_id' => $this->sheet, 'stage_id' => 1, 'grade' => 10, 'notes' => 'ملاحظة',
        ];

        $this->postJson('/api/v1/tasks', $task())->assertCreated();

        // Same title (spacing and case aside): refused with a flag the app asks on.
        $this->postJson('/api/v1/tasks', $task(['title' => '  scaling ']))
            ->assertStatus(422)
            ->assertJsonPath('duplicate', true)
            ->assertJsonPath('duplicates', ['scaling'])
            ->assertJsonValidationErrors('title');
        $this->assertSame(1, Task::count());

        $this->postJson('/api/v1/tasks', $task(['title' => 'scaling', 'allow_duplicates' => true]))->assertCreated();
        $this->assertSame(2, Task::count());

        // Another title in the same department goes straight in.
        $this->postJson('/api/v1/tasks', $task(['title' => 'Motivation']))->assertCreated();
    }

    public function test_case_sheet_shows_its_doctor(): void
    {
        $doctor = Doctor::create([
            'name' => 'د. علي', 'username' => 'ali', 'password' => 'secret', 'email' => 'ali@example.com',
            'education_type_id' => 1, 'stage_id' => 1,
        ]);
        $task = Task::create([
            'department_id' => $this->department->id, 'case_sheet_type_id' => $this->sheet, 'stage_id' => 1,
            'title' => 'حشوة', 'required_per_doctor' => 1, 'required_count' => 1,
        ]);
        $instance = TaskInstance::create(['task_id' => $task->id, 'doctor_id' => $doctor->id, 'status' => 'assigned']);
        $record = PreventionRecord::create(['doctor_id' => $doctor->id, 'task_instances_id' => $instance->id]);

        $this->getJson("/api/v1/prevention-records/{$record->id}")
            ->assertOk()
            ->assertJsonPath('data.linked_doctor', ['id' => $doctor->id, 'name' => 'د. علي']);

        // Not worked out for every row of a list.
        $this->getJson('/api/v1/prevention-records')
            ->assertOk()
            ->assertJsonMissingPath('data.0.linked_doctor');
    }
}
