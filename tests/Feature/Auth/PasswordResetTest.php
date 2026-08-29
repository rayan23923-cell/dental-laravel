<?php

namespace Tests\Feature\Auth;

use App\Models\User;
use App\Notifications\OtpPasswordReset;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Notification;
use Tests\TestCase;

/**
 * Updated (2026-08-29) for the OTP-based reset flow — replaces the
 * clickable-link one Breeze ships this file with by default. See
 * App\Services\OtpPasswordResetBroker for why: a link's token has
 * nowhere to live but a URL, whereas this app now emails a 6-digit code
 * meant to be typed, not clicked.
 */
class PasswordResetTest extends TestCase
{
    use RefreshDatabase;

    public function test_reset_password_request_screen_can_be_rendered(): void
    {
        $response = $this->get('/forgot-password');

        $response->assertStatus(200);
    }

    public function test_reset_password_code_can_be_requested(): void
    {
        Notification::fake();

        $user = User::factory()->create();

        $this->post('/forgot-password', ['email' => $user->email]);

        Notification::assertSentTo($user, OtpPasswordReset::class);
    }

    public function test_reset_password_screen_can_be_rendered(): void
    {
        $response = $this->get('/reset-password?email=someone@example.com');

        $response->assertStatus(200);
    }

    public function test_password_can_be_reset_with_valid_code(): void
    {
        Notification::fake();

        $user = User::factory()->create();

        $this->post('/forgot-password', ['email' => $user->email]);

        Notification::assertSentTo($user, OtpPasswordReset::class, function ($notification) use ($user) {
            $response = $this->post('/reset-password', [
                'email' => $user->email,
                'otp' => $notification->code,
                'password' => 'password',
                'password_confirmation' => 'password',
            ]);

            $response
                ->assertSessionHasNoErrors()
                ->assertRedirect(route('login'));

            return true;
        });
    }

    public function test_password_reset_fails_with_invalid_code(): void
    {
        Notification::fake();

        $user = User::factory()->create();

        $this->post('/forgot-password', ['email' => $user->email]);

        $response = $this->post('/reset-password', [
            'email' => $user->email,
            'otp' => '000000',
            'password' => 'password',
            'password_confirmation' => 'password',
        ]);

        $response->assertSessionHasErrors('otp');
    }
}
