<?php

namespace App\Support;

use App\Models\Doctor;
use App\Models\User;
use App\Services\PermissionManager;

/**
 * Whether the currently authenticated principal may see a task instance's
 * student/staff identity fields (doctor name+username, who started it) —
 * requested so that scanning a printed task receipt's QR shows that
 * context, but only to staff who are actually allowed to see it, not to
 * every authenticated user who happens to scan the code.
 *
 * A doctor viewing their own instance (`TaskInstanceController::show()`/
 * `TaskInstanceQrController::scan()` already enforce that ownership check
 * before this is ever consulted) already knows who they are — always
 * visible. A staff `User` needs to be an admin or hold the same
 * `task_progress,view` permission that already gates the Task Progress
 * screen this QR scanner is reached from (`routes/api.php`'s
 * `permission:task_progress,view` on `filters()`/`group()`) — reusing that
 * permission rather than inventing a new module for one field.
 */
class TaskInstanceVisibility
{
    public static function canSeeStudentInfo(Doctor|User|null $principal): bool
    {
        if ($principal instanceof Doctor) {
            return true;
        }

        if ($principal instanceof User) {
            $permissions = new PermissionManager($principal);

            return $permissions->isAdmin() || $permissions->canView('task_progress');
        }

        return false;
    }
}
