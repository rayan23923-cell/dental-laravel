<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class DeskRolesTest extends TestCase
{
    use RefreshDatabase;

    private function createUser(string $role): User
    {
        $admin = User::factory()->create(['role' => 'super_admin']);
        $this->actingAs($admin)->post('/users', [
            'full_name' => ucfirst($role), 'username' => $role, 'email' => "{$role}@example.com",
            'password' => 'secret123', 'role' => $role,
        ])->assertSessionHasNoErrors();

        return User::where('username', $role)->firstOrFail();
    }

    public function test_reception_role_gets_ticket_desk_only(): void
    {
        $user = $this->createUser('reception');
        $this->assertDatabaseHas('user_permissions', ['user_id' => $user->id, 'module' => 'patients', 'permission' => 'create', 'granted' => true]);

        $this->actingAs($user)->get('/dashboard')->assertRedirect(route('patient-registrations.create'));
        $this->actingAs($user)->get('/patient-registrations/create')->assertOk();
        $this->actingAs($user)->get('/patient-registrations')->assertOk()
            ->assertInertia(fn ($p) => $p->where('can.archive', false)->where('can.settings', false)->where('can.screening', false));
        $this->actingAs($user)->get('/lab')->assertForbidden();
        // The tickets' own income only (2026-10-26, by request).
        $this->actingAs($user)->get('/payments')->assertOk()->assertInertia(fn ($p) => $p->where('scope', ['registration']));
        $this->actingAs($user)->get('/doctors')->assertForbidden();
    }

    public function test_lab_role_gets_lab_only(): void
    {
        $user = $this->createUser('lab');
        $this->assertDatabaseHas('user_permissions', ['user_id' => $user->id, 'module' => 'patient_screening', 'permission' => 'confirm', 'granted' => true]);

        $this->actingAs($user)->get('/dashboard')->assertRedirect(route('lab.index'));
        $this->actingAs($user)->get('/lab')->assertOk()->assertInertia(fn ($p) => $p->where('canConfirm', true));
        $this->actingAs($user)->get('/patient-registrations/create')->assertForbidden();
        // The lab fees only (2026-10-26, by request).
        $this->actingAs($user)->get('/payments')->assertOk()->assertInertia(fn ($p) => $p->where('scope', ['lab']));
    }

    /** Registering goes straight to printing the ticket (2026-10-18, by request). */
    public function test_registering_prints_the_ticket_straight_away(): void
    {
        $user = $this->createUser('reception');
        $service = \App\Models\Service::create(['name' => 'حشوة', 'price' => 6000]);

        $this->actingAs($user)->post('/patient-registrations', ['name' => 'Ali', 'phone' => '0770', 'service_id' => $service->id])
            ->assertRedirect(route('patient-registrations.index'))
            ->assertSessionHas('print_ticket');
        $id = session('print_ticket');

        $this->actingAs($user)->get(route('patient-registrations.print', ['patientRegistration' => $id, 'autoprint' => 1]))
            ->assertOk()->assertSee('setTimeout(() => window.print()', false);
    }
}
