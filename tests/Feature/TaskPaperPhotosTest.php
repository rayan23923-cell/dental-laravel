<?php

namespace Tests\Feature;

use App\Models\Doctor;
use App\Models\ScannerPairing;
use App\Models\Task;
use App\Models\TaskInstance;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class TaskPaperPhotosTest extends TestCase
{
    use RefreshDatabase;

    private function startedCase(): TaskInstance
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

        return TaskInstance::create(['task_id' => $task->id, 'doctor_id' => $doctor->id, 'status' => 'assigned']);
    }

    public function test_staff_attach_a_photo_from_the_computer_and_from_the_paired_phone(): void
    {
        Storage::fake('public');
        Storage::fake('local');
        $instance = $this->startedCase();
        $admin = User::factory()->create(['role' => 'super_admin']);

        // From the computer.
        $this->actingAs($admin)
            ->post("/task-progress/instances/{$instance->id}/attachments", ['photo' => UploadedFile::fake()->image('page1.jpg')])
            ->assertCreated()->assertJsonCount(1, 'data');

        // From the phone: the computer asks, the phone sees the request and sends a photo.
        $pairing = ScannerPairing::open($admin);
        $this->putJson("/scanner-pairings/{$pairing->id}/photo-request", ['label' => 'حشوة - د. علي'])->assertOk();
        auth()->logout();
        $this->getJson("/scan/{$pairing->token}/status")->assertJsonPath('data.photo_request', 'حشوة - د. علي');
        $scanId = $this->post("/scan/{$pairing->token}/photos", ['photo' => UploadedFile::fake()->image('page2.jpg')])
            ->assertCreated()->json('data.id');
        $this->getJson("/scan/{$pairing->token}/status")->assertJsonPath('data.photo_request', null);
        $this->post("/scan/{$pairing->token}/photos", ['photo' => UploadedFile::fake()->create('notes.pdf', 10, 'application/pdf')])
            ->assertSessionHasErrors('photo');

        $poll = $this->actingAs($admin)->getJson("/scanner-pairings/{$pairing->id}/scans")->json('data.scans');
        $this->assertSame([['id' => $scanId, 'payload' => '[photo]', 'photo' => true]], $poll);

        // Someone else's computer can't take it; the owner attaches it once.
        $other = User::factory()->create(['role' => 'super_admin']);
        $this->actingAs($other)->postJson("/task-progress/instances/{$instance->id}/attachments", ['scan_id' => $scanId])
            ->assertJsonValidationErrors('scan_id');
        $list = $this->actingAs($admin)->postJson("/task-progress/instances/{$instance->id}/attachments", ['scan_id' => $scanId])
            ->assertCreated()->assertJsonCount(2, 'data')->json('data');
        $this->postJson("/task-progress/instances/{$instance->id}/attachments", ['scan_id' => $scanId])
            ->assertJsonValidationErrors('scan_id');
        $this->assertCount(0, Storage::disk('local')->allFiles($pairing->photoDir()));
        $this->assertCount(2, Storage::disk('public')->allFiles("task-forms/{$instance->id}"));

        // Deleting removes the file too.
        $this->deleteJson("/task-progress/attachments/{$list[0]['id']}")->assertOk()->assertJsonCount(1, 'data');
        $this->assertCount(1, Storage::disk('public')->allFiles("task-forms/{$instance->id}"));
    }

    public function test_a_doctor_attaches_photos_to_their_own_cases_only(): void
    {
        Storage::fake('public');
        $instance = $this->startedCase();
        $doctor = $instance->doctor;
        DB::statement('SET FOREIGN_KEY_CHECKS=0');
        $otherDoctor = Doctor::create([
            'name' => 'د. سارة', 'username' => 'sara', 'password' => 'secret', 'email' => 'sara@example.com',
            'education_type_id' => 1, 'stage_id' => 1,
        ]);
        DB::statement('SET FOREIGN_KEY_CHECKS=1');

        $this->actingAs($otherDoctor, 'doctor')
            ->postJson("/doctor/task-instances/{$instance->id}/attachments", ['photo' => UploadedFile::fake()->image('x.jpg')])
            ->assertForbidden();

        $id = $this->actingAs($doctor, 'doctor')
            ->postJson("/doctor/task-instances/{$instance->id}/attachments", ['photo' => UploadedFile::fake()->image('x.jpg')])
            ->assertCreated()->json('data.0.id');
        $this->actingAs($otherDoctor, 'doctor')->deleteJson("/doctor/task-instance-attachments/{$id}")->assertForbidden();
        $this->actingAs($doctor, 'doctor')->deleteJson("/doctor/task-instance-attachments/{$id}")->assertOk()->assertJsonCount(0, 'data');
    }

    public function test_the_mobile_app_attaches_photos_over_the_api(): void
    {
        Storage::fake('public');
        $instance = $this->startedCase();
        $admin = User::factory()->create(['role' => 'super_admin']);

        Sanctum::actingAs($admin);
        $this->postJson("/api/v1/task-progress/instances/{$instance->id}/attachments", ['photo' => UploadedFile::fake()->image('a.jpg')])
            ->assertCreated()->assertJsonCount(1, 'data');
        $this->getJson("/api/v1/my-task-instances/{$instance->id}/attachments")->assertForbidden();

        Sanctum::actingAs($instance->doctor);
        $this->postJson("/api/v1/my-task-instances/{$instance->id}/attachments", ['photo' => UploadedFile::fake()->image('b.jpg')])
            ->assertCreated()->assertJsonCount(2, 'data');
        $this->getJson("/api/v1/task-progress/instances/{$instance->id}/attachments")->assertForbidden();
        $this->getJson('/api/v1/my-task-progress')->assertOk();
    }

    public function test_the_supervisor_notes_a_doctors_photo_and_the_doctor_sees_it(): void
    {
        Storage::fake('public');
        $instance = $this->startedCase();
        $doctor = $instance->doctor;
        $admin = User::factory()->create(['role' => 'super_admin', 'full_name' => 'د. المشرف']);

        $id = $this->actingAs($doctor, 'doctor')
            ->postJson("/doctor/task-instances/{$instance->id}/attachments", ['photo' => UploadedFile::fake()->image('x.jpg')])
            ->assertCreated()->assertJsonPath('data.0.by_doctor', true)->json('data.0.id');

        $this->actingAs($admin, 'web')
            ->putJson("/task-progress/attachments/{$id}/note", ['note' => '  الحشوة غير مكتملة من الحافة  '])
            ->assertOk()
            ->assertJsonPath('data.0.note', 'الحشوة غير مكتملة من الحافة')
            ->assertJsonPath('data.0.note_by', 'د. المشرف');
        $this->assertDatabaseHas('notifications', ['notifiable_id' => $doctor->id, 'type' => \App\Notifications\PhotoNoteAdded::class]);

        $this->actingAs($doctor, 'doctor')
            ->getJson("/doctor/task-instances/{$instance->id}/attachments")
            ->assertJsonPath('data.0.note', 'الحشوة غير مكتملة من الحافة');

        // The app's API, and clearing the note.
        Sanctum::actingAs($admin);
        $this->putJson("/api/v1/task-progress/attachments/{$id}/note", ['note' => ''])
            ->assertOk()->assertJsonPath('data.0.note', null)->assertJsonPath('data.0.note_at', null);

        // The doctor can't write notes.
        Sanctum::actingAs($doctor);
        $this->putJson("/api/v1/task-progress/attachments/{$id}/note", ['note' => 'x'])->assertForbidden();
    }

    public function test_a_sheet_opened_from_a_task_case_shows_that_cases_doctor(): void
    {
        $instance = $this->startedCase();
        $admin = User::factory()->create(['role' => 'super_admin']);

        $this->actingAs($admin)
            ->get("/prosthodontics-records/create?task_instances_id={$instance->id}")
            ->assertOk()
            ->assertInertia(fn ($page) => $page
                ->where('linkedDoctor.id', $instance->doctor_id)
                ->where('linkedDoctor.name', 'د. علي'));
    }
}
