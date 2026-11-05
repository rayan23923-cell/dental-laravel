<?php

namespace Tests\Feature;

use App\Models\Doctor;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Inertia\Testing\AssertableInertia as Assert;
use Tests\TestCase;

/**
 * The installed web app opens the system itself, and the offline server's
 * front page links its certificate page over plain http (2026-11-05).
 */
class OfflineStartPageTest extends TestCase
{
    use RefreshDatabase;

    private function doctor(): Doctor
    {
        DB::statement('SET FOREIGN_KEY_CHECKS=0');
        $doctor = Doctor::create([
            'name' => 'د. علي', 'username' => 'ali', 'password' => 'secret', 'email' => 'ali@example.com',
            'education_type_id' => 1, 'stage_id' => 1,
        ]);
        DB::statement('SET FOREIGN_KEY_CHECKS=1');

        return $doctor;
    }

    public function test_installed_app_start_goes_to_login_or_straight_into_the_system(): void
    {
        $this->get('/start')->assertRedirect(route('login'));

        $user = User::factory()->create(['role' => 'admin', 'status' => 'active']);
        $this->actingAs($user)->get('/start')->assertRedirect(route('dashboard'));
    }

    public function test_installed_app_start_sends_a_doctor_to_their_dashboard(): void
    {
        $this->actingAs($this->doctor(), 'doctor')->get('/start')->assertRedirect(route('doctor.dashboard'));
    }

    public function test_offline_front_page_links_setup_over_http_and_skips_when_signed_in(): void
    {
        config(['offline.edition' => true, 'offline.activation' => false, 'offline.http_port' => 8080]);

        $this->get('https://clinic.lan/')->assertOk()
            ->assertInertia(fn (Assert $page) => $page->component('Welcome')->where('setupUrl', 'http://clinic.lan:8080/setup'));

        $user = User::factory()->create(['role' => 'admin', 'status' => 'active']);
        $this->actingAs($user)->get('http://clinic.lan/')->assertRedirect(route('dashboard'));
    }

    public function test_hosted_front_page_is_unchanged(): void
    {
        config(['offline.edition' => false]);

        $this->get('/')->assertOk()->assertInertia(fn (Assert $page) => $page->component('Welcome')->where('setupUrl', null));

        $user = User::factory()->create(['role' => 'admin', 'status' => 'active']);
        $this->actingAs($user)->get('/')->assertOk();
    }
}
