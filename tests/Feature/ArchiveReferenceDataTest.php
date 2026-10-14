<?php

namespace Tests\Feature;

use App\Models\Department;
use App\Models\EducationType;
use App\Models\Stage;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class ArchiveReferenceDataTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        EducationType::create(['id' => 1, 'name' => 'صباحي']);
        Stage::create(['id' => 1, 'name' => 'الرابعة', 'education_type_id' => 1]);
        Stage::create(['id' => 2, 'name' => 'الخامسة', 'education_type_id' => 1]);
        Department::create(['name' => 'الحشوات', 'stage_id' => 1, 'education_type_id' => 1]);
        Department::create(['name' => 'الجراحة', 'stage_id' => 1, 'education_type_id' => 1]);
    }

    public function test_web_refuses_a_linked_stage_and_archives_a_free_one(): void
    {
        $this->actingAs(User::factory()->create(['role' => 'super_admin']));

        $this->delete('/stages/1')->assertSessionHas('error', 'لا يمكن الحذف لأنه مرتبط بـ: 2 قسم.');
        $this->assertNotSoftDeleted('stages', ['id' => 1]);

        $this->delete('/stages/2')->assertSessionHas('success');
        $this->assertSoftDeleted('stages', ['id' => 2]);
        $this->assertSame([1], Stage::pluck('id')->all());
    }

    public function test_api_names_what_is_linked(): void
    {
        Sanctum::actingAs(User::factory()->create(['role' => 'super_admin']));

        $this->deleteJson('/api/v1/stages/1')
            ->assertStatus(422)
            ->assertJsonPath('message', 'لا يمكن الحذف لأنه مرتبط بـ: 2 قسم.')
            ->assertJsonPath('linked.0', ['label' => 'قسم', 'count' => 2]);

        $this->deleteJson('/api/v1/stages/2')->assertNoContent();
        $this->assertSoftDeleted('stages', ['id' => 2]);
    }
}
