<?php

namespace App\Services;

use App\Notifications\OtpPasswordReset;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

/**
 * Replaces the emailed reset *link* (Laravel's stock `Password` facade /
 * `password_reset_tokens` table) with a short-lived, human-typeable
 * numeric code (2026-08-29, by request) — a 40-character URL token is
 * meant to be clicked, not typed, so email-a-code needed genuinely new
 * generation/storage/verification, not a config tweak to the existing
 * broker. Deliberately bypasses `Illuminate\Auth\Passwords\PasswordBroker`
 * entirely rather than trying to coerce it into issuing short codes.
 *
 * `$guard` is `'users'` or `'doctors'` — matches config/auth.php's two
 * broker names, so both account types share this one mechanism/table
 * (`password_reset_otps`) the same way they already shared
 * `password_reset_tokens`.
 */
class OtpPasswordResetBroker
{
    public const EXPIRY_MINUTES = 5;

    /** Matches the old brokers' `throttle` setting (config/auth.php) — one new code per address per minute. */
    private const THROTTLE_SECONDS = 60;

    /**
     * Generates and emails a fresh code, replacing any still-outstanding
     * one for this address — unless one was just issued within
     * {@see THROTTLE_SECONDS}, in which case this is a silent no-op (the
     * caller shows the same neutral "sent" response either way, so this
     * never reveals whether a throttle or a missing account was the
     * reason nothing new went out).
     */
    public static function send(string $email, string $guard, object $notifiable): void
    {
        $existing = DB::table('password_reset_otps')->where('email', $email)->where('guard', $guard)->first();

        if ($existing?->created_at && now()->diffInSeconds($existing->created_at) < self::THROTTLE_SECONDS) {
            return;
        }

        $code = (string) random_int(100000, 999999);

        DB::table('password_reset_otps')->updateOrInsert(
            ['email' => $email, 'guard' => $guard],
            [
                'otp' => Hash::make($code),
                'expires_at' => now()->addMinutes(self::EXPIRY_MINUTES),
                'created_at' => now(),
            ]
        );

        $notifiable->notify(new OtpPasswordReset($code));
    }

    /** Does not consume the code — the caller calls {@see forget()} only after actually changing the password. */
    public static function verify(string $email, string $guard, string $code): bool
    {
        $row = DB::table('password_reset_otps')->where('email', $email)->where('guard', $guard)->first();

        if (! $row || now()->greaterThan($row->expires_at)) {
            return false;
        }

        return Hash::check($code, $row->otp);
    }

    public static function forget(string $email, string $guard): void
    {
        DB::table('password_reset_otps')->where('email', $email)->where('guard', $guard)->delete();
    }
}
