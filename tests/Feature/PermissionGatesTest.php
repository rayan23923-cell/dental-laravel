<?php

namespace Tests\Feature;

use App\Models\EducationType;
use App\Models\Stage;
use App\Models\User;
use App\Services\PermissionManager;
use App\Services\ScopeHelper;
use App\Support\RolePresets;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Illuminate\Support\Facades\Cache;
use Tests\TestCase;

/**
 * An account sees only what it was given (2026-10-18, by request: a lab
 * account with no grants could see every section in the app).
 */
class PermissionGatesTest extends TestCase
{
    use RefreshDatabase;

    private function lab(): User
    {
        $lab = User::factory()->create(['role' => 'lab']);
        RolePresets::apply($lab);

        return $lab;
    }

    public function test_a_lab_account_is_refused_everything_outside_the_lab(): void
    {
        $lab = $this->lab();
        Sanctum::actingAs($lab);

        $this->getJson('/api/v1/payments')->assertForbidden();
        $this->getJson('/api/v1/payments/stats')->assertForbidden();
        $this->getJson('/api/v1/appointments')->assertForbidden();
        $this->getJson('/api/v1/groups')->assertForbidden();
        $this->getJson('/api/v1/activity-logs')->assertForbidden();
        $this->getJson('/api/v1/permissions')->assertForbidden();
        $this->postJson('/api/v1/academic-sessions', ['name' => 'x'])->assertForbidden();
        $this->getJson('/api/v1/periodontal-charts')->assertForbidden();
        // Above all, it can't hand itself more.
        $this->putJson("/api/v1/permissions/{$lab->id}", ['grants' => ['users.view']])->assertForbidden();
        $this->assertFalse((new PermissionManager($lab->fresh()))->can('users', 'view'));

        $this->getJson('/api/v1/lab')->assertOk();
    }

    public function test_the_accountant_reads_payments(): void
    {
        $accountant = User::factory()->create(['role' => 'accountant']);
        Sanctum::actingAs($accountant);
        // Payments are a permission since 2026-10-24, the accountant's by default.
        $this->getJson('/api/v1/payments')->assertForbidden();

        RolePresets::apply($accountant);
        Cache::flush();
        $this->getJson('/api/v1/payments')->assertOk();
        $this->getJson('/api/v1/payments/stats')->assertOk();
        $this->postJson('/api/v1/services', ['name' => 'حشوة', 'price' => 5000])->assertSuccessful();
        $this->getJson('/api/v1/groups')->assertForbidden();
    }

    public function test_payments_and_register_settings_follow_their_permissions(): void
    {
        $editor = User::factory()->create(['role' => 'editor']);
        Sanctum::actingAs($editor);
        $this->getJson('/api/v1/payments')->assertForbidden();
        $this->postJson('/api/v1/services', ['name' => 'قلع'])->assertForbidden();
        $this->putJson('/api/v1/register-settings/lab', ['lab_fee' => 2000])->assertForbidden();

        PermissionManager::syncGrants($editor, ['payments.view', 'register_settings.edit']);
        Cache::flush();
        $this->getJson('/api/v1/payments')->assertOk();
        $this->getJson('/api/v1/payments/report')->assertForbidden();
        $this->putJson('/api/v1/register-settings/lab', ['lab_fee' => 2000, 'lab_validity_days' => 30])
            ->assertOk()->assertJsonPath('lab_validity_days', 30);
    }

    public function test_the_accountant_opens_payments_and_register_settings_on_the_web(): void
    {
        $accountant = User::factory()->create(['role' => 'accountant']);
        $this->actingAs($accountant)->get('/payments')->assertForbidden();
        $this->get('/patient-registrations/settings')->assertForbidden();

        RolePresets::apply($accountant);
        Cache::flush();
        $this->get('/payments')->assertOk();
        $this->get('/patient-registrations/settings')->assertOk();
        $this->get('/groups')->assertForbidden();
    }

    public function test_case_sheets_need_the_open_case_sheet_grant(): void
    {
        $editor = User::factory()->create(['role' => 'editor']);
        Sanctum::actingAs($editor);
        $this->getJson('/api/v1/periodontal-charts')->assertForbidden();

        PermissionManager::syncGrants($editor, ['task_progress.open_case_sheet']);
        $this->getJson('/api/v1/periodontal-charts')->assertOk();
    }

    public function test_the_app_gets_the_accounts_grants(): void
    {
        Sanctum::actingAs($this->lab());

        $this->getJson('/api/v1/me')
            ->assertOk()
            ->assertJsonPath('permissions', fn ($p) => collect($p)->sort()->values()->all() === ['patient_screening.confirm', 'patient_screening.view', 'printer_settings.view']);
    }

    public function test_nothing_picked_in_the_scope_means_nothing(): void
    {
        EducationType::create(['id' => 1, 'name' => 'الدراسات الأولية']);
        Stage::create(['id' => 1, 'name' => 'الرابعة', 'education_type_id' => 1]);
        $editor = User::factory()->create(['role' => 'editor']);

        ScopeHelper::saveScope($editor, ['education_types' => [], 'all_education_types' => false, 'all_academic_sessions' => false]);
        $this->assertSame([], ScopeHelper::allowedEducationTypeIds($editor->fresh()));
        $this->assertSame([], ScopeHelper::allowedStageIds($editor->fresh()));
        $this->assertSame([], ScopeHelper::allowedAcademicSessionIds($editor->fresh()));

        ScopeHelper::saveScope($editor, ['all_education_types' => true, 'all_academic_sessions' => true]);
        $this->assertNull(ScopeHelper::allowedEducationTypeIds($editor->fresh()));
        $this->assertNull(ScopeHelper::allowedAcademicSessionIds($editor->fresh()));

        // A stage picked without its type still shows that stage's type.
        ScopeHelper::saveScope($editor, ['stages' => [1], 'all_education_types' => false]);
        $this->assertSame([1], ScopeHelper::allowedEducationTypeIds($editor->fresh()));
        $this->assertSame([1], ScopeHelper::allowedStageIds($editor->fresh()));
    }

    public function test_the_permissions_screen_reads_and_saves_all(): void
    {
        Sanctum::actingAs(User::factory()->create(['role' => 'super_admin']));
        $editor = User::factory()->create(['role' => 'editor']);

        $this->getJson("/api/v1/permissions/{$editor->id}")
            ->assertOk()
            ->assertJsonPath('scope.education_types', null)
            ->assertJsonPath('scope.all_education_types', false);

        $this->putJson("/api/v1/permissions/{$editor->id}", [
            'grants' => [],
            'scope' => ['education_types' => [], 'all_education_types' => true],
        ])->assertOk();
        $this->getJson("/api/v1/permissions/{$editor->id}")->assertJsonPath('scope.all_education_types', true);

        // An app from before "الكل" sends no flag: an empty list still means all.
        $this->putJson("/api/v1/permissions/{$editor->id}", ['grants' => [], 'scope' => ['education_types' => []]])->assertOk();
        $this->assertNull(ScopeHelper::allowedEducationTypeIds($editor->fresh()));
    }

    public function test_admins_with_nothing_picked_still_see_everything(): void
    {
        $this->assertNull(ScopeHelper::allowedEducationTypeIds(User::factory()->create(['role' => 'admin'])));
    }

    public function test_the_waiting_screen_follows_its_own_permission(): void
    {
        $editor = User::factory()->create(['role' => 'editor']);
        Sanctum::actingAs($editor);
        $this->getJson('/api/v1/waiting-screen-settings')->assertForbidden();
        $this->postJson('/api/v1/waiting-screen/pairings/resolve-code', ['code' => '1234'])->assertForbidden();

        PermissionManager::syncGrants($editor, ['waiting_screen.view', 'waiting_screen.pair']);
        Cache::flush();
        $this->getJson('/api/v1/waiting-screen-settings')->assertOk();
        $this->putJson('/api/v1/waiting-screen-settings', [])->assertForbidden();
        $this->postJson('/api/v1/waiting-screen/pairings/resolve-code', ['code' => '1234'])->assertNotFound();

        $this->actingAs($editor)->get('/waiting-screen-settings')->assertOk();
        $this->get('/waiting-screen/pair')->assertOk();
    }
}
