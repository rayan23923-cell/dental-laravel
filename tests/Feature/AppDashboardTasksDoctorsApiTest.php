<?php

namespace Tests\Feature;

use App\Models\AcademicSession;
use App\Models\Department;
use App\Models\Doctor;
use App\Models\EducationType;
use App\Models\Stage;
use App\Models\Task;
use App\Models\TaskInstance;
use App\Models\User;
use App\Models\UserPermission;
use App\Services\ScopeHelper;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use PhpOffice\PhpSpreadsheet\Spreadsheet;
use PhpOffice\PhpSpreadsheet\Writer\Xlsx;
use Tests\TestCase;

/**
 * The app's dashboard, task detail and doctors tools (2026-10-17): the API
 * side of each, with the same gates as the web pages.
 */
class AppDashboardTasksDoctorsApiTest extends TestCase
{
    use RefreshDatabase;

    private Department $department;

    private int $sheet;

    protected function setUp(): void
    {
        parent::setUp();
        EducationType::create(['id' => 1, 'name' => 'صباحي']);
        Stage::create(['id' => 1, 'name' => 'الرابعة', 'education_type_id' => 1]);
        $this->department = Department::create(['name' => 'اللثة', 'stage_id' => 1, 'education_type_id' => 1]);
        $this->sheet = DB::table('case_sheet_types')->insertGetId(['type_code' => 'x', 'name_ar' => 'س', 'name_en' => 'x', 'is_active' => 1]);
    }

    private function doctor(string $username, array $extra = []): Doctor
    {
        return Doctor::create($extra + [
            'name' => "د. {$username}", 'username' => $username, 'password' => 'secret',
            'email' => "{$username}@example.com", 'education_type_id' => 1, 'stage_id' => 1,
        ]);
    }

    private function task(array $extra = []): Task
    {
        return Task::create($extra + [
            'department_id' => $this->department->id, 'case_sheet_type_id' => $this->sheet, 'stage_id' => 1,
            'title' => 'حشوة', 'required_per_doctor' => 3, 'required_count' => 3,
        ]);
    }

    public function test_dashboard_returns_the_web_figures(): void
    {
        Sanctum::actingAs(User::factory()->create(['role' => 'super_admin']));
        $doctor = $this->doctor('ali');
        $task = $this->task();
        $this->task(['title' => 'قلع', 'done' => true]);
        TaskInstance::create(['task_id' => $task->id, 'doctor_id' => $doctor->id, 'status' => 'completed']);
        TaskInstance::create(['task_id' => $task->id, 'doctor_id' => $doctor->id, 'status' => 'assigned']);

        $this->getJson('/api/v1/dashboard')
            ->assertOk()
            ->assertJsonPath('stats.doctors', 1)
            ->assertJsonPath('stats.tasks', 2)
            ->assertJsonPath('stats.tasks_done', 1)
            ->assertJsonPath('stats.tasks_not_done', 1)
            ->assertJsonPath('stats.instances_completed', 1)
            ->assertJsonPath('stats.instances_assigned', 1)
            ->assertJsonPath('latestDoctors.0.name', 'د. ali')
            ->assertJsonPath('latestDoctors.0.education_type', 'صباحي')
            ->assertJsonPath('can.payments', true)
            ->assertJsonStructure(['income' => ['today' => ['total'], 'month' => ['total']], 'educationTypes', 'currency']);

        $this->getJson('/api/v1/dashboard/tasks-by-education-type/1')
            ->assertOk()
            ->assertJsonPath('departments.0.department', 'اللثة')
            ->assertJsonPath('departments.0.required', 6)
            ->assertJsonPath('departments.0.completed', 1)
            ->assertJsonPath('departments.0.tasks.0.title', 'حشوة')
            ->assertJsonPath('departments.0.tasks.0.remaining', 2);
    }

    public function test_dashboard_is_closed_to_doctors_and_desk_roles(): void
    {
        Sanctum::actingAs($this->doctor('ali'));
        $this->getJson('/api/v1/dashboard')->assertForbidden();

        Sanctum::actingAs(User::factory()->create(['role' => 'reception']));
        $this->getJson('/api/v1/dashboard')->assertForbidden();
        $this->getJson('/api/v1/dashboard/tasks-by-education-type/1')->assertForbidden();
    }

    public function test_tasks_by_department_follows_its_permission_and_the_scope(): void
    {
        EducationType::create(['id' => 2, 'name' => 'مسائي']);
        Stage::create(['id' => 2, 'name' => 'الخامسة', 'education_type_id' => 2]);
        $this->task();
        $user = User::factory()->create(['role' => 'editor']);
        ScopeHelper::setAllowedEducationTypes($user, [1]);
        Sanctum::actingAs($user);

        $this->getJson('/api/v1/dashboard')
            ->assertOk()
            ->assertJsonPath('educationTypes', [])
            ->assertJsonPath('can.tasks_by_department', false);
        $this->getJson('/api/v1/dashboard/tasks-by-education-type/1')->assertForbidden();

        UserPermission::create(['user_id' => $user->id, 'module' => 'dashboard', 'permission' => 'tasks_by_department', 'granted' => true]);
        Cache::flush();

        $this->getJson('/api/v1/dashboard')
            ->assertOk()
            ->assertJsonCount(1, 'educationTypes')
            ->assertJsonPath('educationTypes.0.id', 1);
        $this->getJson('/api/v1/dashboard/tasks-by-education-type/1')
            ->assertOk()
            ->assertJsonPath('departments.0.department', 'اللثة');
        $this->getJson('/api/v1/dashboard/tasks-by-education-type/2')->assertForbidden();
    }

    public function test_a_role_outside_payments_sees_no_income(): void
    {
        Sanctum::actingAs(User::factory()->create(['role' => 'accountant']));

        $this->getJson('/api/v1/dashboard')
            ->assertOk()
            ->assertJsonPath('can.payments', false)
            ->assertJsonPath('income', null)
            ->assertJsonPath('latestPayments', []);
    }

    public function test_task_detail_lists_assigns_edits_and_removes_instances(): void
    {
        Sanctum::actingAs(User::factory()->create(['role' => 'super_admin']));
        $session = AcademicSession::create(['name' => '2025', 'start_date' => '2025-09-01', 'end_date' => '2026-06-30', 'is_active' => true]);
        $other = AcademicSession::create(['name' => '2024', 'start_date' => '2024-09-01', 'end_date' => '2025-06-30', 'is_active' => true]);
        $task = $this->task(['academic_session_id' => $session->id]);
        $this->doctor('this_year', ['academic_session_id' => $session->id]);
        $this->doctor('any_year');
        $this->doctor('last_year', ['academic_session_id' => $other->id]);

        $names = collect($this->getJson("/api/v1/tasks/{$task->id}/assignable-doctors")->assertOk()->json('data'))->pluck('name');
        $this->assertEqualsCanonicalizing(['د. this_year', 'د. any_year'], $names->all());

        $doctorId = Doctor::where('username', 'this_year')->value('id');
        $id = $this->postJson('/api/v1/task-instances', ['task_id' => $task->id, 'doctor_id' => $doctorId])
            ->assertCreated()->assertJsonPath('data.status', 'assigned')->json('data.id');

        $this->getJson("/api/v1/tasks/{$task->id}")
            ->assertOk()
            ->assertJsonPath('data.instances.0.id', $id)
            ->assertJsonPath('data.instances.0.doctor.name', 'د. this_year');

        $this->putJson("/api/v1/task-instances/{$id}", ['status' => 'completed', 'grade' => 9, 'notes' => 'جيد'])
            ->assertOk()->assertJsonPath('data.status', 'completed');
        $this->assertNotNull(TaskInstance::find($id)->completion_date);

        $this->getJson("/api/v1/task-instances/{$id}/qr")->assertOk()->assertHeader('Content-Type', 'image/png');

        $this->deleteJson("/api/v1/task-instances/{$id}")->assertNoContent();
        $this->assertNull(TaskInstance::find($id));
    }

    public function test_a_doctor_cannot_assign_or_remove_instances(): void
    {
        $task = $this->task();
        $doctor = $this->doctor('ali');
        $instance = TaskInstance::create(['task_id' => $task->id, 'doctor_id' => $doctor->id, 'status' => 'assigned']);
        Sanctum::actingAs($doctor);

        $this->postJson('/api/v1/task-instances', ['task_id' => $task->id, 'doctor_id' => $doctor->id])->assertForbidden();
        $this->deleteJson("/api/v1/task-instances/{$instance->id}")->assertForbidden();
        $this->getJson("/api/v1/tasks/{$task->id}/assignable-doctors")->assertForbidden();
        $this->assertNotNull($instance->fresh());
    }

    public function test_doctors_bulk_delete_archives_unlinked_and_names_linked(): void
    {
        Sanctum::actingAs(User::factory()->create(['role' => 'super_admin']));
        $free = $this->doctor('free');
        $linked = $this->doctor('linked');
        TaskInstance::create(['task_id' => $this->task()->id, 'doctor_id' => $linked->id, 'status' => 'assigned']);
        // Doctors join their stage's default group when created; that is a link too.
        DB::table('doctor_group_members')->where('doctor_id', $free->id)->delete();

        $response = $this->deleteJson('/api/v1/doctors-bulk', ['ids' => [$free->id, $linked->id]])
            ->assertOk()
            ->assertJsonPath('archived', 1);
        $this->assertCount(1, $response->json('blocked'));
        $this->assertStringContainsString('د. linked', $response->json('blocked.0'));
        $this->assertSoftDeleted($free);
        $this->assertNotSoftDeleted($linked);

        $this->deleteJson('/api/v1/doctors-bulk', ['ids' => []])->assertUnprocessable();
    }

    public function test_doctors_template_export_and_import(): void
    {
        Sanctum::actingAs(User::factory()->create(['role' => 'super_admin']));
        $this->doctor('ali');

        $this->get('/api/v1/doctors-template')->assertOk()->assertDownload();
        $this->get('/api/v1/doctors-export')->assertOk()->assertDownload();

        $sheet = new Spreadsheet();
        $sheet->getActiveSheet()->fromArray([
            ['first', 'last', 'email', 'phone', 'username'],
            ['Sara', 'Ahmed', 'sara@example.com', '0770', 'sara'],
            ['Ali', 'X', 'ali@example.com', '', 'ali'],
        ]);
        $path = tempnam(sys_get_temp_dir(), 'doc').'.xlsx';
        (new Xlsx($sheet))->save($path);

        $this->post('/api/v1/doctors-import', [
            'file' => new UploadedFile($path, 'doctors.xlsx', null, null, true),
            'education_type_id' => 1,
            'stage_id' => 1,
            'default_password' => 'secret123',
        ], ['Accept' => 'application/json'])
            ->assertOk()
            ->assertJsonPath('imported', 1)
            ->assertJsonPath('skipped', 1);
        $this->assertTrue(Doctor::where('username', 'sara')->exists());
    }
}
