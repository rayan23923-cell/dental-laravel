<?php

namespace Tests\Feature;

use App\Models\ClinicSetting;
use App\Models\PatientRegistration;
use App\Models\Payment;
use App\Models\Service;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Student discount (2026-10-25): an eligible patient pays each service's
 * price, and the lab fee, less its own percentage (50 by default); not
 * eligible is the default.
 */
class StudentDiscountTest extends TestCase
{
    use RefreshDatabase;

    private function admin(): User
    {
        return User::factory()->create(['role' => 'super_admin']);
    }

    public function test_new_services_and_the_lab_default_to_fifty_percent(): void
    {
        $this->actingAs($this->admin())->post('/register-services', ['name' => 'Filling', 'price' => 20000])->assertRedirect();

        $this->assertEquals(50, Service::firstWhere('name', 'Filling')->student_discount_percent);
        $this->assertEquals(50, ClinicSetting::current()->fresh()->lab_student_discount_percent);
    }

    public function test_registration_is_full_price_unless_eligible(): void
    {
        $service = Service::create(['name' => 'Filling', 'price' => 20000]);
        $admin = $this->admin();

        $this->actingAs($admin)->post('/patient-registrations', ['name' => 'Ali', 'phone' => '0770', 'service_id' => $service->id])->assertRedirect();
        $this->actingAs($admin)->post('/patient-registrations', ['name' => 'Sara', 'phone' => '0771', 'service_id' => $service->id, 'discount_eligible' => true])->assertRedirect();

        $ali = PatientRegistration::firstWhere('name', 'Ali');
        $sara = PatientRegistration::firstWhere('name', 'Sara');
        $this->assertFalse($ali->discount_eligible);
        $this->assertTrue($sara->discount_eligible);
        $this->assertEquals(20000, Payment::where('patient_registration_id', $ali->id)->value('amount'));
        $this->assertEquals(10000, Payment::where('patient_registration_id', $sara->id)->value('amount'));
    }

    public function test_api_uses_each_services_own_percentage_and_the_lab_percentage(): void
    {
        ClinicSetting::current()->update(['lab_fee' => 8000, 'lab_student_discount_percent' => 25]);
        Sanctum::actingAs($this->admin());

        $service = $this->postJson('/api/v1/services', ['name' => 'Crown', 'price' => 30000, 'student_discount_percent' => 20])
            ->assertCreated()->json();

        $id = $this->postJson('/api/v1/patient-registrations', [
            'name' => 'Omar', 'phone' => '0772', 'service_id' => $service['id'], 'discount_eligible' => true,
        ])->assertCreated()->assertJsonPath('data.discount_eligible', true)->json('data.id');

        $this->assertEquals(24000, Payment::where('patient_registration_id', $id)->where('type', 'service')->value('amount'));

        $this->getJson('/api/v1/lab')->assertOk()->assertJsonPath('data.0.lab_fee_due', 6000);

        $this->postJson("/api/v1/patient-registrations/{$id}/screening", ['screening_status' => 'clear'])->assertOk();
        $this->assertEquals(6000, Payment::where('patient_registration_id', $id)->where('type', 'lab')->value('amount'));
    }

    public function test_employees_are_eligible_with_an_optional_workplace(): void
    {
        $service = Service::create(['name' => 'Filling', 'price' => 20000]);
        $admin = $this->admin();

        $this->actingAs($admin)->post('/patient-registrations', [
            'name' => 'Huda', 'phone' => '0773', 'service_id' => $service->id,
            'discount_eligible' => true, 'discount_type' => 'employee', 'discount_workplace' => 'Pharmacy', 'discount_stage' => 'Fifth',
            'discount_person_name' => 'Huda Ali',
        ])->assertRedirect();
        $this->actingAs($admin)->post('/patient-registrations', [
            'name' => 'Zaid', 'phone' => '0774', 'service_id' => $service->id,
            'discount_eligible' => true, 'discount_type' => 'student',
        ])->assertRedirect();
        $this->actingAs($admin)->post('/patient-registrations', [
            'name' => 'Noor', 'phone' => '0775', 'service_id' => $service->id,
            'discount_eligible' => false, 'discount_type' => 'employee', 'discount_workplace' => 'Lab', 'discount_person_name' => 'X',
        ])->assertRedirect();

        $huda = PatientRegistration::firstWhere('name', 'Huda');
        $this->assertSame('employee', $huda->discount_type);
        $this->assertSame('Pharmacy', $huda->discount_workplace);
        $this->assertNull($huda->discount_stage);
        $this->assertSame('Huda Ali', $huda->discount_person_name);
        $this->assertSame('موظف · Huda Ali · Pharmacy', \App\Support\StudentDiscount::whoLabel($huda));
        $this->assertEquals(10000, Payment::where('patient_registration_id', $huda->id)->value('amount'));

        $zaid = PatientRegistration::firstWhere('name', 'Zaid');
        $this->assertSame('student', $zaid->discount_type);
        $this->assertNull($zaid->discount_stage);

        $noor = PatientRegistration::firstWhere('name', 'Noor');
        $this->assertNull($noor->discount_type);
        $this->assertNull($noor->discount_workplace);
        $this->assertNull($noor->discount_person_name);
        $this->assertEquals(20000, Payment::where('patient_registration_id', $noor->id)->value('amount'));

        $this->actingAs($admin)->post('/patient-registrations', [
            'name' => 'Bad', 'phone' => '0776', 'service_id' => $service->id, 'discount_eligible' => true, 'discount_type' => 'other',
        ])->assertSessionHasErrors('discount_type');
    }

    public function test_the_lab_fee_is_full_for_a_patient_who_is_not_eligible(): void
    {
        ClinicSetting::current()->update(['lab_fee' => 8000]);
        $service = Service::create(['name' => 'Filling', 'price' => 20000]);
        Sanctum::actingAs($this->admin());

        $id = $this->postJson('/api/v1/patient-registrations', ['name' => 'Ali', 'phone' => '0770', 'service_id' => $service->id])
            ->assertCreated()->assertJsonPath('data.discount_eligible', false)->json('data.id');

        $this->postJson("/api/v1/patient-registrations/{$id}/screening", ['screening_status' => 'flagged'])->assertOk();
        $this->assertEquals(8000, Payment::where('patient_registration_id', $id)->where('type', 'lab')->value('amount'));
    }

    public function test_printouts_and_the_report_show_the_discount(): void
    {
        ClinicSetting::current()->update(['lab_fee' => 8000, 'lab_student_discount_percent' => 25]);
        $service = Service::create(['name' => 'Filling', 'price' => 20000]);
        $admin = $this->admin();

        $this->actingAs($admin)->post('/patient-registrations', [
            'name' => 'Huda', 'phone' => '0773', 'service_id' => $service->id,
            'discount_eligible' => true, 'discount_type' => 'employee', 'discount_workplace' => 'Pharmacy',
        ]);
        $huda = PatientRegistration::firstWhere('name', 'Huda');

        // The amount, the discount and the amount after it, each on its own row.
        $rows = ['20,000', '50% — موظف · Pharmacy', 'المبلغ بعد التخفيض', '10,000'];
        $this->actingAs($admin)->get("/patient-registrations/{$huda->id}/print")->assertOk()
            ->assertSeeInOrder($rows, false);

        $payment = Payment::where('patient_registration_id', $huda->id)->first();
        $this->actingAs($admin)->get("/payments/{$payment->id}/receipt")->assertOk()
            ->assertSeeInOrder($rows, false);

        $this->actingAs($admin)->get('/payments')->assertOk()
            ->assertInertia(fn ($page) => $page
                ->where('payments.data.0.discount.percent', '50')
                ->where('payments.data.0.discount.full', fn ($v) => (float) $v === 20000.0)
                ->etc());

        Sanctum::actingAs($admin);
        $this->postJson("/api/v1/patient-registrations/{$huda->id}/screening", ['screening_status' => 'clear'])->assertOk()
            ->assertJsonPath('data.lab_discount_line', fn ($v) => str_contains($v, 'خصم 25% من 8,000'))
            ->assertJsonPath('data.lab_discount.percent', '25')
            ->assertJsonPath('data.lab_discount.paid', fn ($v) => (float) $v === 6000.0);

        $this->getJson('/api/v1/payments')->assertOk()
            ->assertJsonPath('data.0.discount_label', fn ($v) => str_starts_with($v, 'موظف · Pharmacy'))
            ->assertJsonPath('data.0.discount.who', 'موظف · Pharmacy');

        $this->actingAs($admin)->get('/payments/report')->assertOk()
            ->assertSeeInOrder(['20,000', '50% · موظف · Pharmacy', '10,000'], false);
    }
}
