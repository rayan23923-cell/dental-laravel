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

class TaskDepartmentStageTest extends TestCase
{
    use RefreshDatabase;

    public function test_a_task_must_use_a_department_of_its_own_stage(): void
    {
        EducationType::create(['id' => 1, 'name' => 'صباحي']);
        Stage::create(['id' => 1, 'name' => 'الرابعة', 'education_type_id' => 1]);
        Stage::create(['id' => 2, 'name' => 'الخامسة', 'education_type_id' => 1]);
        $own = Department::create(['name' => 'الحشوات', 'stage_id' => 1, 'education_type_id' => 1]);
        $other = Department::create(['name' => 'الجراحة', 'stage_id' => 2, 'education_type_id' => 1]);
        $loose = Department::create(['name' => 'بدون مرحلة', 'stage_id' => null, 'education_type_id' => 1]);
        $sheet = DB::table('case_sheet_types')->insertGetId(['type_code' => 'x', 'name_ar' => 'س', 'name_en' => 'x', 'is_active' => 1]);
        $admin = User::factory()->create(['role' => 'super_admin']);

        $task = fn ($departmentId) => [
            'department_id' => $departmentId, 'case_sheet_type_id' => $sheet, 'stage_id' => 1,
            'title' => 'حشوة', 'required_per_doctor' => 1, 'required_count' => 1,
        ];

        $this->actingAs($admin)->post('/tasks', $task($other->id))->assertSessionHasErrors('department_id');
        $this->post('/tasks', $task($loose->id))->assertSessionHasErrors('department_id');
        $this->post('/tasks', $task(null))->assertSessionHasErrors('department_id');
        $this->post('/tasks', $task($own->id))->assertSessionHasNoErrors();

        $this->assertSame([$own->id], Task::pluck('department_id')->map(fn ($id) => (int) $id)->all());
    }
}
