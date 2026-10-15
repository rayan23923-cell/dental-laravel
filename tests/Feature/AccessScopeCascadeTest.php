<?php

namespace Tests\Feature;

use App\Models\Department;
use App\Models\EducationType;
use App\Models\Stage;
use App\Models\User;
use App\Services\ScopeHelper;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * "نطاق الوصول" cascades (2026-10-14): education type → its stages →
 * their departments, both in what an account sees and in what is saved.
 */
class AccessScopeCascadeTest extends TestCase
{
    use RefreshDatabase;

    /** Department id by its stage id. */
    private array $dept = [];

    protected function setUp(): void
    {
        parent::setUp();
        EducationType::create(['id' => 1, 'name' => 'الدراسات الأولية']);
        EducationType::create(['id' => 2, 'name' => 'الموازي']);
        Stage::create(['id' => 1, 'name' => 'الرابعة', 'education_type_id' => 1]);
        Stage::create(['id' => 2, 'name' => 'الخامسة', 'education_type_id' => 1]);
        Stage::create(['id' => 3, 'name' => 'الرابعة', 'education_type_id' => 2]);
        // The same department name in each stage, as at the clinic.
        foreach ([1 => 1, 2 => 1, 3 => 2] as $stage => $type) {
            $this->dept[$stage] = Department::create(['name' => 'جراحة الفم', 'stage_id' => $stage, 'education_type_id' => $type])->id;
        }
    }

    public function test_an_education_type_alone_limits_its_stages_and_departments(): void
    {
        $user = User::factory()->create(['role' => 'admin']);
        ScopeHelper::saveScope($user, ['education_types' => [1]]);

        $this->assertEqualsCanonicalizing([1, 2], ScopeHelper::allowedStageIds($user));
        $this->assertEqualsCanonicalizing([$this->dept[1], $this->dept[2]], ScopeHelper::allowedDepartmentIds($user));
        // What the screen shows as picked stays just the type.
        $this->assertNull(ScopeHelper::chosenStageIds($user));
    }

    public function test_chosen_stages_limit_their_departments(): void
    {
        $user = User::factory()->create(['role' => 'admin']);
        ScopeHelper::saveScope($user, ['education_types' => [1], 'stages' => [2]]);

        $this->assertSame([2], ScopeHelper::allowedStageIds($user));
        $this->assertSame([$this->dept[2]], ScopeHelper::allowedDepartmentIds($user));
    }

    public function test_saving_drops_choices_outside_the_level_above(): void
    {
        Sanctum::actingAs(User::factory()->create(['role' => 'super_admin']));
        $user = User::factory()->create(['role' => 'admin']);

        $this->putJson("/api/v1/permissions/{$user->id}", [
            'grants' => [],
            // Stage 3 and department 3 belong to the other education type.
            'scope' => ['education_types' => [1], 'stages' => [1, 3], 'departments' => [$this->dept[1], $this->dept[3]]],
        ])->assertOk();

        $this->getJson("/api/v1/permissions/{$user->id}")
            ->assertOk()
            ->assertJsonPath('scope.education_types', [1])
            ->assertJsonPath('scope.stages', [1])
            ->assertJsonPath('scope.departments', [$this->dept[1]])
            ->assertJsonPath('scope_options.departments.0.stage_name', fn ($v) => $v !== null)
            ->assertJsonPath('scope_options.stages.0.education_type_id', fn ($v) => $v !== null);
    }

    public function test_an_unrestricted_account_sees_everything(): void
    {
        $user = User::factory()->create(['role' => 'admin']);

        $this->assertNull(ScopeHelper::allowedStageIds($user));
        $this->assertNull(ScopeHelper::allowedDepartmentIds($user));
    }
}
