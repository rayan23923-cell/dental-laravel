<?php

namespace Tests\Feature;

use App\Models\ActivityLog;
use App\Models\PatientRegistration;
use App\Models\Payment;
use App\Models\Service;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * 2026-11-01, by request: a payment keeps the price of its day after the
 * price changes, and the payments activity log prints who added / deleted
 * which payment.
 */
class PaymentPriceAtTimeAndActivityTest extends TestCase
{
    use RefreshDatabase;

    private function admin(): User
    {
        return User::factory()->create(['role' => 'super_admin']);
    }

    public function test_old_receipts_keep_the_price_of_their_day(): void
    {
        $service = Service::create(['name' => 'Filling', 'price' => 10000]);
        $admin = $this->admin();

        $this->actingAs($admin)->post('/patient-registrations', [
            'name' => 'Sara', 'phone' => '0771', 'service_id' => $service->id, 'discount_eligible' => true,
        ])->assertRedirect();
        $sara = PatientRegistration::firstWhere('name', 'Sara');
        $payment = Payment::firstWhere('patient_registration_id', $sara->id);
        $this->assertEquals(5000, $payment->amount);
        $this->assertEquals(10000, $payment->full_amount);

        $service->update(['price' => 15000]);

        $this->actingAs($admin)->get("/payments/{$payment->id}/receipt")->assertOk()
            ->assertSee('10,000')->assertDontSee('15,000');
        $this->actingAs($admin)->get("/patient-registrations/{$sara->id}/print")->assertOk()
            ->assertSee('10,000')->assertDontSee('15,000');

        // A new registration takes the new price.
        $this->actingAs($admin)->post('/patient-registrations', ['name' => 'Ali', 'phone' => '0772', 'service_id' => $service->id])->assertRedirect();
        $this->assertEquals(15000, Payment::where('patient_registration_id', PatientRegistration::firstWhere('name', 'Ali')->id)->value('full_amount'));
    }

    public function test_payments_activity_log_prints_adds_and_deletes(): void
    {
        $service = Service::create(['name' => 'Filling', 'price' => 12000]);
        $admin = $this->admin();
        $this->actingAs($admin)->post('/patient-registrations', ['name' => 'Huda', 'phone' => '0773', 'service_id' => $service->id])->assertRedirect();
        $payment = Payment::firstWhere('patient_registration_id', PatientRegistration::firstWhere('name', 'Huda')->id);
        $this->actingAs($admin)->delete("/payments/{$payment->id}")->assertRedirect();

        $this->assertSame(2, ActivityLog::where('module', 'Payment')->count());
        $deleted = ActivityLog::where('module', 'Payment')->where('action', 'delete')->first();
        $this->assertSame('Huda', json_decode($deleted->data, true)['snapshot']['patient']);

        $this->actingAs($admin)->get('/payments/activity?autoprint=1')->assertOk()
            ->assertSee('سجل حركات المدفوعات')
            ->assertSee('إضافة')->assertSee('حذف')
            ->assertSee('Huda')->assertSee('12,000')
            ->assertSee($admin->username);

        $this->actingAs(User::factory()->create(['role' => 'lab']))->get('/payments/activity')->assertForbidden();
    }
}
