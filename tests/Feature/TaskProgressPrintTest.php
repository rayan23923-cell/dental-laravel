<?php

namespace Tests\Feature;

use App\Models\Department;
use App\Models\Doctor;
use App\Models\EducationType;
use App\Models\Stage;
use App\Models\Task;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class TaskProgressPrintTest extends TestCase
{
    use RefreshDatabase;

    public function test_task_progress_prints_a_stage_department_or_doctor(): void
    {
        EducationType::create(['id' => 1, 'name' => 'صباحي']);
        Stage::create(['id' => 1, 'name' => 'الرابعة', 'education_type_id' => 1]);
        $fillings = Department::create(['name' => 'الحشوات', 'stage_id' => 1, 'education_type_id' => 1]);
        $surgery = Department::create(['name' => 'الجراحة', 'stage_id' => 1, 'education_type_id' => 1]);
        $sheet = DB::table('case_sheet_types')->insertGetId(['type_code' => 'x', 'name_ar' => 'س', 'name_en' => 'x', 'is_active' => 1]);
        Task::create(['department_id' => $fillings->id, 'case_sheet_type_id' => $sheet, 'stage_id' => 1, 'title' => 'حشوة أمامية', 'required_count' => 1]);
        Task::create(['department_id' => $surgery->id, 'case_sheet_type_id' => $sheet, 'stage_id' => 1, 'title' => 'قلع بسيط', 'required_count' => 1]);
        $ali = Doctor::create(['name' => 'د. علي', 'username' => 'ali', 'password' => 'secret', 'email' => 'ali@example.com', 'education_type_id' => 1, 'stage_id' => 1]);
        Doctor::create(['name' => 'د. سارة', 'username' => 'sara', 'password' => 'secret', 'email' => 'sara@example.com', 'education_type_id' => 1, 'stage_id' => 1]);
        $this->actingAs(User::factory()->create(['role' => 'super_admin']));

        $this->get('/task-progress/print?stage=1')->assertOk()
            ->assertSee('تقرير تقدم المهام')->assertSee('حشوة أمامية')->assertSee('قلع بسيط')->assertSee('د. سارة');

        $this->get("/task-progress/print?stage=1&department={$fillings->id}")->assertOk()
            ->assertSee('حشوة أمامية')->assertDontSee('قلع بسيط');

        $this->get("/task-progress/print?stage=1&department={$fillings->id}&doctor={$ali->id}")->assertOk()
            ->assertSee('د. علي')->assertDontSee('د. سارة');
    }
}
