<?php

namespace Tests\Feature;

use App\Models\Payment;
use App\Models\PatientRegistration;
use App\Models\User;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * With a date filter the payments overview, charts and report cover that
 * period only (2026-11-04, by request), by the clinic's day (Baghdad).
 */
class PaymentsFilteredPeriodTest extends TestCase
{
    use RefreshDatabase;

    protected function tearDown(): void
    {
        CarbonImmutable::setTestNow();
        \Illuminate\Support\Carbon::setTestNow();
        parent::tearDown();
    }

    private function seedPayments(): User
    {
        \Illuminate\Support\Carbon::setTestNow('2026-11-04 09:00:00');
        CarbonImmutable::setTestNow('2026-11-04 09:00:00');
        $id = DB::table('patients_simple')->insertGetId([
            'name' => 'Ali', 'phone' => '0770', 'screening_status' => 'pending', 'created_at' => now(),
        ]);
        $r = PatientRegistration::findOrFail($id);
        // 01:00 Baghdad on 11-04 is 22:00 UTC on 11-03: inside the 11-04 filter.
        Payment::create(['patient_registration_id' => $r->id, 'amount' => 1000, 'paid_at' => '2026-11-03 22:00:00', 'type' => 'service']);
        Payment::create(['patient_registration_id' => $r->id, 'amount' => 3000, 'paid_at' => '2026-11-05 08:00:00', 'type' => 'lab']);
        // Outside the period.
        Payment::create(['patient_registration_id' => $r->id, 'amount' => 7000, 'paid_at' => '2026-10-20 08:00:00', 'type' => 'service']);

        return User::factory()->create(['role' => 'super_admin']);
    }

    public function test_web_page_and_report_cover_the_filtered_period_only(): void
    {
        $admin = $this->seedPayments();

        $this->actingAs($admin)->get('/payments?from=2026-11-04&to=2026-11-07')->assertOk()
            ->assertInertia(fn ($p) => $p
                ->where('range.from', '2026-11-04')
                ->where('range.to', '2026-11-07')
                ->where('range.days', 4)
                ->where('range.total', 4000)
                ->where('range.count', 2)
                ->where('range.paid_days', 2)
                ->where('range.best.date', '2026-11-05')
                ->where('filteredTotal', 4000)
                ->has('daily', 4)
                ->where('daily.0.total', 1000)
                ->where('daily.1.total', 3000)
                ->has('monthly', 0));

        // Without a date filter: the usual overview.
        $this->actingAs($admin)->get('/payments')->assertOk()
            ->assertInertia(fn ($p) => $p->where('range', null)->has('daily', 30)->has('monthly', 12));

        $this->actingAs($admin)->get('/payments/report?from=2026-11-04&to=2026-11-07')->assertOk()
            ->assertSee('مجموع الفترة')->assertSee('الوارد اليومي من 2026-11-04 إلى 2026-11-07')
            ->assertSee('4,000')->assertDontSee('آخر 30 يومًا');
    }

    public function test_api_stats_and_report_follow_the_period(): void
    {
        $admin = $this->seedPayments();
        Sanctum::actingAs($admin);

        $this->getJson('/api/v1/payments/stats?from=2026-10-01&to=2026-11-07')->assertOk()
            ->assertJsonPath('data.range.total', 11000)
            ->assertJsonCount(38, 'data.daily')
            ->assertJsonCount(2, 'data.monthly')
            ->assertJsonPath('data.monthly.0.total', 7000);

        // Only "from" (in the future here): up to that same day.
        $this->getJson('/api/v1/payments/report?from=2026-11-05&source=lab')->assertOk()
            ->assertJsonPath('data.range.total', 3000)
            ->assertJsonPath('data.range.to', '2026-11-05')
            ->assertJsonCount(1, 'data.payments');

        // Only "to": from the first payment the filters match.
        $this->getJson('/api/v1/payments/stats?to=2026-11-04')->assertOk()
            ->assertJsonPath('data.range.from', '2026-10-20')
            ->assertJsonPath('data.range.total', 8000);
    }

    public function test_api_activity_log(): void
    {
        $admin = $this->seedPayments();
        Sanctum::actingAs($admin);

        $this->getJson('/api/v1/payments/activity')->assertOk()->assertJsonStructure(['data', 'currency']);
    }
}
