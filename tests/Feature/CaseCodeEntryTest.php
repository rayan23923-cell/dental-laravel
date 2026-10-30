<?php

namespace Tests\Feature;

use App\Models\Doctor;
use App\Models\Task;
use App\Models\TaskInstance;
use App\Models\User;
use App\Services\PermissionManager;
use App\Support\CaseCode;
use App\Support\TaskScoring;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * A supervisor types the case code shown under the case's QR instead of
 * scanning it (2026-10-30, by request).
 */
class CaseCodeEntryTest extends TestCase
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
        PermissionManager::syncGrants($this->supervisor, ['task_progress.view', 'task_progress.start', 'task_progress.track_steps', 'task_progress.finish']);
    }

    public function test_codes_round_trip_to_the_qr_payloads_and_reject_typos(): void
    {
        $this->assertSame('{"type":"task_instance","id":4523}', CaseCode::toPayload(CaseCode::forInstance(4523)));
        $this->assertSame(
            '{"type":"pending_task","task_id":37,"doctor_id":1204}',
            CaseCode::toPayload(CaseCode::format(CaseCode::forPending(37, 1204)))
        );

        $code = CaseCode::forInstance(4523);
        $typo = substr($code, 0, 2).(((int) $code[2] + 1) % 10).substr($code, 3);
        $this->assertNull(CaseCode::toPayload($typo));
        $this->assertNull(CaseCode::toPayload('12'));
        // A scanned QR passes through untouched.
        $this->assertSame('{"type":"doctor","id":1}', CaseCode::normalize('{"type":"doctor","id":1}'));
    }

    public function test_a_typed_code_opens_the_case_with_its_card_on_the_web(): void
    {
        $this->actingAs($this->supervisor);

        $this->postJson(route('task-progress.scan'), ['payload' => CaseCode::format(CaseCode::forPending($this->task->id, $this->doctor->id))])
            ->assertOk()
            ->assertJsonPath('kind', 'pending_task')
            ->assertJsonPath('doctor.name', 'د. علي')
            ->assertJsonPath('card.status', 'unassigned')
            ->assertJsonPath('card.slot', 1);

        $this->post(route('task-progress.start'), ['doctor_id' => $this->doctor->id, 'task_id' => $this->task->id])->assertRedirect();
        $instance = TaskInstance::where('doctor_id', $this->doctor->id)->sole();

        $this->postJson(route('task-progress.scan'), ['payload' => CaseCode::forInstance($instance->id)])
            ->assertOk()
            ->assertJsonPath('kind', 'task_instance')
            ->assertJsonPath('card.instance_id', $instance->id)
            ->assertJsonPath('card.status', 'assigned')
            ->assertJsonPath('card.steps_count', 1);

        // The next free slot once one is started.
        $this->postJson(route('task-progress.scan'), ['payload' => CaseCode::forPending($this->task->id, $this->doctor->id)])
            ->assertOk()->assertJsonPath('card.slot', 2);

        $this->postJson(route('task-progress.scan'), ['payload' => '123 456'])
            ->assertStatus(422)->assertJsonPath('message', 'الرمز غير صحيح، تأكد من الأرقام.');
    }

    public function test_the_app_looks_a_code_up_and_a_doctor_can_type_their_own(): void
    {
        $instance = TaskInstance::create([
            'task_id' => $this->task->id, 'doctor_id' => $this->doctor->id, 'status' => 'assigned', 'assigned_date' => now(),
        ]);

        Sanctum::actingAs($this->supervisor);
        $this->postJson('/api/v1/task-progress/lookup', ['payload' => CaseCode::forInstance($instance->id)])
            ->assertOk()
            ->assertJsonPath('kind', 'task_instance')
            ->assertJsonPath('task.id', $this->task->id)
            ->assertJsonPath('card.instance_id', $instance->id)
            ->assertJsonPath('code', CaseCode::forInstance($instance->id));

        // Without task progress the lookup is refused.
        Sanctum::actingAs(User::factory()->create(['role' => 'editor', 'status' => 'active']));
        $this->postJson('/api/v1/task-progress/lookup', ['payload' => CaseCode::forInstance($instance->id)])->assertForbidden();

        Sanctum::actingAs($this->doctor);
        $this->postJson('/api/v1/task-instances/scan', ['payload' => CaseCode::forInstance($instance->id)])
            ->assertOk()->assertJsonPath('data.id', $instance->id);
    }
}
