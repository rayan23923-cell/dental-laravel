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
            'title' => 'حشوة', 'required_per_doctor' => 1, 'required_count' => 1, 'grade' => 10, 'notes' => 'ملاحظة',
        ];

        $this->actingAs($admin)->post('/tasks', $task($other->id))->assertSessionHasErrors('department_id');
        $this->post('/tasks', $task($loose->id))->assertSessionHasErrors('department_id');
        $this->post('/tasks', $task(null))->assertSessionHasErrors('department_id');
        // Back to the list on the task's own stage and department, so it shows.
        $this->post('/tasks', $task($own->id))->assertSessionHasNoErrors()
            ->assertRedirect(route('tasks.index', ['stage_id' => 1, 'department_id' => $own->id]));
        $saved = Task::latest('id')->first();
        $this->put("/tasks/{$saved->id}", ['title' => 'حشوة معدلة'] + $task($own->id))
            ->assertRedirect(route('tasks.index', ['stage_id' => 1, 'department_id' => $own->id]));

        $this->assertSame([$own->id], Task::pluck('department_id')->map(fn ($id) => (int) $id)->all());

        // "المطلوب لكل طبيب" is gone: an old value sent by an older app is
        // ignored and the stored column follows required_count.
        $this->post('/tasks', ['required_per_doctor' => 9, 'required_count' => 3] + $task($own->id))->assertSessionHasNoErrors();
        $this->assertSame(3, (int) Task::latest('id')->value('required_per_doctor'));
    }

    public function test_departments_stages_and_tasks_need_every_field(): void
    {
        $admin = \App\Models\User::factory()->create(['role' => 'super_admin']);
        $this->actingAs($admin);

        $this->post('/stages', ['name' => 'رابعة'])->assertSessionHasErrors('education_type_id');
        $this->post('/departments', ['name' => 'حشوات'])->assertSessionHasErrors(['education_type_id', 'stage_id']);
        $this->post('/tasks', ['title' => 'حشوة'])->assertSessionHasErrors(['notes', 'grade']);
    }
}
