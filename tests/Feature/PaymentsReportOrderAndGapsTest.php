<?php

namespace Tests\Feature;

use App\Models\Payment;
use App\Models\PatientRegistration;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * The printed payments report (2026-11-25, by request): oldest first, a
 * serial number from 1 beside the id, and the missing ids between the
 * listed ones with what is known of them.
 */
class PaymentsReportOrderAndGapsTest extends TestCase
{
    use RefreshDatabase;

    private function registration(string $name): PatientRegistration
    {
        $id = DB::table('patients_simple')->insertGetId([
            'name' => $name, 'phone' => '0770', 'screening_status' => 'pending', 'created_at' => now(),
        ]);

        return PatientRegistration::findOrFail($id);
    }

    public function test_report_is_oldest_first_numbered_and_shows_missing_ids(): void
    {
        $admin = User::factory()->create(['role' => 'super_admin', 'username' => 'boss']);
        $this->actingAs($admin);

        $ali = $this->registration('Ali');
        $sara = $this->registration('Sara');
        $omar = $this->registration('Omar');
        Payment::create(['patient_registration_id' => $ali->id, 'amount' => 3000, 'paid_at' => now()->subHours(3), 'type' => 'lab']);
        $ticket = Payment::create(['patient_registration_id' => $sara->id, 'amount' => 5000, 'paid_at' => now()->subHours(2), 'type' => 'service']);
        $deleted = Payment::create(['patient_registration_id' => $omar->id, 'amount' => 3000, 'paid_at' => now()->subHours(2), 'type' => 'lab']);
        Payment::create(['patient_registration_id' => $sara->id, 'amount' => 3000, 'paid_at' => now()->subHour(), 'type' => 'lab']);
        $deleted->delete();

        $html = $this->get('/payments/report?source=lab')->assertOk()->getContent();

        // Oldest first: Ali's payment before Sara's lab payment.
        $this->assertLessThan(strpos($html, 'Sara'), strpos($html, 'Ali'));
        $this->assertStringContainsString('<th class="w-n">ت</th>', $html);

        // The ticket payment is outside the lab report; the deleted one is
        // shown as deleted, by whom, with what it was.
        $this->assertStringContainsString('أرقام ناقصة في التسلسل: 2', $html);
        $this->assertMatchesRegularExpression('/رقم ناقص <strong dir="ltr">'.$ticket->id.'<\/strong>: ليست ضمن هذا التقرير — تسجيل مريض · Sara/u', $html);
        $this->assertMatchesRegularExpression('/رقم ناقص <strong dir="ltr">'.$deleted->id.'<\/strong>: محذوفة من boss/u', $html);
        $this->assertStringContainsString('Omar', $html);
    }

    public function test_lab_account_sees_no_details_of_other_sources(): void
    {
        $sara = $this->registration('Sara');
        $ali = $this->registration('Ali');
        Payment::create(['patient_registration_id' => $ali->id, 'amount' => 3000, 'paid_at' => now()->subHours(3), 'type' => 'lab']);
        $ticket = Payment::create(['patient_registration_id' => $sara->id, 'amount' => 5000, 'paid_at' => now()->subHours(2), 'type' => 'service']);
        Payment::create(['patient_registration_id' => $ali->id, 'amount' => 3000, 'paid_at' => now()->subHour(), 'type' => 'lab']);

        $gaps = \App\Support\PaymentGaps::for(Payment::where('type', 'lab')->orderBy('paid_at')->get(), ['lab']);

        $this->assertSame(1, $gaps['count']);
        $this->assertSame($ticket->id, $gaps['after'][0][0]['id']);
        $this->assertSame('outside', $gaps['after'][0][0]['status']);
        $this->assertNull($gaps['after'][0][0]['details']);
    }
}
