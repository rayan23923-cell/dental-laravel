<?php

namespace Tests\Feature;

use App\Models\ClinicSetting;
use App\Models\PatientRegistration;
use App\Models\Payment;
use App\Models\User;
use App\Models\UserPermission;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * The app's lab list, payments report and registrations archive
 * (2026-10-17) — the API twins of the web /lab page, payments.report and
 * the registry's destroy-many / restore-many.
 */
class ApiLabPaymentsReportAndArchiveTest extends TestCase
{
    use RefreshDatabase;

    private function admin(): User
    {
        return User::factory()->create(['role' => 'super_admin']);
    }

    /** A `lab` desk user with only the given patient_screening grants. */
    private function labUser(array $permissions = ['view', 'confirm']): User
    {
        $user = User::factory()->create(['role' => 'lab']);
        foreach ($permissions as $p) {
            UserPermission::create(['user_id' => $user->id, 'module' => 'patient_screening', 'permission' => $p, 'granted' => true]);
        }

        return $user;
    }

    private function registration(array $attrs = []): PatientRegistration
    {
        $id = DB::table('patients_simple')->insertGetId(array_merge([
            'name' => 'Patient', 'phone' => '0770', 'screening_status' => 'pending', 'created_at' => now(),
        ], $attrs));

        return PatientRegistration::findOrFail($id);
    }

    public function test_lab_list_filters_by_status_and_search_and_marks_paid(): void
    {
        ClinicSetting::current(); // first call creates the row
        ClinicSetting::current()->update(['lab_fee' => 5000]);
        $ali = $this->registration(['name' => 'Ali', 'phone' => '0771']);
        $this->registration(['name' => 'Sara', 'phone' => '0772']);
        $this->registration(['name' => 'Omar', 'phone' => '0773', 'screening_status' => 'clear', 'screening_checked_at' => now()]);
        Payment::create(['patient_registration_id' => $ali->id, 'amount' => 5000, 'paid_at' => now(), 'type' => 'lab']);
        Sanctum::actingAs($this->labUser());

        $res = $this->getJson('/api/v1/lab')->assertOk()
            ->assertJsonCount(2, 'data')
            ->assertJsonPath('meta.counts.pending', 2)
            ->assertJsonPath('meta.counts.clear', 1)
            ->assertJsonPath('meta.lab_fee', 5000)
            ->assertJsonPath('meta.can_confirm', true);
        $paid = collect($res->json('data'))->firstWhere('name', 'Ali');
        $this->assertTrue($paid['lab_paid']);

        $this->getJson('/api/v1/lab?status=all')->assertOk()->assertJsonCount(3, 'data');
        $this->getJson('/api/v1/lab?status=clear')->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.name', 'Omar');
        $this->getJson('/api/v1/lab?status=all&search=0772')->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.name', 'Sara');
    }

    public function test_lab_list_flags_an_earlier_valid_result(): void
    {
        ClinicSetting::current(); // first call creates the row
        ClinicSetting::current()->update(['lab_validity_days' => 30]);
        $this->registration(['name' => 'Ali', 'phone' => '0771', 'screening_status' => 'clear', 'screening_checked_at' => now()->subDays(3)]);
        $again = $this->registration(['name' => 'Ali', 'phone' => '0771']);
        Sanctum::actingAs($this->labUser());

        $this->getJson('/api/v1/lab')->assertOk()
            ->assertJsonPath('data.0.id', $again->id)
            ->assertJsonPath('data.0.previous_screening.matched_by', 'name');
    }

    public function test_lab_scan_show_and_qr_need_only_a_screening_permission(): void
    {
        $ali = $this->registration(['name' => 'Ali']);
        Sanctum::actingAs($this->labUser(['view']));

        $this->postJson('/api/v1/lab/scan', ['payload' => json_encode(['type' => 'patient_registration', 'id' => $ali->id])])
            ->assertOk()->assertJsonPath('data.registration.name', 'Ali');
        $this->postJson('/api/v1/lab/scan', ['payload' => 'nope'])->assertStatus(422);
        $this->getJson("/api/v1/lab/{$ali->id}")->assertOk()
            ->assertJsonPath('data.registration.id', $ali->id)
            ->assertJsonPath('data.lab_paid', false);
        $this->get("/api/v1/lab/{$ali->id}/qr")->assertOk()->assertHeader('Content-Type', 'image/png');
        $this->getJson('/api/v1/lab')->assertOk()->assertJsonPath('meta.can_confirm', false);

        // The registry itself stays closed to the lab role.
        $this->getJson('/api/v1/patient-registrations')->assertForbidden();
    }

    public function test_lab_is_closed_without_a_screening_permission(): void
    {
        $ali = $this->registration();
        Sanctum::actingAs(User::factory()->create(['role' => 'reception']));

        $this->getJson('/api/v1/lab')->assertForbidden();
        $this->getJson("/api/v1/lab/{$ali->id}")->assertForbidden();
        $this->postJson('/api/v1/lab/scan', ['payload' => '{}'])->assertForbidden();
    }

    public function test_payments_report_lists_every_filtered_payment_with_its_service(): void
    {
        $serviceId = DB::table('register_services')->insertGetId(['name' => 'Filling', 'price' => 25000]);
        $ali = $this->registration(['name' => 'Ali', 'service_id' => $serviceId]);
        for ($i = 0; $i < 18; $i++) {
            Payment::create(['patient_registration_id' => $ali->id, 'amount' => 1000, 'paid_at' => now(), 'type' => 'service']);
        }
        Payment::create(['patient_registration_id' => $ali->id, 'amount' => 5000, 'paid_at' => now(), 'type' => 'lab']);
        Sanctum::actingAs($this->admin());

        $this->getJson('/api/v1/payments/report')->assertOk()
            ->assertJsonCount(19, 'data.payments')
            ->assertJsonPath('data.filtered_total', 23000)
            ->assertJsonPath('data.payments.0.patient_registration.service_name', 'Filling')
            ->assertJsonCount(30, 'data.daily');

        $this->getJson('/api/v1/payments/report?source=lab')->assertOk()
            ->assertJsonCount(1, 'data.payments')
            ->assertJsonPath('data.payments.0.type', 'lab')
            ->assertJsonPath('data.filtered_total', 5000);

        // The list itself doesn't carry the service.
        $this->getJson('/api/v1/payments')->assertOk()
            ->assertJsonMissingPath('data.0.patient_registration.service_name');
    }

    public function test_bulk_archive_restore_and_the_archive_tab(): void
    {
        $ali = $this->registration(['name' => 'Ali']);
        $sara = $this->registration(['name' => 'Sara']);
        $omar = $this->registration(['name' => 'Omar']);
        Payment::create(['patient_registration_id' => $ali->id, 'amount' => 1000, 'paid_at' => now(), 'type' => 'service']);
        Sanctum::actingAs($this->admin());

        $this->getJson('/api/v1/patient-registrations')->assertOk()->assertJsonPath('can.archive', true);

        $this->deleteJson('/api/v1/patient-registrations-bulk', ['ids' => [$ali->id, $sara->id]])
            ->assertOk()->assertJsonPath('count', 2);
        $this->assertSoftDeleted('patients_simple', ['id' => $ali->id]);
        $this->assertDatabaseHas('payments', ['patient_registration_id' => $ali->id]);

        $this->getJson('/api/v1/patient-registrations')->assertOk()->assertJsonCount(1, 'data');
        $this->getJson('/api/v1/patient-registrations?archived=1')->assertOk()->assertJsonCount(2, 'data');
        $this->getJson('/api/v1/patient-registrations?archived=1&search=Sara')->assertOk()
            ->assertJsonCount(1, 'data')->assertJsonPath('data.0.name', 'Sara');

        $this->postJson('/api/v1/patient-registrations-restore', ['ids' => [$sara->id]])
            ->assertOk()->assertJsonPath('count', 1);
        $this->assertNotSoftDeleted('patients_simple', ['id' => $sara->id]);

        // "Archive all" takes the filters, as on the web.
        $this->deleteJson('/api/v1/patient-registrations-bulk', ['all' => true, 'search' => 'Omar'])
            ->assertOk()->assertJsonPath('count', 1);
        $this->assertSoftDeleted('patients_simple', ['id' => $omar->id]);
        $this->assertNotSoftDeleted('patients_simple', ['id' => $sara->id]);
    }

    public function test_bulk_archive_needs_the_delete_permission(): void
    {
        $ali = $this->registration();
        $user = User::factory()->create(['role' => 'editor']);
        UserPermission::create(['user_id' => $user->id, 'module' => 'patients', 'permission' => 'view', 'granted' => true]);
        Sanctum::actingAs($user);

        $this->getJson('/api/v1/patient-registrations')->assertOk()->assertJsonPath('can.archive', false);
        $this->deleteJson('/api/v1/patient-registrations-bulk', ['ids' => [$ali->id]])->assertForbidden();
        $this->postJson('/api/v1/patient-registrations-restore', ['ids' => [$ali->id]])->assertForbidden();
        $this->assertNotSoftDeleted('patients_simple', ['id' => $ali->id]);
    }
}
