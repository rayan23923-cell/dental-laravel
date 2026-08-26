<?php

namespace App\Http\Controllers;

use App\Models\Doctor;
use App\Models\EducationType;
use App\Models\Group;
use App\Models\Stage;
use App\Services\AcademicSessionHelper;
use App\Services\ScopeHelper;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Ports admin/manage_groups.php + its ajax family (load_groups.php,
 * add_group.php, update_group.php, add/remove_multiple_doctors_to_group.php,
 * get_available_doctors.php). Only the multi-select doctor-management flow
 * is ported — the original also has an older single-add form
 * (load_group_doctors.php / get_doctors_by_group.php) explicitly superseded
 * by the multi-select modal, so it's skipped here (see README.md).
 */
class GroupController extends Controller
{
    public function index(Request $request): Response
    {
        $user = $request->user();

        $query = Group::with(['stage.educationType', 'doctors:id,name,email'])
            ->when($request->integer('stage_id'), fn ($q, $stageId) => $q->where('stage_id', $stageId));

        // Matches load_groups.php: session-scoped groups plus legacy groups
        // with no session at all. Skipped entirely on a fresh install with
        // no academic_sessions rows yet (resolveId() returns null) — every
        // group is necessarily session-less at that point anyway.
        $selectedSession = AcademicSessionHelper::resolve();
        $selectedSessionId = $selectedSession?->id;
        if ($selectedSessionId !== null) {
            $query->where(function ($q) use ($selectedSessionId) {
                $q->where('academic_session_id', $selectedSessionId)
                    ->orWhereNull('academic_session_id');
            });
        }

        $query = ScopeHelper::scopeStages($query, $user, 'stage_id');
        $query = ScopeHelper::scopeAcademicSessions($query, $user);

        // The original only lists groups once a filter has been applied
        // ("عرض المجموعات") rather than dumping every group on load.
        $shouldLoad = $request->boolean('loaded') || $request->filled('stage_id');

        $groups = $shouldLoad
            ? $query->orderBy('name')->get()->map(fn ($group) => [
                'id' => $group->id,
                'name' => $group->name,
                'stage' => $group->stage,
                'doctors' => $group->doctors->map(fn ($d) => ['id' => $d->id, 'name' => $d->name, 'email' => $d->email]),
                'slots' => $group->slots()->orderBy('day')->get(),
            ])
            : collect();

        return Inertia::render('Groups/Index', [
            'groups' => $groups->values(),
            'loaded' => $shouldLoad,
            'educationTypes' => ScopeHelper::scopeEducationTypes(EducationType::query(), $user)->orderBy('name')->get(['id', 'name']),
            'stages' => ScopeHelper::scopeStages(Stage::query(), $user)->orderBy('name')->get(['id', 'name', 'education_type_id']),
            'filters' => $request->only('stage_id', 'education_type_id'),
            // Shown as a banner so it's clear which academic year the groups
            // being created/edited belong to.
            'currentSession' => $selectedSession?->only('id', 'name'),
        ]);
    }

    public function store(Request $request): RedirectResponse
    {
        $validated = $this->validateGroup($request);

        DB::transaction(function () use ($validated) {
            $group = Group::create([
                'name' => $validated['name'],
                'stage_id' => $validated['stage_id'],
                'academic_session_id' => AcademicSessionHelper::resolveId(),
            ]);

            $group->slots()->createMany($validated['slots']);
        });

        return back()->with('success', 'Group added.');
    }

    public function update(Request $request, Group $group): RedirectResponse
    {
        $validated = $this->validateGroup($request);

        DB::transaction(function () use ($validated, $group) {
            $group->update([
                'name' => $validated['name'],
                'stage_id' => $validated['stage_id'],
            ]);

            $group->slots()->delete();
            $group->slots()->createMany($validated['slots']);
        });

        return back()->with('success', 'Group updated.');
    }

    public function destroy(Group $group): RedirectResponse
    {
        $group->delete();

        return back()->with('success', 'Group deleted.');
    }

    public function availableDoctors(Request $request): JsonResponse
    {
        // The original lists doctors in no group *at all*. Now that
        // membership is per-session, "available" means not already in a
        // group **for this session** — otherwise a doctor who attended last
        // year could never be enrolled again this year.
        $sessionId = AcademicSessionHelper::resolveId();

        $doctors = Doctor::query()
            ->whereDoesntHave('groups', fn ($q) => $q->where(function ($q2) use ($sessionId) {
                $q2->where('doctor_group_members.academic_session_id', $sessionId)
                    ->orWhereNull('doctor_group_members.academic_session_id');
            }))
            ->when($request->integer('stage_id'), fn ($q, $stageId) => $q->where('stage_id', $stageId))
            // A doctor enrolled in another session is still selectable, but
            // one belonging to a different session entirely is not offered.
            ->when($sessionId, fn ($q) => $q->where(fn ($q2) => $q2
                ->where('academic_session_id', $sessionId)
                ->orWhereNull('academic_session_id')))
            ->orderBy('name')
            ->get(['id', 'name', 'stage_id']);

        return response()->json($doctors);
    }

    public function addDoctors(Request $request, Group $group): RedirectResponse
    {
        $validated = $request->validate([
            'doctor_ids' => ['required', 'array'],
            'doctor_ids.*' => ['integer', 'exists:doctors,id'],
        ]);

        // The original's rule is "one group at a time", enforced by deleting
        // *every* prior membership — which erases the doctor's group from
        // previous years. Scoped to the session here instead: a doctor holds
        // one group per academic session, so last year's record survives
        // (see the 2026_08_19_120000 migration).
        $sessionId = $group->academic_session_id ?? AcademicSessionHelper::resolveId();

        DB::transaction(function () use ($validated, $group, $sessionId) {
            DB::table('doctor_group_members')
                ->whereIn('doctor_id', $validated['doctor_ids'])
                ->where(function ($q) use ($sessionId) {
                    $q->where('academic_session_id', $sessionId);
                    // Rows predating the session column belong to no year in
                    // particular; treat them as the current one so a doctor
                    // isn't left in two groups for the same session.
                    if ($sessionId !== null) {
                        $q->orWhereNull('academic_session_id');
                    }
                })
                ->delete();

            $rows = array_map(fn ($id) => [
                'group_id' => $group->id,
                'doctor_id' => $id,
                'academic_session_id' => $sessionId,
                'added_at' => now(),
            ], $validated['doctor_ids']);

            DB::table('doctor_group_members')->insert($rows);
        });

        return back()->with('success', 'Doctors added to group.');
    }

    public function removeDoctors(Request $request, Group $group): RedirectResponse
    {
        $validated = $request->validate([
            'doctor_ids' => ['required', 'array'],
            'doctor_ids.*' => ['integer', 'exists:doctors,id'],
        ]);

        DB::table('doctor_group_members')
            ->where('group_id', $group->id)
            ->whereIn('doctor_id', $validated['doctor_ids'])
            ->delete();

        return back()->with('success', 'Doctors removed from group.');
    }

    private function validateGroup(Request $request): array
    {
        return $request->validate([
            'name' => ['required', 'string', 'max:100'],
            'stage_id' => ['required', 'exists:stages,id'],
            'slots' => ['array'],
            'slots.*.day' => ['required', 'string', 'max:20'],
            'slots.*.start_time' => ['required', 'date_format:H:i'],
            'slots.*.end_time' => ['required', 'date_format:H:i', 'after:slots.*.start_time'],
        ]);
    }
}
