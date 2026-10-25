<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\DoctorResource;
use App\Http\Resources\UserResource;
use App\Models\Doctor;
use App\Models\User;
use App\Listeners\AuthEventLogger;
use App\Support\IpGeolocator;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Auth\Events\Lockout;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

/**
 * Token-based authentication for the mobile (Flutter) client, backed by
 * Laravel Sanctum personal access tokens. Separate from the web session
 * auth used by the Inertia app (routes/web.php, auth.php).
 */
class AuthController extends Controller
{
    /**
     * Unified staff-or-doctor login. One `login` field (email or
     * username, auto-detected the same way `App\Http\Requests\Auth\LoginRequest`
     * does for the web) — tries `users` first, then `doctors`, so the
     * Flutter client never has to ask which kind of account this is
     * before submitting. `account_type` in the response tells the client
     * which resource shape `user`/`doctor` is and which one to persist
     * for session restore (see `AccountType` on the Flutter side).
     */
    public function login(Request $request): JsonResponse
    {
        $credentials = $request->validate([
            'login' => ['required', 'string'],
            'password' => ['required', 'string'],
            'device_name' => ['required', 'string'],
        ]);

        // Same brake as the web login (LoginRequest): 5 wrong passwords per
        // login name and address, then a wait (2026-10-25, security review).
        $throttleKey = Str::transliterate(Str::lower($credentials['login']).'|'.$request->ip());
        if (RateLimiter::tooManyAttempts($throttleKey, 5)) {
            event(new Lockout($request));
            $seconds = RateLimiter::availableIn($throttleKey);

            throw ValidationException::withMessages([
                'login' => [trans('auth.throttle', ['seconds' => $seconds, 'minutes' => ceil($seconds / 60)])],
            ]);
        }

        $field = filter_var($credentials['login'], FILTER_VALIDATE_EMAIL) ? 'email' : 'username';

        $user = User::where($field, $credentials['login'])->first();

        // Accounts switched off on the users page can't sign in (2026-10-21).
        if ($user && $user->status !== 'inactive' && Hash::check($credentials['password'], $user->password)) {
            RateLimiter::clear($throttleKey);
            $token = $user->createToken($credentials['device_name']);
            $this->recordSessionMeta($token->accessToken, $request);
            AuthEventLogger::loggedIn($user, 'api');

            return response()->json([
                'token' => $token->plainTextToken,
                'account_type' => 'staff',
                'user' => new UserResource($user),
            ]);
        }

        $doctor = Doctor::where($field, $credentials['login'])->first();

        if ($doctor && Hash::check($credentials['password'], $doctor->password)) {
            RateLimiter::clear($throttleKey);
            $token = $doctor->createToken($credentials['device_name']);
            $this->recordSessionMeta($token->accessToken, $request);
            AuthEventLogger::loggedIn($doctor, 'api');

            return response()->json([
                'token' => $token->plainTextToken,
                'account_type' => 'doctor',
                'doctor' => new DoctorResource($doctor),
            ]);
        }

        RateLimiter::hit($throttleKey);
        AuthEventLogger::failed($credentials['login'], 'api');

        throw ValidationException::withMessages([
            'login' => ['The provided credentials are incorrect.'],
        ]);
    }

    /**
     * IP + best-effort location, captured once at token creation for the
     * "Active sessions" screen (`Api\SessionController`) — see
     * `App\Support\IpGeolocator`'s own doc comment for why this is a
     * cached, one-time lookup rather than resolved live on every list
     * request.
     */
    private function recordSessionMeta(\Laravel\Sanctum\PersonalAccessToken $token, Request $request): void
    {
        $ip = $request->ip();

        $token->forceFill([
            'ip_address' => $ip,
            'location' => IpGeolocator::locate($ip),
        ])->save();
    }

    public function logout(Request $request): JsonResponse
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json(['message' => 'Logged out.']);
    }

    public function me(Request $request): JsonResponse
    {
        $user = $request->user();

        return response()->json(
            $user instanceof Doctor ? new DoctorResource($user) : new UserResource($user)
        );
    }
}
