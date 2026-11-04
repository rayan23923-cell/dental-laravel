<?php

namespace Tests\Feature;

use App\Models\Payment;
use App\Models\PatientRegistration;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Archiving is plain (2026-11-04, by request); the permanent delete from
 * the archive asks where from: the patients list, the lab list, or both.
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

    public function test_archiving_is_plain_and_ignores_an_older_apps_scope(): void
    {
        $admin = User::factory()->create(['role' => 'super_admin']);
        $p = $this->registration('patients-only');
        $this->registration('kept');

        Sanctum::actingAs($admin);
        $this->deleteJson('/api/v1/patient-registrations-bulk', ['ids' => [$p->id], 'scope' => 'patients'])->assertOk();
        $this->assertSoftDeleted('patients_simple', ['id' => $p->id]);
        $this->assertSame(['kept'], $this->names('/api/v1/patient-registrations', 'data'));
        $this->assertSame(['kept'], $this->names('/api/v1/lab?status=all', 'data'));
        $this->assertSame(['patients-only'], $this->names('/api/v1/patient-registrations?archived=1', 'data'));

        $this->postJson('/api/v1/patient-registrations-restore', ['ids' => [$p->id]])->assertOk();
        $this->assertSame(2, PatientRegistration::count());
    }

    /** Permanent delete from the patients list, the lab list, or both (2026-11-04). */
    public function test_permanent_delete_from_patients_or_lab_keeps_the_other_part(): void
    {
        $admin = User::factory()->create(['role' => 'super_admin', 'password' => bcrypt('secret-pass')]);
        $p = $this->registration('del-patients');
        $l = $this->registration('del-lab');
        $this->registration('kept');
        foreach ([$p, $l] as $r) {
            Payment::create(['patient_registration_id' => $r->id, 'amount' => 25000, 'paid_at' => now(), 'type' => 'service']);
            Payment::create(['patient_registration_id' => $r->id, 'amount' => 5000, 'paid_at' => now(), 'type' => 'lab']);
            $r->delete();
        }

        $this->actingAs($admin)->delete('/patient-registrations-purge', ['ids' => [$p->id], 'password' => 'secret-pass', 'scope' => 'patients'])->assertRedirect();
        Sanctum::actingAs($admin);
        $this->deleteJson('/api/v1/patient-registrations-purge', ['ids' => [$l->id], 'password' => 'secret-pass', 'scope' => 'lab'])->assertOk();

        // Each keeps only the other part's payments, and stays archived.
        $this->assertSame(['lab'], Payment::where('patient_registration_id', $p->id)->pluck('type')->all());
        $this->assertSame(['service'], Payment::where('patient_registration_id', $l->id)->pluck('type')->all());
        $this->assertSame(['del-lab', 'del-patients'], $this->names('/api/v1/patient-registrations?archived=1', 'data'));

        // Restored: each comes back only where it wasn't deleted from.
        $this->postJson('/api/v1/patient-registrations-restore', ['ids' => [$p->id, $l->id]])->assertOk();
        $this->assertSame(['del-lab', 'kept'], $this->names('/api/v1/patient-registrations', 'data'));
        $this->assertSame(['del-patients', 'kept'], $this->names('/api/v1/lab?status=all', 'data'));
        $this->assertSame([], $this->names('/api/v1/patient-registrations?archived=1', 'data'));

        // Archived again and deleted from the other list: nothing left, so the row goes.
        PatientRegistration::find($p->id)->delete();
        $this->deleteJson('/api/v1/patient-registrations-purge', ['ids' => [$p->id], 'password' => 'secret-pass', 'scope' => 'lab'])->assertOk();
        $this->assertDatabaseMissing('patients_simple', ['id' => $p->id]);
        $this->assertDatabaseMissing('payments', ['patient_registration_id' => $p->id]);
    }

    public function test_bad_scope_is_rejected(): void
    {
        $admin = User::factory()->create(['role' => 'super_admin']);
        $p = $this->registration('x');

        Sanctum::actingAs($admin);
        $this->deleteJson('/api/v1/patient-registrations-bulk', ['ids' => [$p->id], 'scope' => 'everything'])->assertStatus(422);
    }

    public function test_permanent_delete_needs_password_and_only_archived(): void
    {
        $admin = User::factory()->create(['role' => 'super_admin', 'password' => bcrypt('secret-pass')]);
        $archived = $this->registration('archived');
        $live = $this->registration('live');
        \App\Models\Payment::create(['patient_registration_id' => $archived->id, 'amount' => 5000, 'paid_at' => now(), 'type' => 'lab']);
        $archived->delete();

        $this->actingAs($admin)->deleteJson('/patient-registrations-purge', ['ids' => [$archived->id], 'password' => 'wrong'])
            ->assertStatus(422)->assertJsonValidationErrors('password');
        $this->assertSoftDeleted('patients_simple', ['id' => $archived->id]);

        $this->actingAs($admin)->delete('/patient-registrations-purge', ['ids' => [$archived->id, $live->id], 'password' => 'secret-pass'])
            ->assertRedirect();
        $this->assertDatabaseMissing('patients_simple', ['id' => $archived->id]);
        $this->assertDatabaseMissing('payments', ['patient_registration_id' => $archived->id]);
        // Not archived: untouched.
        $this->assertDatabaseHas('patients_simple', ['id' => $live->id, 'deleted_at' => null]);
    }
}
