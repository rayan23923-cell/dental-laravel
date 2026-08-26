<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AcademicSession;
use App\Models\Doctor;
use App\Models\Group;
use App\Services\AcademicSessionHelper;
use App\Services\ScopeHelper;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Mirrors App\Http\Controllers\GroupController for the Flutter client.
 * store() takes an explicit academic_session_id (nullable — falls back to
 * the is_current session) since the API has no persisted "selected"
 * session to default to.
 */
class GroupController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $user = $request->user();

        $query = Group::with(['stage.educationType'])
            ->withCount('doctors')
            ->when($request->integer('stage_id'), fn ($q, $stageId) => $q->where('stage_id', $stageId))
            // New — no group-name search existed anywhere in this project
            // (web or API) before this.
            ->when($request->string('search')->toString(), fn ($q, $search) => $q->where('name', 'like', "%{$search}%"))
            // New — "which group is this doctor in", the NFC-scan use case
            // on the Flutter groups list (a doctor isn't a group-name
            // match, so it's a separate filter, combinable with the two
            // above).
            ->when($request->integer('doctor_id'), fn ($q, $id) => $q->whereHas('doctors', fn ($q2) => $q2->where('doctors.id', $id)));

        // Defaults to the current academic year when the client doesn't
        // pass one explicitly — Api\DoctorController/Api\TaskController
        // already do this; this one didn't, so the Flutter Groups list
        // was silently showing every year's groups at once (found while
        // scoping "each academic year has independent groups").
        $sessionId = $request->integer('academic_session_id') ?: AcademicSessionHelper::resolveId();
        if ($sessionId && ! $request->boolean('all_sessions')) {
            $query->where(fn ($q) => $q->where('academic_session_id', $sessionId)->orWhereNull('academic_session_id'));
        }

        $query = ScopeHelper::scopeStages($query, $user, 'stage_id');
        $query = ScopeHelper::scopeAcademicSessions($query, $user);

        $groups = $query->orderBy('name')->get()->map(fn ($group) => [
            'id' => $group->id,
            'name' => $group->name,
            'stage' => $group->stage,
            'academic_session_id' => $group->academic_session_id,
            'doctors_count' => $group->doctors_count,
            'slots' => $group->slots,
        ]);

        return response()->json($groups);
    }

    public function show(Group $group): JsonResponse
    {
        // username — used by the roster PDF's member table (matches the
        // legacy task-progress print's own use of it for the doctor QR
        // payload, though this call site has no QR code).
        $group->load(['stage', 'slots', 'doctors:id,name,email,username']);

        return response()->json($group);
    }

    public function store(Request $request): JsonResponse
    {
        $validated = $this->validateGroup($request);

        $sessionId = $validated['academic_session_id']
            ?? AcademicSession::where('is_current', true)->value('id');

        $group = DB::transaction(function () use ($validated, $sessionId) {
            $group = Group::create([
                'name' => $validated['name'],
                'stage_id' => $validated['stage_id'],
                'academic_session_id' => $sessionId,
            ]);

            $group->slots()->createMany($validated['slots'] ?? []);

            return $group;
        });

        return response()->json($group->load('slots'), 201);
    }

    public function update(Request $request, Group $group): JsonResponse
    {
        $validated = $this->validateGroup($request);

        DB::transaction(function () use ($validated, $group) {
            $group->update([
                'name' => $validated['name'],
                'stage_id' => $validated['stage_id'],
            ]);

            if (array_key_exists('slots', $validated)) {
                $group->slots()->delete();
                $group->slots()->createMany($validated['slots']);
            }
        });

        return response()->json($group->load('slots'));
    }

    public function destroy(Group $group): JsonResponse
    {
        $group->delete();

        return response()->json(null, 204);
    }

    public function availableDoctors(Request $request): JsonResponse
    {
        // Mirrors the web GroupController: "available" means not already in a
        // group **for this session**, so a doctor who attended a previous year
        // can be enrolled again in the new one.
        $sessionId = $request->integer('academic_session_id') ?: AcademicSessionHelper::resolveId();

        $doctors = Doctor::query()
            ->whereDoesntHave('groups', fn ($q) => $q->where(function ($q2) use ($sessionId) {
                $q2->where('doctor_group_members.academic_session_id', $sessionId)
                    ->orWhereNull('doctor_group_members.academic_session_id');
            }))
            ->when($request->integer('stage_id'), fn ($q, $stageId) => $q->where('stage_id', $stageId))
            ->when($sessionId, fn ($q) => $q->where(fn ($q2) => $q2
                ->where('academic_session_id', $sessionId)
                ->orWhereNull('academic_session_id')))
            ->orderBy('name')
            ->get(['id', 'name', 'stage_id']);

        return response()->json($doctors);
    }

    public function addDoctors(Request $request, Group $group): JsonResponse
    {
        $validated = $request->validate([
            'doctor_ids' => ['required', 'array'],
            'doctor_ids.*' => ['integer', 'exists:doctors,id'],
        ]);

        // Scoped to the group's session, exactly as in the web controller —
        // an unscoped delete here would wipe the doctor's group from every
        // previous academic year.
        $sessionId = $group->academic_session_id ?? AcademicSessionHelper::resolveId();

        DB::transaction(function () use ($validated, $group, $sessionId) {
            DB::table('doctor_group_members')
                ->whereIn('doctor_id', $validated['doctor_ids'])
                ->where(function ($q) use ($sessionId) {
                    $q->where('academic_session_id', $sessionId);
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

        return response()->json($group->load('doctors'));
    }

    public function removeDoctors(Request $request, Group $group): JsonResponse
    {
        $validated = $request->validate([
            'doctor_ids' => ['required', 'array'],
            'doctor_ids.*' => ['integer', 'exists:doctors,id'],
        ]);

        DB::table('doctor_group_members')
            ->where('group_id', $group->id)
            ->whereIn('doctor_id', $validated['doctor_ids'])
            ->delete();

        return response()->json($group->load('doctors'));
    }

    private function validateGroup(Request $request): array
    {
        return $request->validate([
            'name' => ['required', 'string', 'max:100'],
            'stage_id' => ['required', 'exists:stages,id'],
            'academic_session_id' => ['nullable', 'exists:academic_sessions,id'],
            'slots' => ['array'],
            'slots.*.day' => ['required', 'string', 'max:20'],
            'slots.*.start_time' => ['required', 'date_format:H:i'],
            'slots.*.end_time' => ['required', 'date_format:H:i', 'after:slots.*.start_time'],
        ]);
    }
}
