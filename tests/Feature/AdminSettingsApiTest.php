<?php

namespace Tests\Feature;

use App\Models\AcademicSession;
use App\Models\ClinicSetting;
use App\Models\Department;
use App\Models\DepartmentRoleAssignment;
use App\Models\Doctor;
use App\Models\EducationType;
use App\Models\Group;
use App\Models\Stage;
use App\Models\User;
use App\Models\UserPermission;
use App\Models\WaitingScreenSetting;
use App\Notifications\AdminBroadcast;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Notification;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/** Admin/settings screens ported to the app (2026-10-17): their API side. */
class AdminSettingsApiTest extends TestCase
{
    use RefreshDatabase;

    private function admin(): User
    {
        return User::factory()->create(['role' => 'super_admin']);
    }

    public function test_mail_settings_save_without_ever_returning_the_password(): void
    {
        Sanctum::actingAs($this->admin());

        $this->putJson('/api/v1/clinic-settings', [
            'clinic_name' => 'عيادة',
            'mail_host' => 'smtp.gmail.com',
            'mail_port' => 587,
            'mail_username' => 'me@gmail.com',
            'mail_password' => 'app-password',
            'mail_encryption' => 'tls',
            'mail_from_address' => 'me@gmail.com',
            'mail_from_name' => 'Clinic',
        ])->assertOk()
            ->assertJsonPath('mail_host', 'smtp.gmail.com')
            ->assertJsonPath('mail_password_set', true)
            ->assertJsonPath('mail_configured', true)
            ->assertJsonMissingPath('mail_password');

        $this->assertSame('app-password', ClinicSetting::current()->mail_password);

        // A blank password keeps the stored one.
        $this->putJson('/api/v1/clinic-settings', ['clinic_name' => 'عيادة', 'mail_password' => '', 'mail_host' => 'smtp.example.com'])
            ->assertOk()->assertJsonPath('mail_password_set', true);
        $this->assertSame('app-password', ClinicSetting::current()->fresh()->mail_password);

        $this->getJson('/api/v1/clinic-settings')->assertOk()
            ->assertJsonPath('mail_host', 'smtp.example.com')
            ->assertJsonMissingPath('mail_password');
    }

    public function test_others_cannot_see_mail_settings_or_change_clinic_settings(): void
    {
        ClinicSetting::current()->update(['mail_host' => 'smtp.secret.com', 'mail_password' => 'x']);

        Sanctum::actingAs(User::factory()->create(['role' => 'editor']));
        $this->getJson('/api/v1/clinic-settings')->assertOk()
            ->assertJsonMissingPath('mail_host')
            ->assertJsonMissingPath('mail_password_set');
        $this->putJson('/api/v1/clinic-settings', ['clinic_name' => 'x'])->assertForbidden();
        $this->postJson('/api/v1/clinic-settings/test-email', ['to' => 'a@b.com'])->assertForbidden();

        // An admin without the settings,edit grant is refused too.
        Sanctum::actingAs(User::factory()->create(['role' => 'admin']));
        $this->putJson('/api/v1/clinic-settings', ['clinic_name' => 'x'])->assertForbidden();
    }

    public function test_test_email_needs_saved_mail_settings_then_sends(): void
    {
        Sanctum::actingAs($this->admin());

        $this->postJson('/api/v1/clinic-settings/test-email', ['to' => 'a@b.com'])
            ->assertStatus(422)->assertJsonPath('message', 'أدخل خادم SMTP وعنوان المرسل واحفظ الإعدادات أولاً.');

        ClinicSetting::current()->update(['mail_host' => 'smtp.example.com', 'mail_from_address' => 'clinic@example.com']);
        config(['mail.default' => 'array']);

        $this->postJson('/api/v1/clinic-settings/test-email', ['to' => 'a@b.com'])
            ->assertOk()->assertJsonPath('message', 'تم إرسال رسالة تجريبية إلى a@b.com.');
        $this->postJson('/api/v1/clinic-settings/test-email', ['to' => 'not-an-email'])->assertJsonValidationErrors('to');
    }

    public function test_waiting_screen_settings_read_and_save(): void
    {
        EducationType::create(['id' => 1, 'name' => 'صباحي']);
        $stage = Stage::create(['name' => 'الرابعة', 'education_type_id' => 1]);
        $group = Group::create(['name' => 'A', 'stage_id' => $stage->id]);

        $admin = User::factory()->create(['role' => 'admin']);
        UserPermission::create(['user_id' => $admin->id, 'module' => 'settings', 'permission' => 'view', 'granted' => true]);
        Sanctum::actingAs($admin);

        $this->getJson('/api/v1/waiting-screen-settings')->assertOk()
            ->assertJsonPath('data.groups.0.name', 'A')
            ->assertJsonPath('data.groups.0.stage_name', 'الرابعة');
        // Viewing is not editing.
        $this->putJson('/api/v1/waiting-screen-settings', ['patients_per_page' => 5, 'rotation_seconds' => 10])->assertForbidden();

        UserPermission::create(['user_id' => $admin->id, 'module' => 'settings', 'permission' => 'edit', 'granted' => true]);
        \Illuminate\Support\Facades\Cache::flush();
        $this->putJson('/api/v1/waiting-screen-settings', ['group_id' => $group->id, 'patients_per_page' => 5, 'rotation_seconds' => 10])
            ->assertOk()->assertJsonPath('data.settings.group_id', $group->id);
        $this->assertSame(5, WaitingScreenSetting::current()->patients_per_page);

        $this->putJson('/api/v1/waiting-screen-settings', ['patients_per_page' => 0, 'rotation_seconds' => 1])
            ->assertJsonValidationErrors(['patients_per_page', 'rotation_seconds']);

        Sanctum::actingAs(User::factory()->create(['role' => 'editor']));
        $this->getJson('/api/v1/waiting-screen-settings')->assertForbidden();
    }

    public function test_department_roles_assign_toggle_and_remove(): void
    {
        EducationType::create(['id' => 1, 'name' => 'صباحي']);
        $stage = Stage::create(['name' => 'الرابعة', 'education_type_id' => 1]);
        $other = Stage::create(['name' => 'الخامسة', 'education_type_id' => 1]);
        $department = Department::create(['name' => 'اللثة', 'stage_id' => $stage->id, 'education_type_id' => 1]);
        $staff = User::factory()->create(['role' => 'editor', 'full_name' => 'سارة']);
        Sanctum::actingAs($this->admin());

        $this->getJson('/api/v1/department-roles')->assertOk()
            ->assertJsonPath('data.users.0.full_name', 'سارة')
            ->assertJsonPath('data.departments.0.stage_id', $stage->id);

        // The department must belong to the chosen stage.
        $this->postJson('/api/v1/department-roles', [
            'user_id' => $staff->id, 'stage_id' => $other->id, 'department_id' => $department->id, 'role_type' => 'senior',
        ])->assertJsonValidationErrors('department_id');

        $id = $this->postJson('/api/v1/department-roles', [
            'user_id' => $staff->id, 'stage_id' => $stage->id, 'department_id' => $department->id, 'role_type' => 'hr',
        ])->assertCreated()
            ->assertJsonPath('data.user_name', 'سارة')
            ->assertJsonPath('data.department_name', 'اللثة')
            ->assertJsonPath('data.status', 'active')
            ->json('data.id');

        $this->putJson("/api/v1/department-roles/{$id}/toggle")->assertOk()->assertJsonPath('data.status', 'inactive');
        $this->assertDatabaseHas('department_role_activity_log', ['role_assignment_id' => $id, 'action' => 'deactivated']);
        $this->putJson("/api/v1/department-roles/{$id}/toggle")->assertOk()->assertJsonPath('data.status', 'active');

        $this->deleteJson("/api/v1/department-roles/{$id}")->assertNoContent();
        $this->assertSame(0, DepartmentRoleAssignment::count());

        Sanctum::actingAs(User::factory()->create(['role' => 'editor']));
        $this->getJson('/api/v1/department-roles')->assertForbidden();
    }

    public function test_admin_broadcast_reaches_every_staff_member(): void
    {
        Notification::fake();
        User::factory()->count(2)->create();
        $admin = $this->admin();
        Sanctum::actingAs($admin);

        $this->getJson('/api/v1/admin-broadcast')->assertOk()->assertJsonPath('data.recipient_count', 3);
        $this->postJson('/api/v1/admin-broadcast', ['title' => ''])->assertJsonValidationErrors(['title', 'body']);
        $this->postJson('/api/v1/admin-broadcast', ['title' => 'اجتماع', 'body' => 'غداً الساعة 9'])
            ->assertOk()->assertJsonPath('data.sent', 3);
        Notification::assertSentTo($admin, AdminBroadcast::class);

        Sanctum::actingAs(User::factory()->create(['role' => 'editor']));
        $this->postJson('/api/v1/admin-broadcast', ['title' => 'x', 'body' => 'y'])->assertForbidden();
    }

    public function test_a_backup_file_downloads_and_names_outside_the_folder_do_not(): void
    {
        $dir = sys_get_temp_dir().'/backup-api-test-'.uniqid();
        File::ensureDirectoryExists($dir);
        File::put($dir.'/backup_1.sql', 'dump-bytes');
        config(['backup.path' => $dir]);

        try {
            Sanctum::actingAs($this->admin());
            $response = $this->get('/api/v1/backup/backup_1.sql/download')->assertOk();
            $this->assertStringContainsString('backup_1.sql', $response->headers->get('content-disposition'));
            $this->get('/api/v1/backup/missing.sql/download')->assertNotFound();
            $this->get('/api/v1/backup/passwd/download')->assertNotFound();

            Sanctum::actingAs(User::factory()->create(['role' => 'editor']));
            $this->get('/api/v1/backup/backup_1.sql/download')->assertForbidden();
            $this->getJson('/api/v1/backup')->assertForbidden();
        } finally {
            File::deleteDirectory($dir);
        }
    }

    public function test_the_app_chooses_which_academic_year_it_views(): void
    {
        $current = AcademicSession::create(['name' => '2025-2026', 'start_date' => '2025-09-01', 'end_date' => '2026-06-30', 'is_active' => true, 'is_current' => true]);
        $old = AcademicSession::create(['name' => '2024-2025', 'start_date' => '2024-09-01', 'end_date' => '2025-06-30', 'is_active' => true, 'is_current' => false]);
        $off = AcademicSession::create(['name' => '2023-2024', 'start_date' => '2023-09-01', 'end_date' => '2024-06-30', 'is_active' => false, 'is_current' => false]);
        Sanctum::actingAs($this->admin());

        $this->postJson('/api/v1/academic-sessions/select', ['academic_session_id' => $old->id])
            ->assertOk()->assertJsonPath('id', $old->id);
        $this->postJson('/api/v1/academic-sessions/select', ['academic_session_id' => $off->id])->assertStatus(422);
        $this->postJson('/api/v1/academic-sessions/select', ['academic_session_id' => 999])->assertJsonValidationErrors('academic_session_id');

        $this->getJson('/api/v1/academic-sessions/current')->assertJsonPath('id', $current->id);
        $this->getJson('/api/v1/academic-sessions/current', ['X-Academic-Session' => (string) $old->id])->assertJsonPath('id', $old->id);
        // An inactive or unknown choice falls back to the current year.
        $this->getJson('/api/v1/academic-sessions/current', ['X-Academic-Session' => (string) $off->id])->assertJsonPath('id', $current->id);
        $this->getJson('/api/v1/academic-sessions/current', ['X-Academic-Session' => 'abc'])->assertJsonPath('id', $current->id);

        // Doctors choose too, as on the web's doctor switcher.
        EducationType::create(['id' => 1, 'name' => 'صباحي']);
        Stage::create(['id' => 1, 'name' => 'الرابعة', 'education_type_id' => 1]);
        $doctor = Doctor::create([
            'name' => 'د. علي', 'username' => 'ali', 'password' => 'secret', 'email' => 'ali@example.com',
            'education_type_id' => 1, 'stage_id' => 1,
        ]);
        Sanctum::actingAs($doctor);
        $this->postJson('/api/v1/academic-sessions/select', ['academic_session_id' => $old->id])->assertOk();
    }
}
