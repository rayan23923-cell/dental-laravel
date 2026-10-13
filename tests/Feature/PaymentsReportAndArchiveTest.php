<?php

namespace Tests\Feature;

use App\Models\Payment;
use App\Models\PatientRegistration;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class PaymentsReportAndArchiveTest extends TestCase
{
    use RefreshDatabase;

    private function admin(): User
    {
        return User::factory()->create(['role' => 'super_admin']);
    }

    private function registration(string $name): PatientRegistration
    {
        $id = DB::table('patients_simple')->insertGetId([
            'name' => $name, 'phone' => '0770', 'screening_status' => 'pending', 'created_at' => now(),
        ]);

        return PatientRegistration::findOrFail($id);
    }

    public function test_deleting_a_patient_archives_it_and_keeps_its_payments(): void
    {
        $ali = $this->registration('Ali');
        $this->registration('Sara');
        Payment::create(['patient_registration_id' => $ali->id, 'amount' => 25000, 'paid_at' => now(), 'type' => 'service']);
        $admin = $this->admin();

        $this->actingAs($admin)->delete('/patient-registrations-bulk', ['ids' => [$ali->id]])->assertRedirect();

        $this->assertSoftDeleted('patients_simple', ['id' => $ali->id]);
        $this->assertSame(1, PatientRegistration::count());
        $this->assertSame('Ali', Payment::first()->patientRegistration->name);

        $this->actingAs($admin)->get('/patient-registrations?archived=1')->assertOk()
            ->assertInertia(fn ($p) => $p->has('registrations.data', 1)->where('registrations.data.0.name', 'Ali'));

        // Archived patients' payments still count and are still searchable.
        $this->actingAs($admin)->get('/payments?search=Ali')->assertOk()
            ->assertInertia(fn ($p) => $p->has('payments.data', 1)->where('filteredTotal', 25000)->where('periods.today.total', 25000));

        $this->actingAs($admin)->post('/patient-registrations-restore', ['ids' => [$ali->id]])->assertRedirect();
        $this->assertSame(2, PatientRegistration::count());
    }

    public function test_payments_page_reports_income_by_period_and_prints(): void
    {
        $ali = $this->registration('Ali');
        Payment::create(['patient_registration_id' => $ali->id, 'amount' => 25000, 'paid_at' => now(), 'type' => 'service']);
        Payment::create(['patient_registration_id' => $ali->id, 'amount' => 10000, 'paid_at' => now(), 'type' => 'lab']);
        Payment::create(['patient_registration_id' => $ali->id, 'amount' => 5000, 'paid_at' => now()->subYears(2), 'type' => 'service']);
        $admin = $this->admin();

        $this->actingAs($admin)->get('/payments')->assertOk()
            ->assertInertia(fn ($p) => $p
                ->where('periods.today.total', 35000)
                ->where('periods.today.count', 2)
                ->where('periods.year.total', 35000)
                ->where('filteredTotal', 40000)
                ->where('bySource.0.total', 30000)
                ->where('bySource.1.total', 10000)
                ->has('daily', 30)
                ->has('monthly', 12));

        $this->actingAs($admin)->get('/payments/report?source=lab')->assertOk()
            ->assertSee('تقرير المدفوعات')->assertSee('<svg', false)->assertSee('10,000');
    }
}
