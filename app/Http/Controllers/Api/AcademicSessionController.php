<?php

namespace App\Http\Controllers\Api;

use App\Support\LinkedRecords;
use App\Http\Controllers\Controller;
use App\Models\AcademicSession;
use App\Models\Doctor;
use App\Models\Group;
use App\Models\Task;
use App\Services\AcademicSessionHelper;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Mirrors App\Http\Controllers\AcademicSessionController for the Flutter
 * client. No "selected session" concept here (Sanctum is stateless) — see
 * App\Services\AcademicSessionHelper docblock. show() always reflects the
 * requested session's own id, not any ambient "current" one.
 */
class AcademicSessionController extends Controller
{
    public function index(): JsonResponse
    {
        $sessions = AcademicSession::withCount(['groups', 'tasks'])
            ->orderByDesc('is_current')
            ->orderByDesc('start_date')
            ->get();

        return response()->json($sessions);
    }

    /**
     * The active academic year, `{id, name}` — or `null` if none is set.
     * One small endpoint reused everywhere Flutter needs to show "current
     * academic year" (dashboard, Doctors/Groups/Tasks/Task-Progress
     * headers) instead of each screen re-resolving it independently.
     * Mirrors the `currentSession` Inertia prop the web controllers
     * already return per-page — Flutter has no equivalent mechanism, so
     * this is its own endpoint.
     */
    public function current(): JsonResponse
    {
        $session = AcademicSessionHelper::resolve();

        return response()->json($session?->only('id', 'name'));
    }

    public function show(AcademicSession $academicSession): JsonResponse
    {
        $tasks = Task::where('academic_session_id', $academicSession->id)
            ->withCount(['instances as completed_count' => fn ($q) => $q->where('status', 'completed')])
            ->get();

        // Mirrors the web controller: a doctor counts toward a session when
        // enrolled in it directly *or* through a group in it (a new intake is
        // registered before groups exist). The column must be qualified —
        // `doctor_group_members` carries one too, so a bare
        // `academic_session_id` here is ambiguous SQL.
        $doctorsCount = Doctor::where('academic_session_id', $academicSession->id)
            ->orWhereHas('groups', fn ($q) => $q->where('groups.academic_session_id', $academicSession->id))
            ->count();
        $groupsCount = Group::where('academic_session_id', $academicSession->id)->count();

        return response()->json([
            'session' => $academicSession,
            'stats' => [
                'doctors' => $doctorsCount,
                'groups' => $groupsCount,
                'required_tasks' => (int) $tasks->sum('required_count'),
                'done_tasks' => (int) $tasks->sum('completed_count'),
                'remaining_tasks' => (int) $tasks->sum(fn ($t) => max(0, $t->required_count - $t->completed_count)),
            ],
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $validated = $this->validateSession($request);

        // "Only one active academic year" is now enforced by
        // AcademicSession::booted()'s saving() hook — see that model.
        $session = AcademicSession::create($validated);

        return response()->json($session, 201);
    }

    public function update(Request $request, AcademicSession $academicSession): JsonResponse
    {
        $validated = $this->validateSession($request);

        $academicSession->update($validated);

        return response()->json($academicSession);
    }

    public function setCurrent(AcademicSession $academicSession): JsonResponse
    {
        $academicSession->update(['is_current' => true, 'is_active' => true]);

        return response()->json($academicSession->fresh());
    }

    public function destroy(AcademicSession $academicSession): JsonResponse
    {
        if ($academicSession->is_current) {
            return response()->json(['message' => 'لا يمكن حذف العام الدراسي النشط.'], 422);
        }

        if ($linked = LinkedRecords::message($academicSession)) {
            return response()->json(['message' => $linked, 'linked' => LinkedRecords::for($academicSession)], 422);
        }

        $academicSession->delete();

        return response()->json(null, 204);
    }

    private function validateSession(Request $request): array
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:150'],
            'start_date' => ['required', 'date'],
            'end_date' => ['required', 'date', 'after_or_equal:start_date'],
            'is_active' => ['boolean'],
            'is_current' => ['boolean'],
        ]);

        $validated['is_active'] = $validated['is_active'] ?? true;
        $validated['is_current'] = $validated['is_current'] ?? false;

        return $validated;
    }
}
