<?php

namespace Tests\Feature;

use App\Models\ClinicSetting;
use App\Models\LabService;
use App\Models\PatientRegistration;
use App\Models\Payment;
use App\Models\User;
use App\Models\UserPermission;
use App\Support\RolePresets;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * The lab's own priced services and test-only patients (2026-11-17, by
 * request): the lab adds «فحص المختبر» for 2,000, registers a patient who
 * came for the test only, and the price lands in the lab payments.
 */
class LabServicesTest extends TestCase
{
    use RefreshDatabase;

    private function labUser(): User
    {
        $user = User::factory()->create(['role' => 'lab']);
        RolePresets::apply($user);

        return $user;
    }

    private function receptionUser(): User
    {
        $user = User::factory()->create(['role' => 'reception']);
        RolePresets::apply($user);

        return $user;
    }

    public function test_the_lab_preset_grants_the_lab_services(): void
    {
        $user = $this->labUser();

        foreach (['view', 'manage', 'register'] as $permission) {
            $this->assertTrue(UserPermission::where(['user_id' => $user->id, 'module' => 'lab_services', 'permission' => $permission, 'granted' => true])->exists());
        }
    }

    public function test_the_lab_adds_prices_edits_and_deletes_its_services(): void
    {
        $this->actingAs($this->labUser());

        $this->postJson(route('lab.services.store'), ['name' => 'فحص المختبر', 'price' => 2000])
            ->assertCreated()
            ->assertJsonPath('data.0.name', 'فحص المختبر')
            ->assertJsonPath('data.0.price', 2000)
            ->assertJsonPath('data.0.active', true);
        $service = LabService::firstOrFail();

        $this->postJson(route('lab.services.store'), ['name' => 'فحص المختبر', 'price' => 1])->assertUnprocessable();

        $this->putJson(route('lab.services.update', $service), ['name' => 'فحص الدم', 'price' => 2500])
            ->assertOk()->assertJsonPath('data.0.name', 'فحص الدم')->assertJsonPath('data.0.price', 2500);

        $this->deleteJson(route('lab.services.destroy', $service))->assertOk()->assertJsonCount(0, 'data');
        $this->assertDatabaseMissing('lab_services', ['id' => $service->id]);
    }

    public function test_a_service_with_patients_is_switched_off_instead_of_deleted(): void
    {
        $this->actingAs($this->labUser());
        $service = LabService::create(['name' => 'فحص المختبر', 'price' => 2000]);
        $this->postJson(route('lab.register'), ['name' => 'Ali', 'phone' => '0771', 'lab_service_id' => $service->id])->assertCreated();

        $this->deleteJson(route('lab.services.destroy', $service))->assertOk()->assertJsonPath('data.0.active', false);
        $this->assertDatabaseHas('lab_services', ['id' => $service->id, 'active' => false]);

        // A switched-off service is no longer offered.
        $this->postJson(route('lab.register'), ['name' => 'Sara', 'phone' => '0772', 'lab_service_id' => $service->id])
            ->assertUnprocessable();
    }

    public function test_reception_cannot_manage_or_register(): void
    {
        $service = LabService::create(['name' => 'فحص المختبر', 'price' => 2000]);
        $this->actingAs($this->receptionUser());

        $this->postJson(route('lab.services.store'), ['name' => 'X', 'price' => 1])->assertForbidden();
        $this->postJson(route('lab.register'), ['name' => 'Ali', 'phone' => '0771', 'lab_service_id' => $service->id])->assertForbidden();
    }

    public function test_paid_at_registration_lands_in_the_lab_payments(): void
    {
        ClinicSetting::current()->update(['lab_fee' => 10000]);
        $service = LabService::create(['name' => 'فحص المختبر', 'price' => 2000]);
        $this->actingAs($this->labUser());

        $res = $this->postJson(route('lab.register'), [
            'name' => 'Ali', 'phone' => '0771', 'age' => 30, 'lab_service_id' => $service->id, 'paid' => true,
        ])->assertCreated();

        $registration = PatientRegistration::where('name', 'Ali')->firstOrFail();
        $this->assertSame($service->id, (int) $registration->lab_service_id);
        $this->assertNull($registration->service_id);
        $this->assertSame('pending', $registration->screening_status);
        $this->assertNotNull($res->json('receipt_url'));
        $res->assertJsonPath('data.lab_paid', true);

        // The service's price, not the clinic's lab fee.
        $payment = Payment::where('patient_registration_id', $registration->id)->sole();
        $this->assertSame(Payment::TYPE_LAB, $payment->type);
        $this->assertEquals(2000, (float) $payment->amount);
        $this->assertEquals(2000, (float) $payment->full_amount);

        // Recording the result charges nothing more.
        $this->postJson(route('patient-registrations.screening', $registration), ['screening_status' => 'clear']);
        $this->assertSame(1, Payment::where('patient_registration_id', $registration->id)->count());
        $this->assertSame('clear', $registration->fresh()->screening_status);
    }

    public function test_unpaid_at_registration_is_charged_with_the_result(): void
    {
        $service = LabService::create(['name' => 'فحص المختبر', 'price' => 2000]);
        $this->actingAs($this->labUser());

        $this->postJson(route('lab.register'), ['name' => 'Ali', 'phone' => '0771', 'lab_service_id' => $service->id, 'paid' => false])
            ->assertCreated()
            ->assertJsonPath('data.lab_paid', false)
            ->assertJsonPath('data.lab_fee_due', 2000)
            ->assertJsonPath('receipt_url', null);
        $registration = PatientRegistration::where('name', 'Ali')->firstOrFail();
        $this->assertSame(0, Payment::where('patient_registration_id', $registration->id)->count());

        // No clinic lab fee is set, yet the service's price is taken.
        $this->postJson(route('patient-registrations.screening', $registration), ['screening_status' => 'clear']);
        $this->assertEquals(2000, (float) Payment::where('patient_registration_id', $registration->id)->where('type', Payment::TYPE_LAB)->sum('amount'));
    }

    public function test_a_test_only_patient_shows_in_the_lab_but_not_the_reception_list(): void
    {
        $service = LabService::create(['name' => 'فحص المختبر', 'price' => 2000]);
        $this->actingAs($this->labUser());
        $this->postJson(route('lab.register'), ['name' => 'Walkin', 'phone' => '0771', 'lab_service_id' => $service->id])->assertCreated();

        $this->get(route('lab.index'))->assertOk()
            ->assertInertia(fn ($page) => $page
                ->where('registrations.data.0.name', 'Walkin')
                ->where('registrations.data.0.lab_service.name', 'فحص المختبر')
                ->where('labServices.0.name', 'فحص المختبر')
                ->where('labAbilities.register', true));

        $this->actingAs(User::factory()->create(['role' => 'super_admin']));
        $this->get(route('patient-registrations.index'))->assertOk()
            ->assertInertia(fn ($page) => $page->where('registrations.data', []));
    }

    public function test_the_app_lists_registers_and_shows_the_lab_service(): void
    {
        $service = LabService::create(['name' => 'فحص المختبر', 'price' => 2000]);
        Sanctum::actingAs($this->labUser());

        $this->getJson('/api/v1/lab/services')->assertOk()
            ->assertJsonPath('data.0.name', 'فحص المختبر')
            ->assertJsonPath('meta.manage', true);

        $res = $this->postJson('/api/v1/lab/register', ['name' => 'Ali', 'phone' => '0771', 'lab_service_id' => $service->id, 'paid' => true])
            ->assertCreated()
            ->assertJsonPath('data.registration.lab_service.name', 'فحص المختبر')
            ->assertJsonPath('data.lab_paid', true)
            ->assertJsonPath('data.lab_fee', 2000);
        $this->assertNotNull($res->json('payment_id'));

        $this->getJson('/api/v1/lab')->assertOk()
            ->assertJsonPath('data.0.lab_service.name', 'فحص المختبر')
            ->assertJsonPath('meta.lab_services.register', true);

        $this->postJson('/api/v1/lab/services', ['name' => 'فحص السكر', 'price' => 3000])->assertCreated()->assertJsonCount(2, 'data');
    }
}
