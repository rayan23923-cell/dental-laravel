<?php

namespace Tests\Feature;

use App\Models\Doctor;
use App\Models\Task;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Notification;
use Tests\TestCase;

class TaskStartWithoutPatientTest extends TestCase
{
    use RefreshDatabase;

    private function doctorAndTask(): array
    {
        // Parent rows (stage, education type, department) don't matter here.
        DB::statement('SET FOREIGN_KEY_CHECKS=0');
        $doctor = Doctor::create([
            'name' => 'د. علي', 'username' => 'ali', 'password' => 'secret', 'email' => 'ali@example.com',
            'education_type_id' => 1, 'stage_id' => 1,
        ]);
        $task = Task::create([
            'department_id' => 1, 'case_sheet_type_id' => 1, 'stage_id' => 1,
            'title' => 'حشوة', 'required_per_doctor' => 2, 'required_count' => 2,
        ]);
        DB::statement('SET FOREIGN_KEY_CHECKS=1');

        return [$doctor, $task];
    }

    public function test_web_start_needs_no_patient(): void
    {
        Notification::fake();
        [$doctor, $task] = $this->doctorAndTask();
        $admin = User::factory()->create(['role' => 'super_admin']);

        $this->actingAs($admin)
            ->post('/task-progress/start', ['doctor_id' => $doctor->id, 'task_id' => $task->id])
            ->assertSessionHasNoErrors()
            ->assertSessionHas('success');

        $this->assertDatabaseHas('task_instances', [
            'task_id' => $task->id, 'doctor_id' => $doctor->id, 'status' => 'assigned', 'patient_registration_id' => null,
        ]);
    }

    public function test_api_start_needs_no_patient(): void
    {
        Notification::fake();
        [$doctor, $task] = $this->doctorAndTask();
        $admin = User::factory()->create(['role' => 'super_admin']);

        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/task-progress/start', ['doctor_id' => $doctor->id, 'task_id' => $task->id])
            ->assertOk()
            ->assertJsonPath('data.status', 'assigned');
    }
}
