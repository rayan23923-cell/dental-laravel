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

    public function test_registration_charges_the_service_price(): void
    {
        $priced = DB::table('register_services')->insertGetId(['name' => 'Filling', 'price' => 25000]);
        $unpriced = DB::table('register_services')->insertGetId(['name' => 'Implant']);
        $admin = $this->admin();

        // An amount the client sends is ignored: the payment is the service's price.
        $this->actingAs($admin)->post('/patient-registrations', [
            'name' => 'Ali', 'phone' => '0770', 'service_id' => $priced, 'amount_paid' => 1,
        ])->assertRedirect();
        $ali = PatientRegistration::where('name', 'Ali')->firstOrFail();
        $this->assertDatabaseHas('payments', ['patient_registration_id' => $ali->id, 'amount' => 25000, 'type' => 'service']);

        $this->actingAs($admin)->postJson('/api/v1/patient-registrations', [
            'name' => 'Sara', 'phone' => '0771', 'service_id' => $priced,
        ])->assertCreated();
        $sara = PatientRegistration::where('name', 'Sara')->firstOrFail();
        $this->assertDatabaseHas('payments', ['patient_registration_id' => $sara->id, 'amount' => 25000, 'type' => 'service']);

        // A service with no price cannot be registered.
        $this->actingAs($admin)->postJson('/api/v1/patient-registrations', [
            'name' => 'Omar', 'phone' => '0772', 'service_id' => $unpriced,
        ])->assertUnprocessable()->assertJsonValidationErrors('service_id');
        $this->actingAs($admin)->post('/patient-registrations', [
            'name' => 'Omar', 'phone' => '0772', 'service_id' => $unpriced,
        ])->assertSessionHasErrors('service_id');
        $this->assertFalse(PatientRegistration::where('name', 'Omar')->exists());
        $this->assertSame(2, \App\Models\Payment::count());
    }

    public function test_bulk_delete_archives_selected_and_all(): void
    {
        $a = $this->registration(['name' => 'Ali']);
        $b = $this->registration(['name' => 'Bob']);
        $c = $this->registration(['name' => 'Ali2']);
        $admin = $this->admin();

        $this->actingAs($admin)->delete('/patient-registrations-bulk', ['ids' => [$b->id]])->assertRedirect();
        $this->assertSoftDeleted('patients_simple', ['id' => $b->id]);

        $this->actingAs($admin)->delete('/patient-registrations-bulk', ['all' => true, 'search' => 'Ali'])->assertRedirect();
        $this->assertSame(0, PatientRegistration::count());
    }

    public function test_registration_needs_only_name_phone_and_priced_service(): void
    {
        $admin = $this->admin();
        $this->actingAs($admin)->post('/register-services', ['name' => 'قلع اسنان', 'price' => 1000])->assertSessionHasNoErrors();
        $service = \App\Models\Service::where('name', 'قلع اسنان')->firstOrFail();
        $this->assertEquals(1000, (float) $service->price);

        $this->actingAs($admin)->get('/patient-registrations/create')
            ->assertInertia(fn ($p) => $p->component('PatientRegistrations/Create')->where('services.0.name', 'قلع اسنان'));

        $this->actingAs($admin)->post('/patient-registrations', [
            'name' => 'Ali', 'phone' => '0771', 'service_id' => $service->id, 'amount_paid' => 1000,
        ])->assertSessionHasNoErrors()->assertRedirect();

        $reg = PatientRegistration::where('phone', '0771')->firstOrFail();
        $this->assertNull($reg->register_day_id);
        $this->assertDatabaseHas('payments', ['patient_registration_id' => $reg->id, 'amount' => 1000, 'type' => 'service']);

        $this->actingAs($admin)->put('/register-settings/lab', ['lab_fee' => 2000, 'lab_validity_days' => 90])->assertSessionHasNoErrors();
        $this->assertEquals(90, \App\Models\ClinicSetting::current()->lab_validity_days);
    }

    public function test_lab_reuses_a_recent_clear_result_without_payment(): void
    {
        \App\Models\ClinicSetting::current();
        \App\Models\ClinicSetting::current()->update(['lab_fee' => 5000, 'lab_validity_days' => 90]);
        $old = $this->registration(['name' => 'Ali', 'phone' => '0772', 'screening_status' => 'clear', 'screening_checked_at' => now()->subDays(30)]);
        $new = $this->registration(['name' => 'Ali', 'phone' => '0772']);
        $stale = $this->registration(['name' => 'Sara', 'phone' => '0773', 'screening_status' => 'clear', 'screening_checked_at' => now()->subDays(120)]);
        $other = $this->registration(['name' => 'Sara', 'phone' => '0773']);
        $admin = $this->admin();

        $this->actingAs($admin)->get('/lab')->assertInertia(fn ($p) => $p
            ->where('registrations.data', fn ($rows) => collect($rows)->firstWhere('id', $new->id)['previous_screening']['id'] === $old->id
                && collect($rows)->firstWhere('id', $other->id)['previous_screening'] === null));

        // Still unpaid, but a valid earlier result means no payment is needed.
        $this->actingAs($admin)->postJson("/lab/{$new->id}/reuse")->assertOk()->assertJsonPath('data.screening_status', 'clear');
        $this->assertEquals($old->id, $new->fresh()->screening_reused_from);
        $this->assertDatabaseMissing('payments', ['patient_registration_id' => $new->id]);

        $this->actingAs($admin)->get("/lab/{$new->id}/print")->assertOk()->assertSee('معفى');

        // Older than the validity window: screen and pay as usual.
        $this->actingAs($admin)->postJson("/lab/{$other->id}/reuse")->assertStatus(422);
        $this->actingAs($admin)->postJson("/patient-registrations/{$other->id}/screening", ['screening_status' => 'clear'])->assertStatus(422);

        // A reused result does not extend the window for the next visit.
        $old->update(['screening_checked_at' => now()->subDays(100)]);
        $third = $this->registration(['name' => 'Ali', 'phone' => '0772']);
        $this->actingAs($admin)->postJson("/lab/{$third->id}/reuse")->assertStatus(422);
    }

    public function test_api_offers_and_reuses_previous_screening(): void
    {
        \App\Models\ClinicSetting::current();
        \App\Models\ClinicSetting::current()->update(['lab_fee' => 5000, 'lab_validity_days' => 90]);
        $old = $this->registration(['phone' => '0774', 'screening_status' => 'clear', 'screening_checked_at' => now()->subDays(10)]);
        $new = $this->registration(['phone' => '0774']);
        \Laravel\Sanctum\Sanctum::actingAs($this->admin());

        $this->postJson('/api/v1/patient-registrations/scan', ['payload' => json_encode(['type' => 'patient_registration', 'id' => $new->id])])
            ->assertOk()->assertJsonPath('data.previous_screening.id', $old->id)->assertJsonPath('data.lab_validity_days', 90);

        $this->postJson("/api/v1/patient-registrations/{$new->id}/screening/reuse")
            ->assertOk()->assertJsonPath('data.registration.screening_status', 'clear')
            ->assertJsonPath('data.registration.screening_reused_from', $old->id)
            ->assertJsonPath('data.previous_screening', null);

        $service = \App\Models\Service::create(['name' => 'تنظيف', 'price' => 2000]);
        $this->postJson('/api/v1/patient-registrations', ['name' => 'X', 'phone' => '0775', 'service_id' => $service->id])
            ->assertCreated()->assertJsonPath('data.service.price', 2000);
    }
}
