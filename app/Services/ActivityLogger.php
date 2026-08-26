<?php

namespace App\Services;

use App\Models\ActivityLog;
use App\Models\Doctor;
use Illuminate\Support\Facades\Request as RequestFacade;

/**
 * Writes to the imported user_activity_log table. Named/shaped after the
 * original PHP app's ActivityLogger (see dental_clinics2/includes/
 * ActivityLogger.php and ACTIVITY_LOGGING_GUIDE.md) for continuity, not a
 * byte-for-byte port — this rebuild hooks it in via a model trait
 * (LogsActivity) rather than explicit calls in every controller.
 */
class ActivityLogger
{
    public static function log(string $action, string $module, string $description, ?int $recordId = null, ?array $data = null): void
    {
        $actor = static::currentActor();

        // user_activity_log.user_id is NOT NULL in the source schema — skip
        // logging rather than attempting an insert that would fail when
        // there's no authenticated actor (shouldn't happen in practice,
        // since every loggable route requires auth, but be defensive).
        if ($actor['id'] === null) {
            return;
        }

        ActivityLog::create([
            'user_id' => $actor['id'],
            'username' => $actor['username'],
            'user_role' => $actor['role'],
            'action' => $action,
            'module' => $module,
            'description' => $description,
            'record_id' => $recordId,
            'data' => $data ? json_encode($data) : null,
            'ip_address' => RequestFacade::ip(),
            'request_method' => RequestFacade::method(),
            'request_url' => RequestFacade::fullUrl(),
            'user_agent' => RequestFacade::userAgent(),
        ]);
    }

    /**
     * Resolves the acting user from whichever guard is authenticated —
     * web session (User), doctor session (Doctor), or Sanctum token (User
     * or Doctor). Checked explicitly per guard rather than relying on
     * auth()->user()'s default-guard resolution, since Laravel's container
     * binding for the unnamed Guard contract does not reliably reflect
     * "whichever guard actually authenticated this request" when more than
     * one guard is in play on the same session.
     *
     * @return array{id: ?int, username: ?string, role: string}
     */
    private static function currentActor(): array
    {
        $user = auth('sanctum')->user() ?? auth('web')->user() ?? auth('doctor')->user();

        if ($user instanceof Doctor) {
            return ['id' => $user->id, 'username' => $user->username, 'role' => 'doctor'];
        }

        if ($user) {
            return ['id' => $user->id, 'username' => $user->username, 'role' => $user->role];
        }

        return ['id' => null, 'username' => 'system', 'role' => 'system'];
    }
}
