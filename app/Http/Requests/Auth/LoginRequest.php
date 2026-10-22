<?php

namespace App\Http\Requests\Auth;

use Illuminate\Auth\Events\Lockout;
use Illuminate\Contracts\Validation\ValidationRule;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class LoginRequest extends FormRequest
{
    /**
     * Determine if the user is authorized to make this request.
     */
    public function authorize(): bool
    {
        return true;
    }

    /**
     * Get the validation rules that apply to the request.
     *
     * @return array<string, ValidationRule|array<mixed>|string>
     */
    public function rules(): array
    {
        return [
            // One field, either a username or an email — see authenticate()
            // for how the two are told apart. Kept as a single input rather
            // than two, matching how the login form itself presents it.
            'login' => ['required', 'string'],
            'password' => ['required', 'string'],
        ];
    }

    /**
     * Attempt to authenticate the request's credentials — against the
     * staff `web` guard first, then the `doctor` guard, so one login form
     * serves both account types without asking which one the visitor is.
     * Whichever guard's `attempt()` succeeds is the one left logged in;
     * `AuthenticatedSessionController::store()` reads that back to pick
     * the right post-login redirect.
     *
     * @throws ValidationException
     */
    public function authenticate(): void
    {
        $this->ensureIsNotRateLimited();

        $field = filter_var($this->input('login'), FILTER_VALIDATE_EMAIL) ? 'email' : 'username';
        $credentials = [$field => $this->input('login'), 'password' => $this->input('password')];

        // A staff account switched off on the users page can't sign in
        // (2026-10-21); the doctor guard is still tried, as before.
        $staff = $credentials + ['status' => fn ($q) => $q->where('status', '!=', 'inactive')];
        $authenticated = Auth::guard('web')->attempt($staff, $this->boolean('remember'))
            || Auth::guard('doctor')->attempt($credentials, $this->boolean('remember'));

        if (! $authenticated) {
            RateLimiter::hit($this->throttleKey());

            throw ValidationException::withMessages([
                'login' => trans('auth.failed'),
            ]);
        }

        RateLimiter::clear($this->throttleKey());
    }

    /**
     * Ensure the login request is not rate limited.
     *
     * @throws ValidationException
     */
    public function ensureIsNotRateLimited(): void
    {
        if (! RateLimiter::tooManyAttempts($this->throttleKey(), 5)) {
            return;
        }

        event(new Lockout($this));

        $seconds = RateLimiter::availableIn($this->throttleKey());

        throw ValidationException::withMessages([
            'login' => trans('auth.throttle', [
                'seconds' => $seconds,
                'minutes' => ceil($seconds / 60),
            ]),
        ]);
    }

    /**
     * Get the rate limiting throttle key for the request.
     */
    public function throttleKey(): string
    {
        return Str::transliterate(Str::lower($this->string('login')).'|'.$this->ip());
    }
}
