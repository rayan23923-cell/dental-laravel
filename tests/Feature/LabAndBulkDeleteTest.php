<?php

namespace Tests\Feature;

use App\Models\PatientRegistration;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class LabAndBulkDeleteTest extends TestCase
{
    use RefreshDatabase;

    private function admin(): User
    {
        return User::factory()->create(['role' => 'super_admin']);
    }

    private function registration(array $attrs = []): PatientRegistration
    {
        $id = DB::table('patients_simple')->insertGetId(array_merge([
            'name' => 'Patient', 'phone' => '0770', 'screening_status' => 'pending', 'created_at' => now(),
        ], $attrs));

        return PatientRegistration::findOrFail($id);
    }

    public function test_lab_page_lists_pending_and_scan_works(): void
    {
        $a = $this->registration(['name' => 'Ali']);
        $this->registration(['name' => 'Sara', 'screening_status' => 'clear']);
        $admin = $this->admin();

        $this->actingAs($admin)->get('/lab')->assertOk()
            ->assertInertia(fn ($p) => $p->component('Lab/Index')->has('registrations.data', 1)->where('canConfirm', true));

        $this->actingAs($admin)->postJson('/lab/scan', ['payload' => json_encode(['type' => 'patient_registration', 'id' => $a->id])])
            ->assertOk()->assertJsonPath('data.name', 'Ali');
    }

    public function test_lab_result_prints_with_qr(): void
    {
        $a = $this->registration(['name' => 'Ali', 'screening_status' => 'flagged', 'screening_checked_at' => now()]);

        $this->actingAs($this->admin())->get("/lab/{$a->id}/print?autoprint=1")
            ->assertOk()->assertSee('غير سليم')->assertSee('غير مدفوع')->assertSee('data:image/png;base64', false)->assertSee('window.print()', false);
    }

    public function test_lab_fee_payment_skips_screening_gate_and_prints_receipt(): void
    {
        \App\Models\ClinicSetting::current(); // first call creates the row
        \App\Models\ClinicSetting::current()->update(['lab_fee' => 5000]);
        $a = $this->registration(['name' => 'Ali']);
        $admin = $this->admin();

        $res = $this->actingAs($admin)->postJson('/payments/lab', ['patient_registration_id' => $a->id]);
        $res->assertCreated();
        $this->assertDatabaseHas('payments', ['patient_registration_id' => $a->id, 'type' => 'lab', 'amount' => 5000]);

        $this->actingAs($admin)->postJson('/payments/lab', ['patient_registration_id' => $a->id])->assertStatus(422);

        $this->actingAs($admin)->get(parse_url($res->json('data.receipt_url'), PHP_URL_PATH).'?autoprint=1')
            ->assertOk()->assertSee('تم دفع أجور المختبر')->assertSee('5,000');

        $scan = $this->actingAs($admin)->postJson('/patient-registrations/scan', ['payload' => json_encode(['type' => 'patient_registration', 'id' => $a->id])])
            ->assertOk();
        $this->assertTrue($scan->json('data.lab_paid'));
        $this->assertFalse($scan->json('data.is_paid'));

        // Service payment is still blocked until screening is clear.
        $this->actingAs($admin)->post('/payments', ['patient_registration_id' => $a->id, 'amount' => 1000])->assertSessionHas('error');

        $this->actingAs($admin)->get('/lab')->assertInertia(fn ($p) => $p->where('registrations.data.0.lab_paid', true));
    }

    public function test_lab_result_needs_lab_fee_paid_first(): void
    {
        \App\Models\ClinicSetting::current(); // first call creates the row
        \App\Models\ClinicSetting::current()->update(['lab_fee' => 5000]);
        $a = $this->registration(['name' => 'Ali']);
        $admin = $this->admin();

        $this->actingAs($admin)->postJson("/patient-registrations/{$a->id}/screening", ['screening_status' => 'clear'])
            ->assertStatus(422);
        $this->actingAs($admin)->postJson("/api/v1/patient-registrations/{$a->id}/screening", ['screening_status' => 'clear'])
            ->assertStatus(422);
        $this->assertSame('pending', $a->fresh()->screening_status);

        $this->actingAs($admin)->postJson('/payments/lab', ['patient_registration_id' => $a->id])->assertCreated();

        $this->actingAs($admin)->postJson("/patient-registrations/{$a->id}/screening", ['screening_status' => 'clear'])
            ->assertOk();
        $this->assertSame('clear', $a->fresh()->screening_status);
    }

    public function test_lab_result_allowed_when_no_lab_fee_set(): void
    {
        $a = $this->registration(['name' => 'Ali']);

        $this->actingAs($this->admin())->postJson("/patient-registrations/{$a->id}/screening", ['screening_status' => 'flagged'])
            ->assertOk();
    }

    public function test_registration_records_amount_paid(): void
    {
        $day = DB::table('register_days')->insertGetId(['name' => 'Sat']);
        $service = DB::table('register_services')->insertGetId(['name' => 'Check']);
        DB::table(\App\Models\Service::make()->days()->getTable())->insert([
            \App\Models\Service::make()->days()->getForeignPivotKeyName() => $service,
            \App\Models\Service::make()->days()->getRelatedPivotKeyName() => $day,
        ]);
        $admin = $this->admin();

        $this->actingAs($admin)->post('/patient-registrations', [
            'name' => 'Ali', 'phone' => '0770', 'register_day_id' => $day, 'service_id' => $service, 'amount_paid' => 15000,
        ])->assertRedirect();
        $ali = PatientRegistration::where('name', 'Ali')->firstOrFail();
        $this->assertDatabaseHas('payments', ['patient_registration_id' => $ali->id, 'amount' => 15000, 'type' => 'service']);

        $this->actingAs($admin)->postJson('/api/v1/patient-registrations', [
            'name' => 'Sara', 'phone' => '0771', 'register_day_id' => $day, 'service_id' => $service, 'amount_paid' => 7000,
        ])->assertCreated();
        $sara = PatientRegistration::where('name', 'Sara')->firstOrFail();
        $this->assertDatabaseHas('payments', ['patient_registration_id' => $sara->id, 'amount' => 7000]);

        $this->actingAs($admin)->postJson('/api/v1/patient-registrations', [
            'name' => 'Omar', 'phone' => '0772', 'register_day_id' => $day, 'service_id' => $service,
        ])->assertCreated();
        $this->assertSame(2, \App\Models\Payment::count());
    }

    public function test_bulk_delete_selected_and_all(): void
    {
        $a = $this->registration(['name' => 'Ali']);
        $b = $this->registration(['name' => 'Bob']);
        $c = $this->registration(['name' => 'Ali2']);
        $admin = $this->admin();

        $this->actingAs($admin)->delete('/patient-registrations-bulk', ['ids' => [$b->id]])->assertRedirect();
        $this->assertDatabaseMissing('patients_simple', ['id' => $b->id]);

        $this->actingAs($admin)->delete('/patient-registrations-bulk', ['all' => true, 'search' => 'Ali'])->assertRedirect();
        $this->assertSame(0, PatientRegistration::count());
    }
}
