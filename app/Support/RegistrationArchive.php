<?php

namespace App\Support;

use App\Models\PatientRegistration;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Where an archived patient disappears from (2026-11-02, by request):
 * the patients list, the lab list, or both. "Both" is the soft delete the
 * archive always used (payments stay); the other two only hide the row
 * from one list. One archive tab lists all three and restores them.
 */
class RegistrationArchive
{
    public const SCOPES = ['both', 'patients', 'lab'];

    /** Archives what $query matches; returns how many rows. */
    public static function archive(Builder $query, string $scope): int
    {
        return match ($scope) {
            'patients' => $query->update(['registry_archived_at' => now()]),
            'lab' => $query->update(['lab_archived_at' => now()]),
            default => $query->delete(),
        };
    }

    /** The patients list: not archived from it in any way. */
    public static function currentRegistry(Builder $query): Builder
    {
        return $query->whereNull('registry_archived_at');
    }

    /** The archive tab: anything archived, from either list or both. */
    public static function archived(Builder $query): Builder
    {
        return $query->withTrashed()->where(fn ($q) => $q
            ->whereNotNull('deleted_at')
            ->orWhereNotNull('registry_archived_at')
            ->orWhereNotNull('lab_archived_at'));
    }

    /** The lab list leaves out patients archived from it. */
    public static function currentLab(Builder $query): Builder
    {
        return $query->whereNull('lab_archived_at');
    }

    /** Back on both lists. */
    public static function restore(array $ids): int
    {
        return PatientRegistration::withTrashed()
            ->whereIn('id', $ids)
            ->where(fn ($q) => $q
                ->whereNotNull('deleted_at')
                ->orWhereNotNull('registry_archived_at')
                ->orWhereNotNull('lab_archived_at'))
            ->update(['deleted_at' => null, 'registry_archived_at' => null, 'lab_archived_at' => null]);
    }

    /**
     * Permanent delete from the archive (2026-11-02, by request, behind the
     * user's password): only already-archived registrations, with their
     * payments; appointments, tasks and care codes just lose the link.
     */
    public static function purge(Builder $archivedQuery): int
    {
        $ids = (clone $archivedQuery)->pluck('id')->all();
        if ($ids === []) {
            return 0;
        }

        return DB::transaction(function () use ($ids) {
            foreach (array_chunk($ids, 500) as $chunk) {
                DB::table('payments')->whereIn('patient_registration_id', $chunk)->delete();
                foreach (['appointments', 'task_instances', 'support_codes'] as $table) {
                    if (Schema::hasTable($table) && Schema::hasColumn($table, 'patient_registration_id')) {
                        DB::table($table)->whereIn('patient_registration_id', $chunk)->update(['patient_registration_id' => null]);
                    }
                }
            }

            return PatientRegistration::withTrashed()->whereIn('id', $ids)->forceDelete();
        });
    }

    /** 'both' | 'patients' | 'lab' | null, for the archive tab's label. */
    public static function scopeOf(PatientRegistration $registration): ?string
    {
        if ($registration->deleted_at !== null
            || ($registration->registry_archived_at !== null && $registration->lab_archived_at !== null)) {
            return 'both';
        }
        if ($registration->registry_archived_at !== null) {
            return 'patients';
        }

        return $registration->lab_archived_at !== null ? 'lab' : null;
    }
}
