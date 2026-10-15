<?php

namespace Tests\Feature;

use App\Models\Doctor;
use App\Models\Task;
use App\Models\TaskInstance;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class CaseSheetReturnTest extends TestCase
{
    use RefreshDatabase;

    public function test_saving_a_doctors_case_sheet_returns_to_the_page_it_was_opened_from(): void
    {
        DB::statement('SET FOREIGN_KEY_CHECKS=0');
        $doctor = Doctor::create([
            'name' => 'د. علي', 'username' => 'ali', 'password' => 'secret', 'email' => 'ali@example.com',
            'education_type_id' => 1, 'stage_id' => 1,
        ]);
        $task = Task::create([
            'department_id' => 1, 'case_sheet_type_id' => 1, 'stage_id' => 1,
            'title' => 'حشوة', 'required_per_doctor' => 1, 'required_count' => 1,
        ]);
        DB::statement('SET FOREIGN_KEY_CHECKS=1');
        $instance = TaskInstance::create(['task_id' => $task->id, 'doctor_id' => $doctor->id, 'status' => 'assigned']);

        $from = route('doctor.required-tasks');
        $this->actingAs($doctor, 'doctor')
            ->get(route('doctor.case-sheet', $instance), ['referer' => $from])
            ->assertRedirect(route('dental-charts.create', ['task_instances_id' => $instance->id]));

        $this->post(route('dental-charts.store'), [
            'doctor_id' => $doctor->id,
            'patient_id' => 'مريض',
            'task_instances_id' => $instance->id,
        ])->assertRedirect($from);
    }

    public function test_without_an_origin_a_doctor_goes_back_to_their_tasks(): void
    {
        DB::statement('SET FOREIGN_KEY_CHECKS=0');
        $doctor = Doctor::create([
            'name' => 'د. علي', 'username' => 'ali', 'password' => 'secret', 'email' => 'ali@example.com',
            'education_type_id' => 1, 'stage_id' => 1,
        ]);
        DB::statement('SET FOREIGN_KEY_CHECKS=1');

        $this->actingAs($doctor, 'doctor')
            ->post(route('dental-charts.store'), ['doctor_id' => $doctor->id, 'patient_id' => 'مريض'])
            ->assertRedirect(route('doctor.required-tasks'));
    }
}
