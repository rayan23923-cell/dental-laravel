<?php

namespace Tests\Feature;

use App\Models\Department;
use App\Models\EducationType;
use App\Models\Stage;
use App\Models\Task;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class TaskDuplicateWarningTest extends TestCase
{
    use RefreshDatabase;

    public function test_adding_a_task_that_already_exists_needs_confirming(): void
    {
        EducationType::create(['id' => 1, 'name' => 'صباحي']);
        Stage::create(['id' => 1, 'name' => 'الرابعة', 'education_type_id' => 1]);
        $department = Department::create(['name' => 'اللثة', 'stage_id' => 1, 'education_type_id' => 1]);
        $sheet = DB::table('case_sheet_types')->insertGetId(['type_code' => 'x', 'name_ar' => 'س', 'name_en' => 'x', 'is_active' => 1]);
        $this->actingAs(User::factory()->create(['role' => 'super_admin']));

        $base = [
            'department_id' => $department->id, 'case_sheet_type_id' => $sheet, 'stage_id' => 1,
            'grade' => 10, 'notes' => 'ملاحظة',
        ];
        $rows = fn () => ['rows' => [
            ['enabled' => true, 'title' => 'Scaling  simple', 'required_count' => 5],
            ['enabled' => true, 'title' => 'Motivation', 'required_count' => 3],
        ]] + $base;

        $this->post('/tasks', $rows())->assertSessionHasNoErrors();
        $this->assertSame(2, Task::count());

        // Same titles again (spacing and case aside): stopped with a warning.
        $this->post('/tasks', ['title' => 'scaling simple', 'required_count' => 1] + $base)->assertSessionHasErrors('title');
        $this->post('/tasks', $rows())->assertSessionHasErrors('rows');
        $this->assertSame(2, Task::count());

        // Confirmed in the form: added anyway.
        $this->post('/tasks', ['allow_duplicates' => true] + $rows())->assertSessionHasNoErrors();
        $this->assertSame(4, Task::count());
    }
}
