<?php

namespace App\Services;

use App\Models\Doctor;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Auth;

/**
 * Who may do what with a case sheet — a direct port of the variables the
 * original computes at the top of every `doctor/*.php` sheet.
 *
 * The original (surgery.php:16-26, repeated in all nine sheets):
 *
 *   $is_admin                 = role in [admin, super_admin]
 *   $is_user_with_permissions = user_id set && !doctor_id && !is_admin
 *   $is_view_only             = $is_admin || $is_user_with_permissions
 *   $can_save_case_sheet      = ($case_owner_id === $doctor_id)
 *
 * Read together with `doctor_auth_check.php` ("Allow any logged-in user
 * (doctor_id OR user_id) — individual pages will check permissions") the
 * rule is:
 *
 *   • **any** logged-in principal may *open* a case sheet;
 *   • **all staff are view-only** — admins included; the original ignores
 *     their POST outright (`if (REQUEST_METHOD === 'POST' && !$is_view_only)`);
 *   • a **doctor may save only their own** case, ownership taken from the
 *     record's `doctor_id`, falling back to the task instance's;
 *   • **deleting requires a doctor session** — `ajax/delete_surgery.php`
 *     returns 401 when `$doctor_id` is absent, so staff cannot delete either.
 *
 * The port had this inverted: the sheets were registered staff-only, so
 * staff could edit freely and doctors could not reach their own sheets at
 * all (see README "A pre-existing bug this surfaced").
 */
class CaseSheetAccess
{
    /**
     * Checks the web session's `doctor` guard first (the original context
     * this whole class was built for), falling back to the current
     * request's Sanctum-authenticated principal (2026-08-28, added when
     * `EnforceCaseSheetAccess` was applied to `routes/api.php` too — the
     * mobile API has no `doctor` guard session at all; a Doctor
     * authenticates there as `$request->user()` directly, same as
     * `Api\CaseSheetController::open()` already checks). The web path
     * always resolves first and short-circuits, so this changes nothing
     * for existing web behavior.
     */
    public static function doctor(): ?Doctor
    {
        $doctor = Auth::guard('doctor')->user() ?? request()?->user();

        return $doctor instanceof Doctor ? $doctor : null;
    }

    public static function isDoctor(): bool
    {
        return self::doctor() !== null;
    }

    /**
     * True for every staff principal. Deliberately not narrowed by role:
     * the original treats admins and permissioned users identically here —
     * both view, neither saves.
     */
    public static function isViewOnly(): bool
    {
        return ! self::isDoctor();
    }

    /**
     * Ownership test behind `$can_save_case_sheet`. Records that carry no
     * `doctor_id` (the surgery/treatment satellites, which hang off a parent
     * rather than off a doctor) have no owner to compare against, so they
     * fall through to "not owner-restricted".
     */
    public static function ownsRecord(Model $record): bool
    {
        $doctor = self::doctor();

        if (! $doctor) {
            return false;
        }

        if (! array_key_exists('doctor_id', $record->getAttributes())) {
            return true;
        }

        return (int) $record->doctor_id === $doctor->id;
    }

    public static function hasOwnerColumn(Model $record): bool
    {
        return array_key_exists('doctor_id', $record->getAttributes());
    }

    /**
     * Restricts a listing to the signed-in doctor's own records — the
     * original's `AND doctor_id = ?`, which it adds for doctors and omits
     * for admins and permissioned users.
     */
    public static function scope(Builder $query): Builder
    {
        $doctor = self::doctor();

        return $doctor
            ? $query->where('doctor_id', $doctor->id)
            : $query;
    }
}
