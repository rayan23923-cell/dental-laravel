<?php

namespace App\Support;

use App\Models\AcademicSession;
use App\Models\CaseSheetType;
use App\Models\Department;
use App\Models\Doctor;
use App\Models\EducationType;
use App\Models\Group;
use App\Models\Stage;
use App\Models\Task;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Safe deletion for the reference data (2026-10-14, by request): nothing
 * can be removed while other data points at it (a stage with departments,
 * a doctor with task cases, ...), and the refusal names what is linked.
 * What can go is archived (soft deleted), never erased.
 *
 * Each model lists the tables that reference it as [table, column, label];
 * tables or columns a given install lacks are skipped, and rows already
 * archived in a soft-deleting table don't count.
 */
class LinkedRecords
{
    private const LINKS = [
        EducationType::class => [
            ['stages', 'education_type_id', 'مرحلة'],
            ['departments', 'education_type_id', 'قسم'],
            ['doctors', 'education_type_id', 'طبيب'],
        ],
        Stage::class => [
            ['departments', 'stage_id', 'قسم'],
            ['doctors', 'stage_id', 'طبيب'],
            ['groups', 'stage_id', 'مجموعة'],
            ['tasks', 'stage_id', 'مهمة'],
            ['patients', 'stage_id', 'مريض'],
        ],
        Department::class => [
            ['tasks', 'department_id', 'مهمة'],
            ['department_role_assignments', 'department_id', 'دور قسم'],
        ],
        CaseSheetType::class => [
            ['tasks', 'case_sheet_type_id', 'مهمة'],
        ],
        AcademicSession::class => [
            ['groups', 'academic_session_id', 'مجموعة'],
            ['tasks', 'academic_session_id', 'مهمة'],
            ['doctors', 'academic_session_id', 'طبيب'],
            ['doctor_group_members', 'academic_session_id', 'عضوية مجموعة'],
        ],
        Group::class => [
            ['doctor_group_members', 'group_id', 'طبيب'],
            ['patients', 'group_id', 'مريض'],
        ],
        Doctor::class => [
            ['task_instances', 'doctor_id', 'حالة مهمة'],
            ['task_progress', 'doctor_id', 'تقدم مهمة'],
            ['doctor_group_members', 'doctor_id', 'مجموعة'],
            ['patients', 'doctor_id', 'مريض'],
            ['appointments', 'doctor_id', 'موعد'],
            ['dental_charts', 'doctor_id', 'استمارة'],
            ['surgeries', 'doctor_id', 'استمارة جراحة'],
        ],
        Task::class => [
            ['task_instances', 'task_id', 'حالة مهمة'],
            ['task_progress', 'task_id', 'تقدم مهمة'],
            ['patients_simple', 'task_id', 'تسجيل مريض'],
            ['appointments', 'task_id', 'موعد'],
            ['dental_charts', 'task_id', 'استمارة'],
        ],
    ];

    /** @return list<array{label: string, count: int}> what still points at $model */
    public static function for(Model $model): array
    {
        $out = [];
        foreach (self::LINKS[$model::class] ?? [] as [$table, $column, $label]) {
            if (! Schema::hasTable($table) || ! Schema::hasColumn($table, $column)) {
                continue;
            }
            $query = DB::table($table)->where($column, $model->getKey());
            if (Schema::hasColumn($table, 'deleted_at')) {
                $query->whereNull('deleted_at');
            }
            $count = $query->count();
            if ($count > 0) {
                $out[] = ['label' => $label, 'count' => $count];
            }
        }

        return $out;
    }

    /** "لا يمكن الحذف لأنه مرتبط بـ: 3 قسم، 12 حالة مهمة", or null when nothing is linked. */
    public static function message(Model $model): ?string
    {
        $links = self::for($model);
        if ($links === []) {
            return null;
        }

        $parts = array_map(fn ($l) => "{$l['count']} {$l['label']}", $links);

        return 'لا يمكن الحذف لأنه مرتبط بـ: '.implode('، ', $parts).'.';
    }
}
