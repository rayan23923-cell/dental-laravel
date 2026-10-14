<?php

namespace Tests\Feature;

use App\Models\Doctor;
use App\Models\Task;
use App\Models\TaskInstance;
use App\Models\TaskStartRequest;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class TaskStartRequestTest extends TestCase
{
    use RefreshDatabase;

    private Doctor $doctor;

    private Task $task;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('public');
        DB::statement('SET FOREIGN_KEY_CHECKS=0');
        $this->doctor = Doctor::create([
            'name' => 'د. علي', 'username' => 'ali', 'password' => 'secret', 'email' => 'ali@example.com',
            'education_type_id' => 1, 'stage_id' => 1,
        ]);
        $this->task = Task::create([
            'department_id' => 1, 'case_sheet_type_id' => 1, 'stage_id' => 1,
            'title' => 'حشوة', 'required_per_doctor' => 2, 'required_count' => 2,
        ]);
        DB::statement('SET FOREIGN_KEY_CHECKS=1');
    }

    public function test_a_doctor_requests_a_start_and_staff_start_the_task_with_the_paper_photo(): void
    {
        $this->actingAs($this->doctor, 'doctor')
            ->post(route('doctor.task-start-requests.store'), [
                'task_id' => $this->task->id,
                'form_type' => 'paper',
                'photo' => UploadedFile::fake()->image('form.jpg'),
            ])->assertCreated();

        // A second request for the same task waits on the first.
        $this->post(route('doctor.task-start-requests.store'), ['task_id' => $this->task->id, 'form_type' => 'electronic'])
            ->assertStatus(302);
        $this->assertSame(1, TaskStartRequest::count());

        $admin = User::factory()->create(['role' => 'super_admin']);
        $this->actingAs($admin)->get(route('task-progress.requests.index'))
            ->assertOk()->assertJsonPath('pending_count', 1);

        $request = TaskStartRequest::first();
        $this->postJson(route('task-progress.requests.approve', $request), ['note' => 'تمام'])->assertOk()
            ->assertJsonPath('request.status', 'approved');

        $instance = TaskInstance::where('doctor_id', $this->doctor->id)->where('status', 'assigned')->sole();
        $this->assertSame($instance->id, (int) $request->fresh()->task_instance_id);
        $this->assertSame(1, $instance->attachments()->count());
        Storage::disk('public')->assertExists($instance->attachments()->first()->path);

        // Reviewed once only.
        $this->postJson(route('task-progress.requests.reject', $request))->assertStatus(422);
    }

    public function test_a_turned_down_request_keeps_the_reason_and_starts_nothing(): void
    {
        $request = TaskStartRequest::create([
            'doctor_id' => $this->doctor->id, 'task_id' => $this->task->id, 'form_type' => 'electronic', 'status' => 'pending',
        ]);

        $this->actingAs(User::factory()->create(['role' => 'super_admin']))
            ->postJson(route('task-progress.requests.reject', $request), ['note' => 'املأ النموذج'])
            ->assertOk()->assertJsonPath('request.review_note', 'املأ النموذج');

        $this->assertSame(0, TaskInstance::count());
        $this->actingAs($this->doctor, 'doctor')->getJson(route('doctor.task-start-requests.index'))
            ->assertJsonPath('data.0.status', 'rejected');
    }

    public function test_staff_hear_about_new_requests_and_doctors_about_turned_down_ones(): void
    {
        \App\Models\ClinicSetting::current()->update(['enable_notifications' => true]);
        $admin = User::factory()->create(['role' => 'super_admin', 'status' => 'active']);

        $this->actingAs($this->doctor, 'doctor')
            ->post(route('doctor.task-start-requests.store'), ['task_id' => $this->task->id, 'form_type' => 'electronic'])
            ->assertCreated();

        $this->assertSame(1, $admin->notifications()->count());
        $this->actingAs($admin)->getJson(route('notifications.index'))
            ->assertJsonPath('unread', 1)
            ->assertJsonPath('data.0.kind', 'new');

        $this->postJson(route('task-progress.requests.reject', TaskStartRequest::first()), ['note' => 'لاحقاً'])->assertOk();
        $this->actingAs($this->doctor, 'doctor')->getJson(route('doctor.notifications.index'))
            ->assertJsonPath('unread', 1)
            ->assertJsonPath('data.0.kind', 'rejected');
    }
}
