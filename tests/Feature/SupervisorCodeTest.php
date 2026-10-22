<?php

namespace Tests\Feature;

use App\Models\ClinicSetting;
use App\Models\Doctor;
use App\Models\Task;
use App\Models\TaskInstance;
use App\Models\TaskStartRequest;
use App\Models\User;
use App\Services\PermissionManager;
use App\Services\SupervisorCode;
use App\Support\TaskScoring;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * The supervisor code typed on a student's account, and "إعدادات النماذج"
 * (2026-10-22, by request).
 */
class SupervisorCodeTest extends TestCase
{
    use RefreshDatabase;

    private Doctor $doctor;

    private Task $task;

    private User $supervisor;

    protected function setUp(): void
    {
        parent::setUp();
        DB::statement('SET FOREIGN_KEY_CHECKS=0');
        $this->doctor = Doctor::create([
            'name' => 'د. علي', 'username' => 'ali', 'password' => 'secret', 'email' => 'ali@example.com',
            'education_type_id' => 1, 'stage_id' => 1,
        ]);
        $this->task = Task::create([
            'department_id' => 1, 'case_sheet_type_id' => 1, 'stage_id' => 1,
            'title' => 'حشوة', 'required_per_doctor' => 2, 'required_count' => 2, 'grade' => 20,
            'scoring' => TaskScoring::normalize([
                'measure' => 'both',
                'steps' => [['key' => 'custom_1', 'label' => 'التحضير', 'max' => 10, 'enabled' => true, 'custom' => true]],
            ]),
        ]);
        DB::statement('SET FOREIGN_KEY_CHECKS=1');
        $this->supervisor = User::factory()->create(['role' => 'admin', 'status' => 'active', 'full_name' => 'د. المشرف', 'scope_all_education_types' => true, 'scope_all_academic_sessions' => true]);
        PermissionManager::syncGrants($this->supervisor, ['task_progress.view', 'task_progress.supervisor_code', 'task_progress.start', 'task_progress.track_steps', 'task_progress.finish']);
        ClinicSetting::current()->update(['supervisor_code_enabled' => true]);
    }

    public function test_a_supervisor_starts_signs_and_completes_a_case_with_their_code(): void
    {
        $code = SupervisorCode::for($this->supervisor);
        $this->actingAs($this->supervisor)->getJson(route('task-progress.my-code'))
            ->assertOk()->assertJsonPath('code', $code)->assertJsonPath('period', 'daily');

        $this->actingAs($this->doctor, 'doctor');
        $this->postJson(route('doctor.supervisor-code.start'), ['task_id' => $this->task->id, 'code' => $code, 'form_type' => 'electronic'])
            ->assertOk()->assertJsonPath('supervisor', 'د. المشرف');
        $instance = TaskInstance::where('doctor_id', $this->doctor->id)->sole();
        $this->assertSame('assigned', $instance->status);
        $this->assertSame((int) $this->supervisor->id, (int) TaskStartRequest::sole()->reviewed_by_user_id);

        $this->postJson(route('doctor.supervisor-code.step', $instance), ['code' => $code, 'step' => 's:custom_1', 'grade' => 8])->assertOk();
        $this->assertSame('د. المشرف', $instance->fresh()->step_signoffs['s:custom_1']['signed_by']);

        $this->postJson(route('doctor.supervisor-code.complete', $instance), ['code' => $code, 'grade' => 18])->assertOk();
        $this->assertSame('completed', $instance->fresh()->status);
    }

    public function test_wrong_codes_and_missing_permissions_are_refused_then_locked(): void
    {
        $this->actingAs($this->doctor, 'doctor');
        $wrong = SupervisorCode::for($this->supervisor) === '000000' ? '111111' : '000000';

        // Without the finish permission the right code can't complete.
        PermissionManager::syncGrants($this->supervisor, ['task_progress.supervisor_code', 'task_progress.start']);
        $instance = TaskInstance::create(['task_id' => $this->task->id, 'doctor_id' => $this->doctor->id, 'status' => 'assigned']);
        $this->postJson(route('doctor.supervisor-code.complete', $instance), ['code' => SupervisorCode::for($this->supervisor)])
            ->assertJsonValidationErrors('code');

        for ($i = 0; $i < 4; $i++) {
            $this->postJson(route('doctor.supervisor-code.start'), ['task_id' => $this->task->id, 'code' => $wrong, 'form_type' => 'electronic'])
                ->assertJsonValidationErrors('code');
        }
        // Locked now, even with the right code.
        $this->postJson(route('doctor.supervisor-code.start'), ['task_id' => $this->task->id, 'code' => SupervisorCode::for($this->supervisor), 'form_type' => 'electronic'])
            ->assertJsonValidationErrors('code');
        $this->assertSame(1, TaskInstance::count());
    }

    public function test_the_code_changes_every_hour_when_set_to_hourly_and_is_off_by_setting(): void
    {
        ClinicSetting::current()->update(['supervisor_code_period' => 'hourly']);
        $at = Carbon::create(2026, 10, 22, 10, 30, 0, 'Asia/Baghdad');
        $this->assertNotSame(SupervisorCode::for($this->supervisor, $at), SupervisorCode::for($this->supervisor, $at->copy()->addHour()));
        $this->assertSame(SupervisorCode::for($this->supervisor, $at), SupervisorCode::for($this->supervisor, $at->copy()->addMinutes(20)));

        ClinicSetting::current()->update(['supervisor_code_enabled' => false]);
        $this->actingAs($this->doctor, 'doctor')
            ->postJson(route('doctor.supervisor-code.start'), ['task_id' => $this->task->id, 'code' => SupervisorCode::for($this->supervisor), 'form_type' => 'electronic'])
            ->assertJsonValidationErrors('code');
    }

    public function test_form_settings_limit_form_types_and_hide_grades_from_students(): void
    {
        $admin = User::factory()->create(['role' => 'super_admin']);
        $this->actingAs($admin)->putJson(route('form-settings.update'), [
            'electronic_forms_enabled' => false, 'paper_forms_enabled' => false, 'show_grades_to_doctors' => true,
            'supervisor_code_enabled' => true, 'supervisor_code_period' => 'daily', 'supervisor_code_actions' => ['start'],
        ])->assertJsonValidationErrors('paper_forms_enabled');
        $this->putJson(route('form-settings.update'), [
            'electronic_forms_enabled' => false, 'paper_forms_enabled' => true, 'show_grades_to_doctors' => false,
            'supervisor_code_enabled' => true, 'supervisor_code_period' => 'hourly', 'supervisor_code_actions' => ['start'],
        ])->assertOk()->assertJsonPath('settings.supervisor_code_actions', ['start']);
        $this->get(route('form-settings.index'))->assertOk();

        TaskInstance::create(['task_id' => $this->task->id, 'doctor_id' => $this->doctor->id, 'status' => 'completed', 'grade' => 17]);
        Sanctum::actingAs($this->doctor);
        $this->getJson('/api/v1/my-form-settings')->assertOk()
            ->assertJsonPath('electronic_forms_enabled', false)->assertJsonPath('show_grades', false)
            ->assertJsonPath('supervisor_code_actions', ['start']);
        $this->postJson('/api/v1/my-task-start-requests', ['task_id' => $this->task->id, 'form_type' => 'electronic'])
            ->assertJsonValidationErrors('form_type');
        $this->assertStringNotContainsString('17', json_encode(collect($this->getJson('/api/v1/my-task-progress')->json())->pluck('doctor.tasks')));
    }
}
