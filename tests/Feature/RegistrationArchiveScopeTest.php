<?php

namespace Tests\Feature;

use App\Models\PatientRegistration;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Archiving asks where from (2026-11-02, by request): the patients list,
 * the lab list, or both; the archive tab lists all three and restores them.
 */
class RegistrationArchiveScopeTest extends TestCase
{
    use RefreshDatabase;

    private function registration(string $name): PatientRegistration
    {
        $id = DB::table('patients_simple')->insertGetId([
            'name' => $name, 'phone' => '0770', 'screening_status' => 'pending', 'created_at' => now(),
        ]);

        return PatientRegistration::findOrFail($id);
    }

    private function names(string $url, string $key): array
    {
        return collect($this->getJson($url)->assertOk()->json($key))->pluck('name')->sort()->values()->all();
    }

    public function test_archive_from_patients_lab_or_both_and_restore(): void
    {
        $admin = User::factory()->create(['role' => 'super_admin']);
        $p = $this->registration('patients-only');
        $l = $this->registration('lab-only');
        $b = $this->registration('both');
        $this->registration('kept');

        $this->actingAs($admin)->delete('/patient-registrations-bulk', ['ids' => [$p->id], 'scope' => 'patients'])->assertRedirect();
        $this->actingAs($admin)->delete('/patient-registrations-bulk', ['ids' => [$l->id], 'scope' => 'lab'])->assertRedirect();
        Sanctum::actingAs($admin);
        $this->deleteJson('/api/v1/patient-registrations-bulk', ['ids' => [$b->id], 'scope' => 'both'])->assertOk();
        $this->assertSoftDeleted('patients_simple', ['id' => $b->id]);

        $this->assertSame(['kept', 'lab-only'], $this->names('/api/v1/patient-registrations', 'data'));
        $this->assertSame(['both', 'lab-only', 'patients-only'], $this->names('/api/v1/patient-registrations?archived=1', 'data'));
        $this->assertSame(['kept', 'patients-only'], $this->names('/api/v1/lab?status=all', 'data'));

        $this->actingAs($admin)->get('/lab?status=all')->assertInertia(fn ($page) => $page->has('registrations.data', 2));

        $this->postJson('/api/v1/patient-registrations-restore', ['ids' => [$p->id, $l->id, $b->id]])->assertOk();
        $this->assertSame(4, PatientRegistration::whereNull('registry_archived_at')->whereNull('lab_archived_at')->count());
    }

    public function test_bad_scope_is_rejected(): void
    {
        $admin = User::factory()->create(['role' => 'super_admin']);
        $p = $this->registration('x');

        Sanctum::actingAs($admin);
        $this->deleteJson('/api/v1/patient-registrations-bulk', ['ids' => [$p->id], 'scope' => 'everything'])->assertStatus(422);
    }
}
