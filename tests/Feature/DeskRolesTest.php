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
        $this->actingAs($user)->get('/payments')->assertForbidden();
        $this->actingAs($user)->get('/doctors')->assertForbidden();
    }

    public function test_lab_role_gets_lab_only(): void
    {
        $user = $this->createUser('lab');
        $this->assertDatabaseHas('user_permissions', ['user_id' => $user->id, 'module' => 'patient_screening', 'permission' => 'confirm', 'granted' => true]);

        $this->actingAs($user)->get('/dashboard')->assertRedirect(route('lab.index'));
        $this->actingAs($user)->get('/lab')->assertOk()->assertInertia(fn ($p) => $p->where('canConfirm', true));
        $this->actingAs($user)->get('/patient-registrations/create')->assertForbidden();
        $this->actingAs($user)->get('/payments')->assertForbidden();
    }
}
