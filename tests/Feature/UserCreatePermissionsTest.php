<?php

namespace Tests\Feature;

use App\Models\EducationType;
use App\Models\Stage;
use App\Models\User;
use App\Services\ScopeHelper;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Adding a user sets its permissions and access scope on the same form
 * (2026-10-14, by request), on the web and through the API.
 */
class UserCreatePermissionsTest extends TestCase
{
    use RefreshDatabase;

    private function account(string $username, array $extra = []): array
    {
        return ['full_name' => 'New User', 'username' => $username, 'email' => "{$username}@example.com", 'password' => 'secret123', 'role' => 'editor'] + $extra;
    }

    public function test_the_web_form_saves_the_picked_grants_and_scope(): void
    {
        EducationType::create(['id' => 1, 'name' => 'الدراسات الأولية']);
        Stage::create(['id' => 1, 'name' => 'الرابعة', 'education_type_id' => 1]);
        $this->actingAs(User::factory()->create(['role' => 'super_admin']));

        $this->get('/users/create')->assertOk()
            ->assertInertia(fn ($p) => $p->has('modules')->has('scopeOptions.stages', 1)->where('roleDefaults.reception', ['patients.view', 'patients.create']));

        $this->post('/users', $this->account('web', [
            'grants' => ['doctors.view', 'tasks.view'],
            'scope' => ['education_types' => [1], 'stages' => [1]],
        ]))->assertSessionHasNoErrors()->assertRedirect(route('permissions.index'));

        $user = User::where('username', 'web')->firstOrFail();
        $this->assertDatabaseHas('user_permissions', ['user_id' => $user->id, 'module' => 'doctors', 'permission' => 'view', 'granted' => true]);
        $this->assertDatabaseHas('user_permissions', ['user_id' => $user->id, 'module' => 'doctors', 'permission' => 'delete', 'granted' => false]);
        $this->assertSame([1], ScopeHelper::allowedEducationTypeIds($user));
        $this->assertSame([1], ScopeHelper::chosenStageIds($user));
    }

    public function test_unticking_a_role_preset_is_kept(): void
    {
        $this->actingAs(User::factory()->create(['role' => 'super_admin']));

        $this->post('/users', $this->account('desk', ['role' => 'reception', 'grants' => ['patients.view']]))
            ->assertSessionHasNoErrors();

        $user = User::where('username', 'desk')->firstOrFail();
        $this->assertDatabaseHas('user_permissions', ['user_id' => $user->id, 'module' => 'patients', 'permission' => 'create', 'granted' => false]);
    }

    public function test_the_api_offers_the_editor_and_saves_it(): void
    {
        Sanctum::actingAs(User::factory()->create(['role' => 'super_admin']));

        $this->getJson('/api/v1/users/form-options')->assertOk()
            ->assertJsonStructure(['modules', 'scope_options' => ['departments', 'stages', 'education_types', 'academic_sessions'], 'role_defaults'])
            ->assertJsonPath('role_defaults.lab', ['patient_screening.view', 'patient_screening.confirm']);

        $this->postJson('/api/v1/users', $this->account('app', ['grants' => ['tasks.view']]))->assertCreated();

        $user = User::where('username', 'app')->firstOrFail();
        $this->assertDatabaseHas('user_permissions', ['user_id' => $user->id, 'module' => 'tasks', 'permission' => 'view', 'granted' => true]);
    }
}
