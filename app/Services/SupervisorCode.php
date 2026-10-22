<?php

namespace App\Services;

use App\Models\ClinicSetting;
use App\Models\Task;
use App\Models\User;
use App\Support\FormSettings;
use Illuminate\Support\Carbon;

/**
 * The supervisor code (2026-10-22, by request): a staff member who holds
 * `task_progress.supervisor_code` has a 6-digit code that changes by
 * itself every day or every hour (FormSettings). Typed on a student's
 * account, it starts the student's task, signs a step or completes the
 * case on the supervisor's behalf, as if they had done it from task
 * progress.
 *
 * Nothing is stored: the code is an HMAC of the user and the current
 * period under the app key, so it rotates on its own and differs per
 * supervisor, which also tells us who approved. The code of the period
 * that just ended still works for a few minutes, so a code read just
 * before the change still goes through.
 */
class SupervisorCode
{
    public const DIGITS = 6;

    private const GRACE_MINUTES = 5;

    public static function for(User $user, ?Carbon $at = null): string
    {
        return self::compute($user, self::periodKey($at ?? self::now()));
    }

    /** The code now, its period and when it changes. */
    public static function current(User $user): array
    {
        $now = self::now();
        $period = FormSettings::get()['supervisor_code_period'];

        return [
            'code' => self::for($user, $now),
            'period' => $period,
            'expires_at' => ($period === 'hourly' ? $now->copy()->startOfHour()->addHour() : $now->copy()->startOfDay()->addDay())->toIso8601String(),
        ];
    }

    /**
     * The active supervisor whose code is $code, who may do $permission
     * (a task_progress permission) and sees $task's stage and department.
     */
    public static function resolve(string $code, string $permission, Task $task): ?User
    {
        $code = preg_replace('/\D/', '', $code);
        if (strlen($code) !== self::DIGITS) {
            return null;
        }

        $now = self::now();
        $keys = [self::periodKey($now)];
        $previous = $now->copy()->subMinutes(self::GRACE_MINUTES);
        if (self::periodKey($previous) !== $keys[0]) {
            $keys[] = self::periodKey($previous);
        }

        return User::query()->where('status', 'active')->orderBy('id')->get()
            ->first(function (User $user) use ($code, $keys, $permission, $task) {
                if (! collect($keys)->contains(fn ($key) => hash_equals(self::compute($user, $key), $code))) {
                    return false;
                }
                $permissions = new PermissionManager($user);

                return $permissions->can('task_progress', 'supervisor_code')
                    && $permissions->can('task_progress', $permission)
                    && Task::query()->whereKey($task->id)->where(function ($q) use ($user) {
                        ScopeHelper::scopeStages($q, $user, 'stage_id');
                        ScopeHelper::scopeDepartments($q, $user, 'department_id');
                    })->exists();
            });
    }

    private static function compute(User $user, string $periodKey): string
    {
        $hash = hash_hmac('sha256', "supervisor-code|{$user->id}|{$periodKey}", (string) config('app.key'));
        $number = hexdec(substr($hash, 0, 12)) % (10 ** self::DIGITS);

        return str_pad((string) $number, self::DIGITS, '0', STR_PAD_LEFT);
    }

    private static function periodKey(Carbon $at): string
    {
        return FormSettings::get()['supervisor_code_period'] === 'hourly' ? $at->format('Y-m-d H') : $at->format('Y-m-d');
    }

    /** The clinic's own clock, so a "daily" code changes at its midnight. */
    private static function now(): Carbon
    {
        return Carbon::now(ClinicSetting::current()->clinic_timezone ?: 'Asia/Baghdad');
    }
}
