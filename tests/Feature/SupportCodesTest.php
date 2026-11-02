<?php

namespace Tests\Feature;

use App\Models\ActivityLog;
use App\Models\ClinicSetting;
use App\Models\PatientRegistration;
use App\Models\Payment;
use App\Models\Service;
use App\Models\SupportCode;
use App\Models\User;
use App\Models\UserPermission;
use App\Support\SupportCodes;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Care codes, "بطاقات الرعاية" (2026-11-01): one-time 5-digit codes that make
 * the service and the lab test free, off until switched on, stoppable, and
 * listed on the payments report's last page.
 */
class SupportCodesTest extends TestCase
{
    use RefreshDatabase;

    private function admin(): User
    {
        return User::factory()->create(['role' => 'super_admin']);
    }

    private function enable(): void
    {
        ClinicSetting::current()->update(['support_codes_enabled' => true, 'lab_fee' => 8000]);
    }

    public function test_codes_are_generated_unique_five_digits_in_a_batch(): void
    {
        $this->actingAs($this->admin())->post('/support-codes', ['count' => 30, 'note' => 'Nov'])->assertRedirect();

        $codes = SupportCode::all();
        $this->assertCount(30, $codes);
        $this->assertCount(30, $codes->pluck('code')->unique());
        $this->assertTrue($codes->every(fn ($c) => preg_match('/^[1-9]\d{4}$/', $c->code) === 1 && $c->batch === 1 && $c->note === 'Nov'));

        SupportCodes::generate(5, null, null);
        $this->assertSame(5, SupportCode::where('batch', 2)->count());
    }

    public function test_a_code_makes_the_service_and_the_lab_free_once(): void
    {
        $this->enable();
        $service = Service::create(['name' => 'Filling', 'price' => 20000]);
        $code = SupportCodes::generate(1, null, null)->first();
        $admin = $this->admin();

        $this->actingAs($admin)->post('/patient-registrations', [
            'name' => 'Ali', 'phone' => '0770', 'service_id' => $service->id, 'support_code' => $code->code,
            // A discount sent with it is dropped: free care wins.
            'discount_eligible' => true,
        ])->assertRedirect()->assertSessionHasNoErrors();

        $ali = PatientRegistration::firstWhere('name', 'Ali');
        $this->assertSame($code->id, $ali->support_code_id);
        $this->assertFalse($ali->discount_eligible);
        $this->assertSame(0, Payment::count());
        $this->assertSame(SupportCode::USED, $code->fresh()->status());
        $this->assertEquals(20000, $code->fresh()->waived_service);

        // The lab records the result without charging; the fee is kept on the code.
        $this->actingAs($admin)->postJson("/patient-registrations/{$ali->id}/screening", ['screening_status' => 'clear'])->assertOk();
        $this->assertSame(0, Payment::count());
        $this->assertEquals(8000, $code->fresh()->waived_lab);

        // Ticket and lab slip say so, with a zero amount.
        $this->actingAs($admin)->get("/patient-registrations/{$ali->id}/print")->assertOk()->assertSee('مشمول بالرعاية');

        // Used once only.
        $this->actingAs($admin)->post('/patient-registrations', [
            'name' => 'Sara', 'phone' => '0771', 'service_id' => $service->id, 'support_code' => $code->code,
        ])->assertSessionHasErrors(['support_code' => 'رمز الرعاية هذا مستخدم مسبقًا.']);
        $this->assertNull(PatientRegistration::firstWhere('name', 'Sara'));
    }

    public function test_the_api_registers_free_and_reports_supported(): void
    {
        $this->enable();
        $service = Service::create(['name' => 'Crown', 'price' => 30000]);
        $code = SupportCodes::generate(1, null, null)->first();
        Sanctum::actingAs($this->admin());

        // Arabic digits are accepted.
        $arabic = strtr($code->code, ['0' => '٠', '1' => '١', '2' => '٢', '3' => '٣', '4' => '٤', '5' => '٥', '6' => '٦', '7' => '٧', '8' => '٨', '9' => '٩']);
        $this->postJson('/api/v1/support-codes/check', ['code' => $arabic])->assertOk()->assertJsonPath('valid', true);

        $id = $this->postJson('/api/v1/patient-registrations', [
            'name' => 'Omar', 'phone' => '0772', 'service_id' => $service->id, 'support_code' => $arabic,
        ])->assertCreated()
            ->assertJsonPath('data.supported', true)
            ->assertJsonPath('data.service_fee', 0)
            ->json('data.id');

        $this->getJson('/api/v1/lab')->assertOk()->assertJsonPath('data.0.lab_fee_due', 0);
        $this->getJson("/api/v1/patient-registrations/{$id}/status")->assertOk()->assertJsonPath('data.supported', true);
        // No lab fee can be taken by hand either.
        $this->postJson('/api/v1/payments', ['patient_registration_id' => $id, 'type' => 'lab', 'amount' => 1])->assertStatus(422);

        $this->postJson("/api/v1/patient-registrations/{$id}/screening", ['screening_status' => 'flagged'])->assertOk();
        $this->assertSame(0, Payment::count());

        $report = $this->getJson('/api/v1/payments/report')->assertOk()->json('data');
        $this->assertCount(1, $report['supported']);
        $this->assertSame('Omar', $report['supported'][0]['name']);
        $this->assertEquals(38000, $report['supported'][0]['waived_total']);
        $this->assertEquals(0, $report['filtered_total']);
    }

    public function test_wrong_stopped_and_switched_off_codes_are_refused(): void
    {
        $service = Service::create(['name' => 'Filling', 'price' => 20000]);
        [$a, $b] = SupportCodes::generate(2, null, null)->all();
        $admin = $this->admin();
        $post = fn ($code) => $this->actingAs($admin)->post('/patient-registrations', [
            'name' => 'X', 'phone' => '0770', 'service_id' => $service->id, 'support_code' => $code,
        ]);

        // Off by default.
        $post($a->code)->assertSessionHasErrors('support_code');

        $this->actingAs($admin)->put('/register-settings/support-codes', ['support_codes_enabled' => true])->assertRedirect();
        $this->assertTrue(SupportCodes::enabled());

        $this->actingAs($admin)->post('/support-codes/status', ['ids' => [$a->id], 'disabled' => true])->assertRedirect();
        $post($a->code)->assertSessionHasErrors(['support_code' => 'رمز الرعاية هذا موقوف.']);
        $post('00000')->assertSessionHasErrors(['support_code' => 'رمز الرعاية غير صحيح.']);

        // Started again, and a whole batch can be stopped.
        $this->actingAs($admin)->post('/support-codes/status', ['ids' => [$a->id], 'disabled' => false]);
        $this->assertSame(SupportCode::ACTIVE, $a->fresh()->status());
        $this->actingAs($admin)->post('/support-codes/status', ['batch' => 1, 'disabled' => true]);
        $this->assertSame(SupportCode::DISABLED, $b->fresh()->status());
        $this->assertSame(0, PatientRegistration::count());
    }

    public function test_the_page_needs_its_permission_and_cards_print_active_codes(): void
    {
        $user = User::factory()->create(['role' => 'reception']);
        $this->actingAs($user)->get('/support-codes')->assertForbidden();
        $this->actingAs($user)->post('/support-codes', ['count' => 3])->assertForbidden();

        UserPermission::create(['user_id' => $user->id, 'module' => 'support_codes', 'permission' => 'view', 'granted' => true]);
        UserPermission::create(['user_id' => $user->id, 'module' => 'support_codes', 'permission' => 'generate', 'granted' => true]);
        Cache::flush();

        $this->actingAs($user)->get('/support-codes')->assertOk();
        $this->actingAs($user)->post('/support-codes', ['count' => 3])->assertRedirect();
        $this->actingAs($user)->post('/support-codes/status', ['batch' => 1, 'disabled' => true])->assertForbidden();

        [$a, $b] = SupportCode::orderBy('id')->take(2)->get()->all();
        $b->update(['disabled_at' => now()]);
        $this->actingAs($user)->get('/support-codes/cards?batch=1')->assertOk()
            ->assertSee($a->code)->assertDontSee('>'.$b->code.'<', false)->assertSee('بطاقة رعاية');
    }

    public function test_the_report_lists_supported_and_discounted_on_its_last_page(): void
    {
        $this->enable();
        $service = Service::create(['name' => 'Filling', 'price' => 20000]);
        $code = SupportCodes::generate(1, null, null)->first();
        $admin = $this->admin();

        $this->actingAs($admin)->post('/patient-registrations', ['name' => 'Free Patient', 'phone' => '0770', 'service_id' => $service->id, 'support_code' => $code->code]);
        $this->actingAs($admin)->post('/patient-registrations', ['name' => 'Student Patient', 'phone' => '0771', 'service_id' => $service->id, 'discount_eligible' => true]);
        $this->actingAs($admin)->post('/patient-registrations', ['name' => 'Full Patient', 'phone' => '0772', 'service_id' => $service->id]);

        $this->actingAs($admin)->get('/payments/report')->assertOk()
            ->assertSeeInOrder(['المدفوعات', 'المستفيدون من الرعاية (1)', 'Free Patient', $code->code, 'المشمولون بالتخفيض (1)', 'Student Patient', '50%'])
            ->assertSee('30,000');
    }

    public function test_every_step_is_written_to_the_activity_log(): void
    {
        $service = Service::create(['name' => 'Filling', 'price' => 20000]);
        $admin = $this->admin();
        ClinicSetting::current()->update(['lab_fee' => 8000]);

        $this->actingAs($admin)->put('/register-settings/support-codes', ['support_codes_enabled' => true]);
        $this->actingAs($admin)->post('/support-codes', ['count' => 3]);
        [$a, $b] = SupportCode::orderBy('id')->take(2)->get()->all();
        $this->actingAs($admin)->post('/support-codes/status', ['ids' => [$b->id], 'disabled' => true]);
        $this->actingAs($admin)->post('/support-codes/status', ['ids' => [$b->id], 'disabled' => false]);
        $this->actingAs($admin)->post('/patient-registrations', ['name' => 'Ali', 'phone' => '0770', 'service_id' => $service->id, 'support_code' => $a->code]);
        $ali = PatientRegistration::firstWhere('name', 'Ali');
        $this->actingAs($admin)->postJson("/patient-registrations/{$ali->id}/screening", ['screening_status' => 'clear'])->assertOk();

        $logs = ActivityLog::where('module', SupportCodes::LOG_MODULE)->orderBy('id')->pluck('description')->all();
        $this->assertSame([
            'تفعيل بطاقات الرعاية',
            'توليد 3 بطاقة رعاية (الدفعة 1)',
            'إيقاف 1 بطاقة رعاية',
            'إعادة تفعيل 1 بطاقة رعاية',
            "استخدام بطاقة الرعاية {$a->code} للمراجع \"Ali\"",
            'فحص مختبر مجاني (رعاية) للمراجع "Ali"',
        ], $logs);
        $this->assertTrue(ActivityLog::where('module', SupportCodes::LOG_MODULE)->get()->every(fn ($l) => $l->user_id === $admin->id));
    }
}
