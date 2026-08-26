<?php

namespace App\Http\Controllers;

use App\Models\AcademicSession;
use App\Models\Doctor;
use App\Models\Group;
use App\Models\Task;
use App\Services\AcademicSessionHelper;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Ports admin/manage_sessions.php. See README.md "Academic sessions" for
 * the is_active/is_current/"selected" three-way semantic ported from
 * includes/SessionHelper.php.
 */
class AcademicSessionController extends Controller
{
    public function index(): Response
    {
        $sessions = AcademicSession::withCount(['groups', 'tasks'])
            ->orderByDesc('is_current')
            ->orderByDesc('start_date')
            ->get();

        return Inertia::render('AcademicSessions/Index', [
            'sessions' => $sessions,
            'selectedSessionId' => AcademicSessionHelper::resolve()?->id,
        ]);
    }

    public function show(AcademicSession $academicSession): Response
    {
        $tasks = Task::where('academic_session_id', $academicSession->id)
            ->withCount(['instances as completed_count' => fn ($q) => $q->where('status', 'completed')])
            ->with('department')
            ->get();

        $groups = Group::where('academic_session_id', $academicSession->id)
            ->with('stage')
            ->withCount('doctors')
            ->orderBy('name')
            ->get();

        // Counts doctors belonging to this session directly *or* through a
        // group in it — a new intake is registered before groups are formed,
        // so counting group membership alone would report zero.
        $doctorsCount = Doctor::where('academic_session_id', $academicSession->id)
            ->orWhereHas('groups', fn ($q) => $q->where('groups.academic_session_id', $academicSession->id))
            ->count();

        return Inertia::render('AcademicSessions/Show', [
            'session' => $academicSession,
            'stats' => [
                'doctors' => $doctorsCount,
                'groups' => $groups->count(),
                'requiredTasks' => (int) $tasks->sum('required_count'),
                'doneTasks' => (int) $tasks->sum('completed_count'),
                'remainingTasks' => (int) $tasks->sum(fn ($t) => max(0, $t->required_count - $t->completed_count)),
            ],
            'tasks' => $tasks->map(fn ($t) => [
                'id' => $t->id,
                'title' => $t->title,
                'department' => $t->department?->name,
                'required' => $t->required_count,
                'done' => $t->completed_count,
                'remaining' => max(0, $t->required_count - $t->completed_count),
            ])->values(),
            'groups' => $groups,
        ]);
    }

    public function store(Request $request): RedirectResponse
    {
        $validated = $this->validateSession($request);

        // "Only one active academic year" is now enforced by
        // AcademicSession::booted()'s saving() hook — it wipes is_current
        // on every other row whenever a row is saved with is_current=true,
        // so this no longer needs to do it manually first.
        $session = AcademicSession::create($validated);

        if (! empty($validated['is_current'])) {
            AcademicSessionHelper::setSelected($session);
        }

        return back()->with('success', 'العام الدراسي أضيف بنجاح.');
    }

    public function update(Request $request, AcademicSession $academicSession): RedirectResponse
    {
        $validated = $this->validateSession($request);

        $academicSession->update($validated);

        return back()->with('success', 'تم تحديث العام الدراسي.');
    }

    public function setCurrent(AcademicSession $academicSession): RedirectResponse
    {
        $academicSession->update(['is_current' => true, 'is_active' => true]);

        AcademicSessionHelper::setSelected($academicSession);

        return back()->with('success', "\"{$academicSession->name}\" أصبح العام الدراسي النشط.");
    }

    // Matches SessionHelper::renderSwitcherWidget()'s navbar dropdown — sets
    // which session this browser session is *viewing*, independent of
    // is_current (a super_admin can browse a past session's data without
    // changing the system-wide default).
    public function select(Request $request): RedirectResponse
    {
        $validated = $request->validate(['academic_session_id' => ['required', 'exists:academic_sessions,id']]);
        $session = AcademicSession::findOrFail($validated['academic_session_id']);

        AcademicSessionHelper::setSelected($session);

        return back();
    }

    public function destroy(AcademicSession $academicSession): RedirectResponse
    {
        if ($academicSession->is_current) {
            return back()->with('error', 'لا يمكن حذف العام الدراسي النشط. عيّن عاماً آخر كنشط أولاً.');
        }

        $groupsCount = $academicSession->groups()->count();
        $tasksCount = $academicSession->tasks()->count();

        if ($groupsCount > 0 || $tasksCount > 0) {
            return back()->with('error', "مرتبط بـ {$groupsCount} مجموعة و {$tasksCount} مهمة — قم بإلغاء تفعيله بدلاً من حذفه.");
        }

        $academicSession->delete();

        return back()->with('success', 'تم حذف العام الدراسي.');
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
