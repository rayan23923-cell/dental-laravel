<?php

namespace Tests\Feature;

use App\Models\ClinicSetting;
use App\Models\Doctor;
use App\Models\EducationType;
use App\Models\Group;
use App\Models\Stage;
use App\Models\User;
use App\Services\DefaultGroups;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class DefaultGroupsTest extends TestCase
{
    use RefreshDatabase;

    private function doctor(string $username, int $stageId): Doctor
    {
        return Doctor::create([
            'name' => "د. {$username}", 'username' => $username, 'password' => 'secret',
            'email' => "{$username}@example.com", 'education_type_id' => 1, 'stage_id' => $stageId,
        ]);
    }

    protected function setUp(): void
    {
        parent::setUp();
        EducationType::create(['id' => 1, 'name' => 'صباحي']);
        Stage::create(['id' => 1, 'name' => 'الرابعة', 'education_type_id' => 1]);
        Stage::create(['id' => 2, 'name' => 'الخامسة', 'education_type_id' => 1]);
        ClinicSetting::current(); // the first call inserts the row and returns it without its id
        ClinicSetting::current()->update(['clinic_working_hours' => 'من 8:30 إلى 15:00']);
    }

    public function test_every_doctor_lands_in_their_stage_group_a_on_every_day(): void
    {
        $ali = $this->doctor('ali', 1);

        $group = $ali->groups()->first();
        $this->assertSame('A', $group->name);
        $this->assertSame(1, (int) $group->stage_id);
        $this->assertCount(7, $group->slots);
        $this->assertStringStartsWith('08:30', $group->slots->first()->start_time);
        $this->assertStringStartsWith('15:00', $group->slots->first()->end_time);

        // A second doctor joins the same group rather than a new one.
        $this->doctor('omar', 1);
        $this->assertSame(1, Group::where('stage_id', 1)->count());
        $this->assertSame(2, $group->doctors()->count());

        // Moved to another stage: out of the old A, into the new stage's A.
        $ali->update(['stage_id' => 2]);
        $this->assertSame([2], $ali->groups()->pluck('stage_id')->map(fn ($id) => (int) $id)->all());
    }

    public function test_sync_keeps_doctors_already_placed_in_another_group(): void
    {
        $ali = $this->doctor('ali', 1);
        $b = Group::create(['name' => 'B', 'stage_id' => 1]);
        $ali->groups()->detach();
        $ali->groups()->attach($b->id, ['added_at' => now()]);

        DefaultGroups::sync();

        $this->assertSame(['B'], $ali->groups()->pluck('name')->all());
        $this->assertTrue(Group::where('stage_id', 2)->where('name', 'A')->exists());
    }

    public function test_turning_groups_off_hides_them_and_task_progress_lists_the_stage(): void
    {
        $this->doctor('ali', 1);
        $this->doctor('omar', 2);
        $admin = User::factory()->create(['role' => 'super_admin']);

        $this->actingAs($admin)->get('/doctors-print')->assertSee('المجموعة');

        $this->put(route('clinic-settings.update'), ['clinic_name' => 'عيادة', 'groups_enabled' => false])->assertSessionHasNoErrors();
        $this->assertFalse(ClinicSetting::current()->groups_enabled);

        $this->get('/doctors-print')->assertOk()->assertDontSee('المجموعة');
        $this->get('/task-progress')->assertInertia(fn ($page) => $page->where('groupsEnabled', false));

        $this->getJson('/task-progress/stages/1')->assertOk()
            ->assertJsonPath('group.id', null)
            ->assertJsonPath('group.stage_id', 1);
    }
}
