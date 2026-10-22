<?php

namespace Tests\Feature;

use App\Models\QueuedEmail;
use App\Models\User;
use App\Models\UserPermission;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Users management (2026-10-21, by request): edit an account's details,
 * switch it off and change its password, on the web and through the API.
 */
class UserManagementTest extends TestCase
{
    use RefreshDatabase;

    private function details(User $user, array $extra = []): array
    {
        return $extra + $user->only(['full_name', 'username', 'email', 'phone', 'role', 'status', 'notes']);
    }

    public function test_the_web_page_lists_and_edits_a_user(): void
    {
        $admin = User::factory()->create(['role' => 'super_admin']);
        $user = User::factory()->create(['role' => 'editor', 'username' => 'old']);
        $this->actingAs($admin);

        $this->get('/users')->assertOk()->assertInertia(fn ($p) => $p->component('Users/Index')->has('users', 2));
        $this->get("/users/{$user->id}/edit")->assertOk()->assertInertia(fn ($p) => $p->where('targetUser.username', 'old'));

        $this->put("/users/{$user->id}", $this->details($user, ['username' => 'new', 'full_name' => 'اسم جديد', 'role' => 'accountant']))
            ->assertSessionHasNoErrors();

        $user->refresh();
        $this->assertSame(['new', 'اسم جديد', 'accountant'], [$user->username, $user->full_name, $user->role]);
    }

    public function test_the_web_page_changes_and_generates_passwords(): void
    {
        $this->actingAs(User::factory()->create(['role' => 'super_admin']));
        $user = User::factory()->create(['role' => 'editor']);
        $user->createToken('phone');

        $this->put("/users/{$user->id}/password", ['password' => 'newpass1', 'password_confirmation' => 'nope'])
            ->assertSessionHasErrors('password');
        $this->put("/users/{$user->id}/password", ['password' => 'newpass1', 'password_confirmation' => 'newpass1'])
            ->assertSessionHasNoErrors();
        $this->assertTrue(Hash::check('newpass1', $user->refresh()->password));
        $this->assertSame(0, $user->tokens()->count());
        $this->assertSame(0, QueuedEmail::count());

        $this->put("/users/{$user->id}/password", ['generate' => true])
            ->assertSessionHasNoErrors()
            ->assertSessionHas('generatedPassword');
        $this->assertTrue(Hash::check(session('generatedPassword'), $user->refresh()->password));
        $this->assertTrue(QueuedEmail::first()->payload['reset']);
    }

    public function test_a_disabled_account_cannot_sign_in(): void
    {
        $user = User::factory()->create(['role' => 'editor', 'username' => 'off', 'password' => 'secret123', 'status' => 'inactive']);

        $this->post('/login', ['login' => 'off', 'password' => 'secret123'])->assertSessionHasErrors('login');
        $this->assertGuest('web');
        $this->postJson('/api/v1/login', ['login' => 'off', 'password' => 'secret123', 'device_name' => 't'])->assertStatus(422);

        $user->update(['status' => 'active']);
        $this->postJson('/api/v1/login', ['login' => 'off', 'password' => 'secret123', 'device_name' => 't'])->assertOk();
        $this->post('/login', ['login' => 'off', 'password' => 'secret123'])->assertSessionHasNoErrors();
        $this->assertAuthenticatedAs($user, 'web');
    }

    public function test_guard_rails(): void
    {
        $admin = User::factory()->create(['role' => 'admin']);
        foreach (['view', 'edit'] as $p) {
            UserPermission::create(['user_id' => $admin->id, 'module' => 'users', 'permission' => $p, 'granted' => true]);
        }
        $root = User::factory()->create(['role' => 'super_admin']);
        $this->actingAs($admin);

        // A super_admin is neither listed nor editable for an admin.
        $this->get('/users')->assertInertia(fn ($p) => $p->has('users', 1));
        $this->get("/users/{$root->id}/edit")->assertForbidden();
        $this->put("/users/{$root->id}/password", ['generate' => true])->assertForbidden();

        // Nobody switches themselves off, changes their own role, or mints a super_admin.
        $this->put("/users/{$admin->id}", $this->details($admin, ['status' => 'inactive']))->assertSessionHasErrors('status');
        $this->put("/users/{$admin->id}", $this->details($admin, ['role' => 'editor']))->assertSessionHasErrors('role');
        $other = User::factory()->create(['role' => 'editor']);
        $this->put("/users/{$other->id}", $this->details($other, ['role' => 'super_admin']))->assertSessionHasErrors('role');

        // Every admin opens it (permissions and department roles live there
        // now); another account needs the users grant.
        $plain = User::factory()->create(['role' => 'admin']);
        $this->actingAs($plain)->get('/users')->assertOk();
        $editor = User::factory()->create(['role' => 'editor']);
        Sanctum::actingAs($editor);
        $this->getJson('/api/v1/users')->assertForbidden();
        $this->getJson("/api/v1/users/{$other->id}")->assertForbidden();
        $granted = User::factory()->create(['role' => 'editor']);
        UserPermission::create(['user_id' => $granted->id, 'module' => 'users', 'permission' => 'view', 'granted' => true]);
        Sanctum::actingAs($granted);
        $this->getJson('/api/v1/users')->assertOk();
    }

    public function test_the_api_twin(): void
    {
        Sanctum::actingAs(User::factory()->create(['role' => 'super_admin']));
        $user = User::factory()->create(['role' => 'editor']);
        $user->createToken('phone');

        $this->getJson('/api/v1/users')->assertOk()->assertJsonCount(2);
        $this->getJson("/api/v1/users/{$user->id}")->assertOk()->assertJsonPath('is_self', false);

        $this->putJson("/api/v1/users/{$user->id}", $this->details($user, ['status' => 'inactive', 'phone' => '0770']))
            ->assertOk()->assertJsonPath('status', 'inactive');
        $this->assertSame(0, $user->tokens()->count());

        $password = $this->putJson("/api/v1/users/{$user->id}/password", ['generate' => true])
            ->assertOk()->json('password');
        $this->assertTrue(Hash::check($password, $user->refresh()->password));

        // The add-user form's options route still resolves.
        $this->getJson('/api/v1/users/form-options')->assertOk()->assertJsonStructure(['modules']);
    }
}
