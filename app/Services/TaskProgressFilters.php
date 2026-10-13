<?php

namespace App\Services;

use App\Models\EducationType;
use App\Models\Group;
use App\Models\Stage;
use App\Models\User;
use Illuminate\Support\Facades\DB;

/**
 * The day -> education type/stage -> group filter data for the admin
 * task-progress screen — extracted from `TaskProgressController::index()`
 * so the web page (Inertia props) and the Flutter API endpoint can share
 * one implementation rather than keeping two copies of this query in sync.
 *
 * Keys are snake_case throughout (the shape the API returns as-is); the
 * web controller maps this onto its existing camelCase Inertia prop names.
 */
class TaskProgressFilters
{
    // $academicSessionId — see TaskProgressGroupSummary::build()'s doc
    // comment; same convention. Previously this group list was scoped
    // only by ScopeHelper::scopeAcademicSessions() (which sessions the
    // *user* is permitted to see, a permission check) with no default-to-
    // current filter — a past year's groups showed up here right
    // alongside the current one.
    public static function build(User $user, ?string $day, ?int $educationTypeId, ?int $stageId, ?int $academicSessionId = null): array
    {
        // Days that any group actually has a slot on, in the original's
        // explicit week order (FIELD(day, ...) in the source query) rather
        // than alphabetical.
        $dayOrder = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
        $days = DB::table('group_slots')->distinct()->pluck('day')
            ->sortBy(fn ($d) => array_search($d, $dayOrder, true))
            ->values();

        $stages = [];
        if ($educationTypeId) {
            $stages = ScopeHelper::scopeStages(
                Stage::where('education_type_id', $educationTypeId),
                $user
            )->orderBy('name')->get(['id', 'name']);
        }

        // The day filter is gone from the screens (2026-10-13, by request:
        // "ازل اليوم"): groups list once a stage is chosen. A day sent by an
        // older app still narrows the list.
        $groups = [];
        if ($day || $stageId) {
            $query = Group::query()
                ->when($day, fn ($q, $d) => $q->whereHas('slots', fn ($q2) => $q2->where('day', $d)))
                ->with(['stage.educationType'])
                ->when($stageId, fn ($q, $id) => $q->where('stage_id', $id))
                ->when($educationTypeId, fn ($q, $id) => $q->whereHas('stage', fn ($q2) => $q2->where('education_type_id', $id)))
                ->when($academicSessionId, fn ($q) => $q->where(
                    fn ($q2) => $q2->where('academic_session_id', $academicSessionId)->orWhereNull('academic_session_id')
                ));

            $groups = ScopeHelper::scopeAcademicSessions(ScopeHelper::scopeStages($query, $user, 'stage_id'), $user)
                ->orderBy('name')->get()
                ->map(fn ($g) => [
                    'id' => $g->id,
                    'name' => $g->name,
                    'stage_name' => $g->stage?->name,
                    'education_type_name' => $g->stage?->educationType?->name,
                ]);
        }

        return [
            'days' => $days,
            'education_types' => ScopeHelper::scopeEducationTypes(EducationType::query(), $user)->orderBy('name')->get(['id', 'name']),
            'stages' => $stages,
            'groups' => $groups,
            'filters' => [
                'day' => $day,
                'education_type' => $educationTypeId,
                'stage' => $stageId,
            ],
        ];
    }
}
