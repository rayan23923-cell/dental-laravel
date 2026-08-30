<?php

namespace App\Services;

use App\Notifications\OtpPasswordReset;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;

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
 *
 * **Bug fixed (2026-08-29, same day, found live after a production
 * report of "no email arrives")**: `send()` originally called
 * `$notifiable->notify(...)` directly instead of going through
 * `Notifier::send()` like every other notification in this app. Delivery
 * here is synchronous (neither this notification nor `TaskAssigned`
 * implements `ShouldQueue`), so a transport-level exception (SMTP
 * hiccup, etc.) propagated straight up through the controller instead of
 * being caught — the whole HTTP request would fail, which from the
 * client looks identical to "the neutral success response came back but
 * no email showed up," and nothing was logged either way. Routed through
 * `Notifier::send()` now, which both catches and logs failures
 * (`Log::warning('Notification failed', ...)`) and respects the same
 * `enable_notifications` clinic-setting gate every other notification in
 * this app already does — deliberately *not* also gating on the
 * mail-specific `enable_email` toggle the way `TaskAssigned::via()`
 * does, since a password-reset code is a core account-recovery function
 * that shouldn't be silenceable by a routine-notifications preference.
 */
class OtpPasswordResetBroker
{
    public const EXPIRY_MINUTES = 5;

    /** Matches the old brokers' `throttle` setting (config/auth.php) — one new code per address per minute. */
    private const THROTTLE_SECONDS = 60;

    /**
     * Generates and emails a fresh code, replacing any still-outstanding
     * one for this address — unless one was just issued within
     * {@see THROTTLE_SECONDS}, in which case this is a silent no-op *to
     * the caller* (the client always gets the same neutral "sent"
     * response, so this never reveals whether a throttle or a missing
     * account was the reason nothing new went out).
     *
     * **Logging added (2026-08-30)**, after a production report of "no
     * email arrives" that turned out to leave *zero* trace in
     * storage/logs/laravel.log on every attempt, across two rounds of
     * fixes — this throttle branch was the one remaining silent path:
     * unlike a missing account (`Api\PasswordResetController::sendResetLink()`'s
     * own log) or a `Notifier::send()` failure (already logged), hitting
     * the throttle here logged nothing at all, making a same-minute
     * repeat test indistinguishable from a genuine delivery failure.
     *
     * Deliberately `Log::warning()`, not `Log::debug()`, for all three of
     * these new log lines (here and in `sendResetLink()`) — a production
     * environment commonly sets `LOG_LEVEL` above `debug` to cut noise,
     * which would silently drop every `debug()` call before it's ever
     * written, regardless of which code path actually ran. That would
     * reproduce the exact "log stays empty no matter what" symptom this
     * investigation is chasing all by itself, independent of anything
     * else — `Notifier::send()`'s own failure log already uses
     * `warning()`, so matching it is the safer bet until `LOG_LEVEL` is
     * confirmed rather than assumed.
     *
     * **The actual root cause, found (2026-08-30) via two temporary
     * diagnostic routes that proved this method never once updated the
     * row or sent mail in *either* CLI or the real web SAPI, no matter
     * how much real time had passed since the one row created during
     * initial testing**: `now()->diffInSeconds($existing->created_at)`
     * passed the **raw database string** straight to `diffInSeconds()`
     * instead of an explicit `Carbon` instance — confirmed live, a row
     * from over 12 hours earlier was still throttling every request.
     *
     * Wrapping the string in `Carbon::parse()` alone turned out to fix
     * only half the bug (confirmed live — still stuck after that fix
     * alone deployed): `diffInSeconds()` in the Carbon version this app
     * uses returns a **signed** value — negative when the compared date
     * is in the past relative to `now()`, which every stored
     * `created_at` always is by the time this runs again. Any negative
     * number is always `< 60`, so the throttle fired unconditionally
     * regardless of how much time had actually passed, string-parsing
     * bug or not. Replaced the diff entirely with an unambiguous
     * `isFuture()` check on `created_at + THROTTLE_SECONDS` — "is the
     * cooldown window still ahead of us" has no sign convention to get
     * backwards, unlike a diff. See `verify()` below for its own
     * `now()->greaterThan(...)` expiry check, which does *not* have this
     * problem (`greaterThan()` is a plain boolean comparison, not a
     * diff) — only needed the `Carbon::parse()` half of this fix.
     */
    public static function send(string $email, string $guard, object $notifiable): void
    {
        $existing = DB::table('password_reset_otps')->where('email', $email)->where('guard', $guard)->first();

        if ($existing?->created_at && Carbon::parse($existing->created_at)->addSeconds(self::THROTTLE_SECONDS)->isFuture()) {
            Log::warning('Password reset code throttled — one was already issued in the last '.self::THROTTLE_SECONDS.'s', [
                'email' => $email,
                'guard' => $guard,
            ]);

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

        $sent = Notifier::send($notifiable, new OtpPasswordReset($code));

        Log::warning($sent ? 'Password reset code notification dispatched' : 'Password reset code notification not sent (Notifier::send() returned false)', [
            'email' => $email,
            'guard' => $guard,
        ]);
    }

    /** Does not consume the code — the caller calls {@see forget()} only after actually changing the password. */
    public static function verify(string $email, string $guard, string $code): bool
    {
        $row = DB::table('password_reset_otps')->where('email', $email)->where('guard', $guard)->first();

        if (! $row || now()->greaterThan(Carbon::parse($row->expires_at))) {
            return false;
        }

        return Hash::check($code, $row->otp);
    }

    public static function forget(string $email, string $guard): void
    {
        DB::table('password_reset_otps')->where('email', $email)->where('guard', $guard)->delete();
    }
}
