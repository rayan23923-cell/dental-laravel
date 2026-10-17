<?php

namespace Tests\Feature;

use App\Models\ClinicSetting;
use App\Models\Department;
use App\Models\Doctor;
use App\Models\EducationType;
use App\Models\Stage;
use App\Models\Task;
use App\Models\TaskInstance;
use App\Support\TaskScoring;
use App\Models\Payment;
use App\Models\PatientRegistration;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/** What the app needs to match the web lab and payments pages (2026-10-17). */
class AppParityApiTest extends TestCase
{
    use RefreshDatabase;

    private function registration(array $attrs = []): PatientRegistration
    {
        $id = DB::table('patients_simple')->insertGetId(array_merge([
            'name' => 'Patient', 'phone' => '0770', 'screening_status' => 'pending', 'created_at' => now(),
        ], $attrs));

        return PatientRegistration::findOrFail($id);
    }

    private function scan(PatientRegistration $r)
    {
        return $this->postJson('/api/v1/patient-registrations/scan', ['payload' => json_encode(['type' => 'patient_registration', 'id' => $r->id])]);
    }

    public function test_scanning_a_screened_ticket_shows_who_recorded_it_and_any_reused_test(): void
    {
        ClinicSetting::current()->update(['lab_validity_days' => 90]);
        $admin = User::factory()->create(['role' => 'super_admin', 'full_name' => 'Lab Tech']);
        Sanctum::actingAs($admin);

        $old = $this->registration(['name' => 'Ali', 'phone' => '0772', 'screening_status' => 'clear', 'screening_checked_at' => now()->subDays(10)]);
        $new = $this->registration(['name' => 'Ali', 'phone' => '0772']);

        $this->scan($new)->assertOk()
            ->assertJsonPath('data.previous_screening.id', $old->id)
            ->assertJsonPath('data.screening_checked_at', null)
            ->assertJsonPath('data.reused_from', null);

        $this->postJson("/api/v1/patient-registrations/{$new->id}/screening/reuse")->assertOk();

        $this->scan($new)->assertOk()
            ->assertJsonPath('data.registration.screening_status', 'clear')
            ->assertJsonPath('data.screening_checked_by', 'Lab Tech')
            ->assertJsonPath('data.reused_from.id', $old->id)
            ->assertJsonPath('data.previous_screening', null)
            ->assertJson(fn ($json) => $json->whereNot('data.screening_checked_at', null)->etc());
    }

    public function test_payment_stats_match_the_web_overview_and_filters(): void
    {
        Sanctum::actingAs(User::factory()->create(['role' => 'super_admin']));
        $r = $this->registration(['screening_status' => 'clear']);
        Payment::create(['patient_registration_id' => $r->id, 'amount' => 5000, 'paid_at' => now(), 'type' => 'service']);
        Payment::create(['patient_registration_id' => $r->id, 'amount' => 3000, 'paid_at' => now(), 'type' => Payment::TYPE_LAB]);
        Payment::create(['patient_registration_id' => $r->id, 'amount' => 1000, 'paid_at' => now()->subYears(2), 'type' => 'service']);

        $res = $this->getJson('/api/v1/payments/stats')->assertOk()
            ->assertJsonPath('data.periods.today.total', 8000)
            ->assertJsonPath('data.periods.today.count', 2)
            ->assertJsonPath('data.filtered_total', 9000)
            ->assertJsonCount(30, 'data.daily')
            ->assertJsonCount(12, 'data.monthly');
        $bySource = collect($res->json('data.by_source'))->keyBy('source');
        $this->assertEquals(6000, $bySource['registration']['total']);
        $this->assertEquals(3000, $bySource['lab']['total']);

        $this->getJson('/api/v1/payments/stats?source=lab')->assertJsonPath('data.filtered_total', 3000);
        $this->getJson('/api/v1/payments?source=lab')->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.type', 'lab');
        // The resource route still answers for a real id.
        $this->getJson('/api/v1/payments/'.Payment::first()->id)->assertOk();
    }

    public function test_the_app_records_a_cases_work_and_reads_its_points_on_the_case_sheet(): void
    {
        EducationType::create(['id' => 1, 'name' => 'صباحي']);
        Stage::create(['id' => 1, 'name' => 'الرابعة', 'education_type_id' => 1]);
        $department = Department::create(['name' => 'اللثة', 'stage_id' => 1, 'education_type_id' => 1]);
        $sheet = DB::table('case_sheet_types')->where('type_code', 'periodontal')->value('id')
            ?? DB::table('case_sheet_types')->insertGetId(['type_code' => 'periodontal', 'name_ar' => 'اللثة', 'name_en' => 'Periodontal', 'is_active' => 1]);
        $admin = User::factory()->create(['role' => 'super_admin']);
        $this->actingAs($admin)->post('/tasks', [
            'department_id' => $department->id, 'case_sheet_type_id' => $sheet, 'stage_id' => 1,
            'notes' => 'متطلبات', 'grade' => 10, 'rows' => array_map(fn ($r) => ['enabled' => true] + $r, TaskScoring::templatesByTypeId()[$sheet]['rows']),
        ])->assertSessionHasNoErrors();
        auth()->logout();

        $doctor = Doctor::create([
            'name' => 'د. مريم', 'username' => 'maryam', 'password' => 'secret', 'email' => 'm@example.com',
            'education_type_id' => 1, 'stage_id' => 1,
        ]);
        $graded = TaskInstance::create(['task_id' => Task::where('title', 'like', '%1000%')->value('id'), 'doctor_id' => $doctor->id, 'status' => 'assigned']);

        // Staff in the app: the case sheet's points panel, then completing with work.
        Sanctum::actingAs($admin);
        $this->getJson("/api/v1/case-sheets/instances/{$graded->id}/work")->assertOk()
            ->assertJsonPath('can_edit', true)->assertJsonPath('scoring.graded', true);
        $this->putJson("/api/v1/case-sheets/instances/{$graded->id}/work", ['work_items' => [['option' => 4, 'grade' => 30]]])
            ->assertOk()->assertJsonPath('points', 30);
        $this->putJson("/api/v1/task-progress/instances/{$graded->id}/complete", ['work_items' => [['option' => 4, 'grade' => 25]]])->assertOk();
        $this->assertEqualsWithDelta(25, $graded->fresh()->points, 0.01);

        // The doctor's own app sees the points but cannot change them.
        Sanctum::actingAs($doctor);
        $this->getJson("/api/v1/case-sheets/instances/{$graded->id}/work")->assertOk()->assertJsonPath('can_edit', false);
        $this->putJson("/api/v1/case-sheets/instances/{$graded->id}/work", ['work_items' => [['option' => 4, 'grade' => 40]]])->assertForbidden();
    }
}
