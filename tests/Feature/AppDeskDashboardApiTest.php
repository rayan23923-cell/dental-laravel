<?php

namespace Tests\Feature;

use App\Models\Doctor;
use App\Models\User;
use App\Support\RolePresets;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/** The app's per-role home panels (2026-10-18): each role gets only what it may open. */
class AppDeskDashboardApiTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        foreach (['pending', 'pending', 'clear', 'flagged'] as $status) {
            DB::table('patients_simple')->insert(['name' => 'P', 'phone' => '0770', 'screening_status' => $status, 'created_at' => now()]);
        }
    }

    private function user(string $role): User
    {
        $user = User::factory()->create(['role' => $role]);
        RolePresets::apply($user);

        return $user;
    }

    public function test_the_lab_gets_its_queue_only(): void
    {
        Sanctum::actingAs($this->user('lab'));

        $this->getJson('/api/v1/dashboard/desk')->assertOk()
            ->assertJsonPath('panels.lab.pending', 2)
            ->assertJsonPath('panels.lab.flagged', 1)
            ->assertJsonMissingPath('panels.registrations')
            ->assertJsonMissingPath('panels.payments');
    }

    public function test_the_ticket_desk_gets_registrations_only(): void
    {
        Sanctum::actingAs($this->user('reception'));

        $this->getJson('/api/v1/dashboard/desk')->assertOk()
            ->assertJsonPath('panels.registrations.today', 4)
            ->assertJsonMissingPath('panels.lab')
            ->assertJsonMissingPath('panels.payments');
    }

    public function test_the_accountant_gets_the_income(): void
    {
        Sanctum::actingAs($this->user('accountant'));

        $this->getJson('/api/v1/dashboard/desk')->assertOk()
            ->assertJsonPath('panels.payments.periods.today.total', 0)
            ->assertJsonMissingPath('panels.lab');
    }

    public function test_doctors_are_refused(): void
    {
        \App\Models\EducationType::create(['id' => 1, 'name' => 'صباحي']);
        \App\Models\Stage::create(['id' => 1, 'name' => 'الرابعة', 'education_type_id' => 1]);
        Sanctum::actingAs(Doctor::create([
            'name' => 'د', 'username' => 'd1', 'password' => 'secret', 'email' => 'd1@example.com',
            'education_type_id' => 1, 'stage_id' => 1,
        ]));

        $this->getJson('/api/v1/dashboard/desk')->assertForbidden();
    }
}
