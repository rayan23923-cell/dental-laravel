<?php

namespace Tests\Feature;

use App\Models\CasePatientLink;
use App\Models\ClinicSetting;
use App\Models\Department;
use App\Models\Doctor;
use App\Models\PatientRegistration;
use App\Models\Payment;
use App\Models\Task;
use App\Models\TaskInstance;
use App\Models\TaskStartRequest;
use App\Models\User;
use App\Support\CasePatientLinks;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/** Linking a patient to a case sheet by QR or typed code (2026-11-04). */
class CasePatientLinkTest extends TestCase
{
    use RefreshDatabase;

    private Doctor $doctor;

    private Doctor $other;

    private Task $task;

    protected function setUp(): void
    {
        parent::setUp();
        DB::statement('SET FOREIGN_KEY_CHECKS=0');
        $department = Department::create(['name' => 'الحشوات']);
        $this->doctor = Doctor::create([
            'name' => 'د. علي', 'username' => 'ali', 'password' => 'secret', 'email' => 'ali@example.com',
            'education_type_id' => 1, 'stage_id' => 1,
        ]);
        $this->other = Doctor::create([
            'name' => 'د. سارة', 'username' => 'sara', 'password' => 'secret', 'email' => 'sara@example.com',
            'education_type_id' => 1, 'stage_id' => 1,
        ]);
        $this->task = Task::create([
            'department_id' => $department->id, 'case_sheet_type_id' => 1, 'stage_id' => 1,
            'title' => 'حشوة', 'required_per_doctor' => 2, 'required_count' => 2,
        ]);
        DB::statement('SET FOREIGN_KEY_CHECKS=1');
    }

    private function patient(string $status = 'clear'): PatientRegistration
    {
        return PatientRegistration::create(['name' => 'مريض '.$status, 'phone' => '0770'.random_int(1000000, 9999999), 'screening_status' => $status]);
    }

    public function test_every_registration_gets_a_six_digit_code(): void
    {
        $a = $this->patient();
        $b = $this->patient();
        $this->assertMatchesRegularExpression('/^\d{6}$/', $a->patient_code);
        $this->assertNotSame($a->patient_code, $b->patient_code);
    }

    public function test_a_doctor_links_by_typed_code_and_the_receipt_cannot_be_reused(): void
    {
        $patient = $this->patient();

        $this->actingAs($this->doctor, 'doctor')
            ->postJson(route('patient-registrations.scan-for-case-sheet'), ['code' => ' '.$patient->patient_code, 'task_id' => $this->task->id])
            ->assertOk()
            ->assertJsonPath('data.registration.name', $patient->name)
            ->assertJsonPath('data.link.method', 'code');

        $this->assertSame($this->doctor->id, (int) CasePatientLink::sole()->doctor_id);

        // Same case again: fine (re-scan).
        $this->postJson(route('patient-registrations.scan-for-case-sheet'), [
            'payload' => json_encode(['type' => 'patient_registration', 'id' => $patient->id]), 'task_id' => $this->task->id,
        ])->assertOk();

        // Another doctor can't use the same receipt.
        $this->actingAs($this->other, 'doctor')
            ->postJson(route('patient-registrations.scan-for-case-sheet'), ['code' => $patient->patient_code, 'task_id' => $this->task->id])
            ->assertStatus(422)
            ->assertJsonPath('message', fn ($m) => str_contains($m, 'مستخدم مسبقاً'));
        $this->assertSame(1, CasePatientLink::count());
    }

    public function test_flagged_or_untested_patients_cannot_be_linked_and_wrong_codes_fail(): void
    {
        $this->actingAs($this->doctor, 'doctor');
        $this->postJson(route('patient-registrations.scan-for-case-sheet'), ['code' => $this->patient('flagged')->patient_code, 'task_id' => $this->task->id])
            ->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'غير سليم'));
        $this->postJson(route('patient-registrations.scan-for-case-sheet'), ['code' => $this->patient('pending')->patient_code, 'task_id' => $this->task->id])
            ->assertStatus(422);
        $this->postJson(route('patient-registrations.scan-for-case-sheet'), ['code' => '000', 'task_id' => $this->task->id])
            ->assertStatus(422);
        $this->assertSame(0, CasePatientLink::count());
    }

    public function test_the_link_follows_the_draft_into_the_started_task_and_the_api_works_too(): void
    {
        $patient = $this->patient();
        $token = $this->doctor->createToken('t')->plainTextToken;
        $this->withToken($token)
            ->postJson('/api/v1/patient-registrations/scan-for-case-sheet', ['code' => $patient->patient_code, 'task_id' => $this->task->id])
            ->assertOk()->assertJsonPath('data.link.name', $patient->name);
        $this->withToken($token)->getJson('/api/v1/case-patient-link?task_id='.$this->task->id)
            ->assertOk()->assertJsonPath('data.patient_code', $patient->patient_code);

        $request = TaskStartRequest::create([
            'doctor_id' => $this->doctor->id, 'task_id' => $this->task->id, 'form_type' => 'electronic', 'status' => 'pending',
        ]);
        $this->app['auth']->forgetGuards();
        $this->actingAs(User::factory()->create(['role' => 'super_admin']))
            ->postJson(route('task-progress.requests.approve', $request))->assertOk();

        $instance = TaskInstance::where('doctor_id', $this->doctor->id)->where('status', 'assigned')->sole();
        $this->assertSame($patient->id, (int) $instance->patient_registration_id);
        $this->assertSame($instance->id, (int) CasePatientLink::sole()->task_instance_id);
    }

    public function test_required_linking_blocks_an_electronic_start_request_until_linked(): void
    {
        ClinicSetting::current()->update(['patient_link_required' => true]);

        $this->actingAs($this->doctor, 'doctor')
            ->post(route('doctor.task-start-requests.store'), ['task_id' => $this->task->id, 'form_type' => 'electronic'])
            ->assertStatus(302)->assertSessionHasErrors('task_id');
        $this->assertSame(0, TaskStartRequest::count());

        $this->postJson(route('patient-registrations.scan-for-case-sheet'), ['code' => $this->patient()->patient_code, 'task_id' => $this->task->id])->assertOk();
        $this->post(route('doctor.task-start-requests.store'), ['task_id' => $this->task->id, 'form_type' => 'electronic'])->assertCreated();
    }

    public function test_required_linking_blocks_saving_a_new_case_sheet(): void
    {
        ClinicSetting::current()->update(['patient_link_required' => true]);
        $data = ['doctor_id' => $this->doctor->id, 'task_id' => $this->task->id];

        try {
            CasePatientLinks::enforceOnCreate($data);
            $this->fail('expected a validation error');
        } catch (\Illuminate\Validation\ValidationException $e) {
            $this->assertArrayHasKey('patient_link', $e->errors());
        }

        CasePatientLinks::link($this->patient(), $this->doctor, $this->task->id, null, 'qr');
        CasePatientLinks::enforceOnCreate($data);
        $this->assertTrue(true);
    }

    public function test_payments_are_split_by_the_linked_department_with_lab_on_its_own(): void
    {
        $linked = $this->patient();
        $unlinked = $this->patient();
        CasePatientLinks::link($linked, $this->doctor, $this->task->id, null, 'code');
        Payment::create(['patient_registration_id' => $linked->id, 'amount' => 5000, 'paid_at' => now(), 'type' => Payment::TYPE_SERVICE]);
        Payment::create(['patient_registration_id' => $linked->id, 'amount' => 2000, 'paid_at' => now(), 'type' => Payment::TYPE_LAB]);
        Payment::create(['patient_registration_id' => $unlinked->id, 'amount' => 3000, 'paid_at' => now(), 'type' => Payment::TYPE_SERVICE]);

        $rows = collect(CasePatientLinks::departmentTotals(Payment::query()))->keyBy('key');
        $this->assertSame(5000.0, $rows['department:'.$this->task->department_id]['total']);
        $this->assertSame('الحشوات', $rows['department:'.$this->task->department_id]['name']);
        $this->assertSame(2000.0, $rows['lab']['total']);
        $this->assertSame(3000.0, $rows['unlinked']['total']);

        $this->actingAs(User::factory()->create(['role' => 'super_admin']))
            ->get(route('payments.index'))->assertOk()
            ->assertInertia(fn ($page) => $page->has('byDepartment', 3));
    }
}
