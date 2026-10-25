<?php

namespace Tests\Feature;

use App\Models\User;
use App\Services\OtpPasswordResetBroker;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

/** The fixes from the OWASP Top 10 review (2026-10-25). */
class SecurityHardeningTest extends TestCase
{
    use RefreshDatabase;

    public function test_app_login_locks_after_five_wrong_passwords(): void
    {
        User::factory()->create(['username' => 'staff1', 'password' => Hash::make('right-pass')]);

        for ($i = 0; $i < 5; $i++) {
            $this->postJson('/api/v1/login', ['login' => 'staff1', 'password' => 'wrong', 'device_name' => 't'])
                ->assertStatus(422);
        }

        // Even the right password waits now.
        $this->postJson('/api/v1/login', ['login' => 'staff1', 'password' => 'right-pass', 'device_name' => 't'])
            ->assertStatus(422)
            ->assertJsonPath('errors.login.0', fn ($m) => ! str_contains($m, 'incorrect'));
    }

    public function test_app_login_is_written_to_the_activity_log(): void
    {
        $user = User::factory()->create(['username' => 'staff2', 'password' => Hash::make('right-pass')]);

        $this->postJson('/api/v1/login', ['login' => 'staff2', 'password' => 'right-pass', 'device_name' => 't'])
            ->assertOk();

        $this->assertDatabaseHas('user_activity_log', ['user_id' => $user->id, 'action' => 'login', 'module' => 'auth']);
    }

    public function test_reset_code_is_discarded_after_five_wrong_guesses(): void
    {
        DB::table('password_reset_otps')->insert([
            'email' => 'a@example.com',
            'guard' => 'users',
            'otp' => Hash::make('123456'),
            'expires_at' => now()->addMinutes(5),
            'created_at' => now(),
        ]);

        for ($i = 0; $i < OtpPasswordResetBroker::MAX_WRONG; $i++) {
            $this->assertFalse(OtpPasswordResetBroker::verify('a@example.com', 'users', '000000'));
        }

        // The right code no longer works: it was thrown away.
        $this->assertFalse(OtpPasswordResetBroker::verify('a@example.com', 'users', '123456'));
        $this->assertDatabaseMissing('password_reset_otps', ['email' => 'a@example.com']);
    }

    public function test_switched_off_account_loses_its_web_session(): void
    {
        $user = User::factory()->create(['role' => 'super_admin']);
        $this->actingAs($user)->get('/profile')->assertOk();

        $user->forceFill(['status' => 'inactive'])->save();

        $this->actingAs($user->fresh())->get('/profile')->assertRedirect(route('login'));
        $this->assertGuest('web');
    }

    public function test_responses_carry_security_headers(): void
    {
        $this->get('/login')
            ->assertHeader('X-Frame-Options', 'SAMEORIGIN')
            ->assertHeader('X-Content-Type-Options', 'nosniff')
            ->assertHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
    }

    public function test_public_tv_board_no_longer_lists_patients(): void
    {
        $this->get('/tv')->assertRedirect('/waiting-screen');
        $this->getJson('/api/v1/tv-board')->assertNotFound();
    }
}
