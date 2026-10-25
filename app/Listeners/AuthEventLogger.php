<?php

namespace App\Listeners;

use App\Models\ActivityLog;
use App\Models\Doctor;
use Illuminate\Auth\Events\Lockout;
use Illuminate\Auth\Events\Login;
use Illuminate\Auth\Events\PasswordReset;
use Illuminate\Contracts\Auth\Authenticatable;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Request as RequestFacade;

/**
 * Sign-ins on the activity log page, failed ones and lockouts in the
 * Laravel log (2026-10-25, security review: nothing recorded who signed in,
 * from where, or a run of wrong passwords). Found by event discovery.
 *
 * A failed attempt has no account to put on user_activity_log (user_id is
 * NOT NULL there), so it goes to storage/logs instead, with the login name
 * and address but never the password.
 */
class AuthEventLogger
{
    public function handleLogin(Login $event): void
    {
        static::loggedIn($event->user, $event->guard);
    }

    public function handleLockout(Lockout $event): void
    {
        Log::warning('Sign-in locked out after repeated wrong passwords', [
            'login' => (string) $event->request->input('login', $event->request->input('username', '')),
            'ip' => $event->request->ip(),
            'url' => $event->request->path(),
        ]);
    }

    public function handlePasswordReset(PasswordReset $event): void
    {
        static::write($event->user, 'password_reset', 'Password reset with an emailed code');
    }

    /** Also called by the token login (Api\AuthController), which fires no Login event. */
    public static function loggedIn(Authenticatable $user, string $guard): void
    {
        static::write($user, 'login', "Signed in ({$guard})");
    }

    public static function failed(string $login, string $guard): void
    {
        Log::warning('Failed sign-in', [
            'login' => $login,
            'guard' => $guard,
            'ip' => RequestFacade::ip(),
            'user_agent' => RequestFacade::userAgent(),
        ]);
    }

    private static function write(Authenticatable $user, string $action, string $description): void
    {
        // The licensing portal's accounts live in their own table.
        if (! $user instanceof Doctor && ! $user instanceof \App\Models\User) {
            return;
        }

        try {
            ActivityLog::create([
                'user_id' => $user->id,
                'username' => $user->username,
                'user_role' => $user instanceof Doctor ? 'doctor' : $user->role,
                'action' => $action,
                'module' => 'auth',
                'description' => $description,
                'ip_address' => RequestFacade::ip(),
                'request_method' => RequestFacade::method(),
                'request_url' => RequestFacade::url(),
                'user_agent' => RequestFacade::userAgent(),
            ]);
        } catch (\Throwable $e) {
            // A logging problem must never block a sign-in.
            Log::warning('Could not write the sign-in to the activity log', ['error' => $e->getMessage()]);
        }
    }
}
