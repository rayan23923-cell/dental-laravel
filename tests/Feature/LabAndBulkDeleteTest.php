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
