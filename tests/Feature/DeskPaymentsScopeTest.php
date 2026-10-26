<?php

namespace Tests\Feature;

use App\Models\Payment;
use App\Models\PatientRegistration;
use App\Models\User;
use App\Models\UserPermission;
use App\Support\RolePresets;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * The lab sees and prints the lab fees only and the ticket desk the
 * tickets' income only (2026-10-26, by request); payments.view still sees
 * every payment.
 */
class DeskPaymentsScopeTest extends TestCase
{
    use RefreshDatabase;

    private Payment $service;

    private Payment $lab;

    protected function setUp(): void
    {
        parent::setUp();
        $id = DB::table('patients_simple')->insertGetId([
            'name' => 'Ali', 'phone' => '0770', 'screening_status' => 'pending', 'created_at' => now(),
        ]);
        $this->service = Payment::create(['patient_registration_id' => $id, 'amount' => 25000, 'paid_at' => now(), 'type' => 'service']);
        $this->lab = Payment::create(['patient_registration_id' => $id, 'amount' => 10000, 'paid_at' => now(), 'type' => 'lab']);
    }

    private function desk(string $role): User
    {
        $user = User::factory()->create(['role' => $role]);
        RolePresets::apply($user);

        return $user;
    }

    public function test_lab_account_sees_and_prints_lab_payments_only(): void
    {
        $lab = $this->desk('lab');

        $this->actingAs($lab)->get('/payments?source=registration')->assertOk()
            ->assertInertia(fn ($p) => $p->has('payments.data', 1)
                ->where('payments.data.0.type', 'lab')
                ->where('filteredTotal', 10000)
                ->where('periods.today.total', 10000)
                ->where('scope', ['lab'])
                ->where('filters.source', 'lab')
                ->where('can.export', true)
                ->where('can.delete', false)
                ->has('bySource', 1));

        $this->actingAs($lab)->get('/payments/report')->assertOk()
            ->assertSee('تقرير مدفوعات المختبر')->assertViewHas('filteredTotal', 10000.0);
        $this->actingAs($lab)->get("/payments/{$this->lab->id}/receipt")->assertOk();
        $this->actingAs($lab)->get("/payments/{$this->service->id}/receipt")->assertForbidden();
        $this->actingAs($lab)->delete("/payments/{$this->lab->id}")->assertForbidden();
    }

    public function test_ticket_desk_sees_ticket_income_only(): void
    {
        $reception = $this->desk('reception');

        $this->actingAs($reception)->get('/payments')->assertOk()
            ->assertInertia(fn ($p) => $p->has('payments.data', 1)
                ->where('payments.data.0.type', 'service')
                ->where('filteredTotal', 25000)
                ->where('scope', ['registration']));
        $this->actingAs($reception)->get('/payments/report')->assertOk()->assertSee('تقرير واردات التذاكر');
    }

    public function test_api_follows_the_same_scope(): void
    {
        Sanctum::actingAs($this->desk('lab'));

        $this->getJson('/api/v1/payments')->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.id', $this->lab->id);
        $this->getJson('/api/v1/payments/report')->assertOk()
            ->assertJsonPath('data.filtered_total', 10000)
            ->assertJsonPath('data.scope', ['lab'])
            ->assertJsonCount(1, 'data.payments');
        $this->getJson('/api/v1/payments/stats')->assertOk()->assertJsonPath('data.periods.today.total', 10000);
        $this->getJson("/api/v1/payments/{$this->service->id}")->assertForbidden();
        $this->getJson('/api/v1/me')->assertOk()->assertSee('payments.view_lab');
    }

    public function test_full_payments_permission_still_sees_everything(): void
    {
        $accountant = $this->desk('accountant');

        $this->actingAs($accountant)->get('/payments')->assertOk()
            ->assertInertia(fn ($p) => $p->has('payments.data', 2)->where('filteredTotal', 35000)->where('scope', null));
    }

    public function test_without_any_payments_grant_the_page_is_refused(): void
    {
        $lab = $this->desk('lab');
        UserPermission::where('user_id', $lab->id)->where('module', 'payments')->delete();
        \Illuminate\Support\Facades\Cache::flush();

        $this->actingAs($lab)->get('/payments')->assertForbidden();
        $this->actingAs($lab)->get('/payments/report')->assertForbidden();
    }
}
