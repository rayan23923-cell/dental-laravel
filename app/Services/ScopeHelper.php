<?php

namespace App\Services;

use App\Models\AcademicSession;
use App\Models\Department;
use App\Models\DepartmentRoleAssignment;
use App\Models\EducationType;
use App\Models\Stage;
use App\Models\User;
use Illuminate\Contracts\Auth\Authenticatable;
use Illuminate\Support\Facades\DB;

/**
 * Ports the original app's includes/scope_helper.php. Confirmed live via
 * codebase research: read by admin/ajax/departments_crud.php and
 * doctors_crud.php to filter what a non-admin user can see; written by
 * admin/user_permissions_ajax/save_scope_permissions.php.
 *
 * `user_allowed_departments` / `_stages` / `_education_types` are pure
 * pivot tables (composite primary key, no `id`, no model) — queried
 * directly here rather than through Eloquent models, matching their shape.
 *
 * Important semantic carried over from the original (easy to get backwards):
 * a user with **zero** rows in `user_allowed_*` is **unrestricted** (sees
 * everything), not locked out. Restriction only kicks in once at least one
 * row exists for that user.
 *
 * Only `super_admin` is unconditionally unrestricted — verified directly
 * against includes/scope_helper.php's getUserAllowedEducationTypes() /
 * getUserAllowedStages() / getUserAllowedDepartments(), which all check
 * `$_SESSION['role'] === 'super_admin'` only. An earlier version of this
 * port also exempted `admin`, which was never true of the original and
 * would silently under-restrict any `admin`-role user who has scope rows.
 *
 * `allowedDepartmentIds()`/`allowedStageIds()` gained a second restriction
 * source (2026-08-29, by request): a `senior`/`hr` `App\Models\
 * DepartmentRoleAssignment` also restricts visibility to just that user's
 * own department(s)/stage(s) — ported from the original's own
 * `ajax/get_department_tasks.php`, which resolves a Senior/HR viewer's
 * allowed departments from that same table before building their task
 * list. Falls back to it only when `user_allowed_departments`/`_stages`
 * has no rows for the user, so an explicit scope assignment (the admin's
 * "نطاق الوصول" tab) always wins if both exist — the two mechanisms are
 * independent in the original (a department-role assignment never writes
 * to `user_allowed_*`), so this is additive, not a replacement.
 */
class ScopeHelper
{
    /**
     * The scope cascades (2026-10-14, by request): education type → its
     * stages → their departments. When a lower level has no explicit
     * choice, it follows the level above, so an account limited to one
     * education type also only sees that type's stages, departments, and
     * the doctors, groups, tasks and task progress under them, without
     * ticking each stage and department as well.
     */
    public static function allowedDepartmentIds(User $user): ?array
    {
        if ($user->role === 'super_admin') {
            return null; // null = unrestricted
        }

        $ids = static::chosenDepartmentIds($user);
        if ($ids !== null) {
            return $ids;
        }

        $stages = static::allowedStageIds($user);

        return $stages === null ? null : Department::whereIn('stage_id', $stages)->pluck('id')->all();
    }

    public static function allowedStageIds(User $user): ?array
    {
        if ($user->role === 'super_admin') {
            return null;
        }

        $ids = static::chosenStageIds($user);
        if ($ids !== null) {
            return $ids;
        }

        $types = static::allowedEducationTypeIds($user);

        return $types === null ? null : Stage::whereIn('education_type_id', $types)->pluck('id')->all();
    }

    /**
     * What was picked for the account itself (the "نطاق الوصول" rows, or
     * failing those a senior/HR department role), before any cascading;
     * null when nothing is. This is what the permissions screen shows.
     */
    public static function chosenDepartmentIds(User $user): ?array
    {
        $ids = DB::table('user_allowed_departments')->where('user_id', $user->id)->pluck('department_id')->all();
        if ($ids === []) {
            $ids = static::departmentRoleIds($user, 'department_id');
        }

        return $ids === [] ? null : $ids;
    }

    public static function chosenStageIds(User $user): ?array
    {
        $ids = DB::table('user_allowed_stages')->where('user_id', $user->id)->pluck('stage_id')->all();
        if ($ids === []) {
            $ids = static::departmentRoleIds($user, 'stage_id');
        }

        return $ids === [] ? null : $ids;
    }

    /**
     * The choices for the permissions screen (web and app): education
     * types, their stages, and the stages' departments, each carrying its
     * parent so the screen can offer only what belongs to the level above.
     */
    public static function options(): array
    {
        return [
            'departments' => Department::with('stage:id,name')->orderBy('name')->get(['id', 'name', 'stage_id', 'education_type_id'])
                ->map(fn (Department $d) => [
                    'id' => $d->id,
                    'name' => $d->name,
                    // Not 'stage': older app versions read that key as an object.
                    'stage_name' => $d->stage?->name,
                    'stage_id' => $d->stage_id,
                    'education_type_id' => $d->education_type_id,
                ])
                ->values()->all(),
            'stages' => Stage::orderBy('name')->get(['id', 'name', 'education_type_id'])->all(),
            'education_types' => EducationType::orderBy('name')->get(['id', 'name'])->all(),
            'academic_sessions' => AcademicSession::orderByDesc('start_date')->get(['id', 'name'])->all(),
        ];
    }

    /**
     * Saves the "نطاق الوصول" choices, dropping any that no longer belong
     * to the level above (a stage of an education type that was unticked,
     * a department of such a stage), so the saved scope always hangs
     * together whatever the client sent.
     */
    /**
     * Validation for a `scope` payload (the four dimensions, each a list of
     * ids; empty or missing = unrestricted). Shared by every form that
     * saves one.
     */
    public static function rules(): array
    {
        return [
            'scope' => ['nullable', 'array'],
            'scope.departments' => ['nullable', 'array'],
            'scope.departments.*' => ['integer', 'exists:departments,id'],
            'scope.stages' => ['nullable', 'array'],
            'scope.stages.*' => ['integer', 'exists:stages,id'],
            'scope.education_types' => ['nullable', 'array'],
            'scope.education_types.*' => ['integer', 'exists:education_types,id'],
            'scope.academic_sessions' => ['nullable', 'array'],
            'scope.academic_sessions.*' => ['integer', 'exists:academic_sessions,id'],
        ];
    }

    public static function saveScope(User $user, array $scope): void
    {
        $types = array_values(array_unique(array_map('intval', $scope['education_types'] ?? [])));
        $stages = array_values(array_unique(array_map('intval', $scope['stages'] ?? [])));
        $departments = array_values(array_unique(array_map('intval', $scope['departments'] ?? [])));

        if ($types !== [] && $stages !== []) {
            $stages = Stage::whereIn('id', $stages)->whereIn('education_type_id', $types)->pluck('id')->all();
        }
        $parentStages = $stages !== []
            ? $stages
            : ($types !== [] ? Stage::whereIn('education_type_id', $types)->pluck('id')->all() : null);
        if ($parentStages !== null && $departments !== []) {
            $departments = Department::whereIn('id', $departments)->whereIn('stage_id', $parentStages)->pluck('id')->all();
        }

        static::setAllowedEducationTypes($user, $types);
        static::setAllowedStages($user, $stages);
        static::setAllowedDepartments($user, $departments);
        static::setAllowedAcademicSessions($user, array_values(array_unique(array_map('intval', $scope['academic_sessions'] ?? []))));
    }

    /** Shared by both fallbacks above — see the class docblock. */
    private static function departmentRoleIds(User $user, string $column): array
    {
        return DepartmentRoleAssignment::active()
            ->where('user_id', $user->id)
            ->pluck($column)
            ->unique()
            ->values()
            ->all();
    }

    public static function allowedEducationTypeIds(User $user): ?array
    {
        if ($user->role === 'super_admin') {
            return null;
        }

        $ids = DB::table('user_allowed_education_types')->where('user_id', $user->id)->pluck('education_type_id')->all();

        return $ids === [] ? null : $ids;
    }

    /**
     * Fourth scope dimension, added alongside the original's three — not a
     * port, since the original has no academic-session concept at all (see
     * the 2026_08_21_090000 migration). Same "zero rows = unrestricted"
     * rule as its siblings.
     */
    public static function allowedAcademicSessionIds(User $user): ?array
    {
        if ($user->role === 'super_admin') {
            return null;
        }

        $ids = DB::table('user_allowed_academic_sessions')->where('user_id', $user->id)->pluck('academic_session_id')->all();

        return $ids === [] ? null : $ids;
    }

    /**
     * Applies allowedDepartmentIds() as a where-in constraint, no-op if
     * unrestricted. $column defaults to 'id' (querying departments itself);
     * pass 'department_id' when scoping a related table.
     *
     * $user accepts any authenticated principal because the API guard
     * (Sanctum) is shared between staff (User) and doctor (Doctor) tokens
     * — see routes/api.php. `role`-based scoping is a staff-only concept in
     * the original app (`$_SESSION['role']` only exists for admin-panel
     * logins), so a non-User principal (a doctor's own token) is always
     * unrestricted here, same as the original never scoping doctor sessions.
     */
    public static function scopeDepartments($query, Authenticatable $user, string $column = 'id')
    {
        if (! $user instanceof User) {
            return $query;
        }

        $ids = static::allowedDepartmentIds($user);

        return $ids === null ? $query : $query->whereIn($column, $ids);
    }

    public static function scopeStages($query, Authenticatable $user, string $column = 'id')
    {
        if (! $user instanceof User) {
            return $query;
        }

        $ids = static::allowedStageIds($user);

        return $ids === null ? $query : $query->whereIn($column, $ids);
    }

    public static function scopeEducationTypes($query, Authenticatable $user, string $column = 'id')
    {
        if (! $user instanceof User) {
            return $query;
        }

        $ids = static::allowedEducationTypeIds($user);

        return $ids === null ? $query : $query->whereIn($column, $ids);
    }

    /**
     * $column defaults to 'academic_session_id' — unlike the other three
     * dimensions, this is never used to scope its own reference table
     * (there's no "academic session I'm allowed to see" screen the way
     * there's a departments list), only ever a related table's FK column.
     *
     * Includes NULL rows even for a restricted user, unlike the other three
     * scopeX() methods — deliberately. `academic_session_id` is nullable
     * throughout this app specifically to mean "belongs to no particular
     * year, visible under all of them" (doctors/groups/tasks created before
     * the session system, or never assigned one — see the
     * 2026_08_19_120000 migration and every controller that filters by the
     * *selected* session). A department/stage restriction has no such
     * "applies to no year" escape hatch to preserve, so this is not a
     * pattern the other three dimensions need.
     */
    public static function scopeAcademicSessions($query, Authenticatable $user, string $column = 'academic_session_id')
    {
        if (! $user instanceof User) {
            return $query;
        }

        $ids = static::allowedAcademicSessionIds($user);

        return $ids === null
            ? $query
            : $query->where(fn ($q) => $q->whereIn($column, $ids)->orWhereNull($column));
    }

    public static function setAllowedDepartments(User $user, array $departmentIds): void
    {
        DB::table('user_allowed_departments')->where('user_id', $user->id)->delete();
        DB::table('user_allowed_departments')->insert(
            array_map(fn ($id) => ['user_id' => $user->id, 'department_id' => $id], $departmentIds)
        );
    }

    public static function setAllowedStages(User $user, array $stageIds): void
    {
        DB::table('user_allowed_stages')->where('user_id', $user->id)->delete();
        DB::table('user_allowed_stages')->insert(
            array_map(fn ($id) => ['user_id' => $user->id, 'stage_id' => $id], $stageIds)
        );
    }

    public static function setAllowedEducationTypes(User $user, array $educationTypeIds): void
    {
        DB::table('user_allowed_education_types')->where('user_id', $user->id)->delete();
        DB::table('user_allowed_education_types')->insert(
            array_map(fn ($id) => ['user_id' => $user->id, 'education_type_id' => $id], $educationTypeIds)
        );
    }

    public static function setAllowedAcademicSessions(User $user, array $academicSessionIds): void
    {
        DB::table('user_allowed_academic_sessions')->where('user_id', $user->id)->delete();
        DB::table('user_allowed_academic_sessions')->insert(
            array_map(fn ($id) => ['user_id' => $user->id, 'academic_session_id' => $id], $academicSessionIds)
        );
    }
}
