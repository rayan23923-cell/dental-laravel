<?php

namespace App\Http\Controllers;

use App\Support\LinkedRecords;
use App\Models\AcademicSession;
use App\Models\CaseSheetType;
use App\Models\Department;
use App\Models\Doctor;
use App\Models\EducationType;
use App\Models\Stage;
use App\Models\Task;
use App\Services\AcademicSessionHelper;
use App\Services\ScopeHelper;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Inertia\Inertia;
use Inertia\Response;

class TaskController extends Controller
{
    /**
     * Matches the original's admin/manage_tasks.php: the task list is
     * hidden entirely until a stage AND a department are both chosen —
     * not a narrowing filter over an already-visible list. Education
     * type has no column on `tasks` at all (same as the original, which
     * only uses it to filter the stage dropdown via
     * tasks_ajax/get_stages_by_edu.php) — it's client-side-only here too,
     * so it's never read from the request.
     */
    public function index(Request $request): Response
    {
        $stageId = $request->integer('stage_id');
        $departmentId = $request->integer('department_id');

        $session = AcademicSessionHelper::resolve();

        $tasks = null;
        if ($stageId && $departmentId) {
            $query = Task::with(['department', 'caseSheetType', 'stage', 'academicSession:id,name'])
                ->withCount('instances')
                ->where('stage_id', $stageId)
                ->where('department_id', $departmentId);
            // Only within the account's access scope, like the app's list.
            ScopeHelper::scopeStages($query, $request->user(), 'stage_id');
            ScopeHelper::scopeDepartments($query, $request->user(), 'department_id');

            // Same rule as the original's tasks_ajax/get_tasks.php:
            // `academic_session_id = active OR IS NULL`. Tasks belong to
            // the year they were created in, so a new academic year
            // starts with its own task list while session-less (legacy)
            // tasks stay visible in all.
            if ($session && ! $request->boolean('all_sessions')) {
                $query->where(fn ($q) => $q
                    ->where('academic_session_id', $session->id)
                    ->orWhereNull('academic_session_id'));
            }

            $tasks = $query->orderByDesc('id')->paginate(15)->withQueryString();
        }

        return Inertia::render('Tasks/Index', [
            'tasks' => $tasks,
            'educationTypes' => ScopeHelper::scopeEducationTypes(EducationType::query(), $request->user())
                ->orderBy('name')->get(['id', 'name']),
            'stages' => ScopeHelper::scopeStages(Stage::query(), $request->user())
                ->orderBy('name')->get(['id', 'name', 'education_type_id']),
            'departments' => ScopeHelper::scopeEducationTypes(
                ScopeHelper::scopeStages(
                    ScopeHelper::scopeDepartments(Department::query(), $request->user()),
                    $request->user(),
                    'stage_id'
                ),
                $request->user(),
                'education_type_id'
            )->orderBy('name')->get(['id', 'name', 'stage_id', 'education_type_id']),
            'filters' => $request->only('stage_id', 'department_id'),
            'currentSession' => $session?->only('id', 'name'),
            'allSessions' => $request->boolean('all_sessions'),
        ]);
    }

    public function create(Request $request): Response
    {
        // Carries a stage/education-type filter over from Tasks/Index.vue's
        // "Add Task" link when one is active there — null (both, or just
        // education_type_id since it has no bearing server-side) when the
        // list wasn't filtered, which the form already treats as "start
        // empty, pick manually", the same as before this existed.
        return Inertia::render('Tasks/Create', [
            'initialStageId' => $request->integer('stage_id') ?: null,
            'initialEducationTypeId' => $request->integer('education_type_id') ?: null,
            ...$this->formOptions(),
        ]);
    }

    public function store(Request $request): RedirectResponse
    {
        $validated = $this->validateTask($request);

        // Matches add_task.php, which stamps SessionHelper::getActiveSessionId()
        // onto every new task.
        $validated['academic_session_id'] ??= AcademicSessionHelper::resolveId();

        Task::create($validated);

        return redirect()->route('tasks.index')->with('success', 'Task created.');
    }

    public function show(Task $task): Response
    {
        $task->load(['department', 'caseSheetType', 'stage', 'instances.doctor']);

        // Only doctors from the task's own academic year can be assigned to
        // it — offering last year's intake would let a 2024 doctor be given a
        // 2025 task. Session-less doctors stay selectable everywhere.
        $doctors = Doctor::query()
            ->when($task->academic_session_id, fn ($q, $sessionId) => $q->where(fn ($q2) => $q2
                ->where('academic_session_id', $sessionId)
                ->orWhereNull('academic_session_id')))
            ->orderBy('name')
            ->get(['id', 'name']);

        return Inertia::render('Tasks/Show', [
            'task' => $task,
            'doctors' => $doctors,
        ]);
    }

    public function edit(Task $task): Response
    {
        return Inertia::render('Tasks/Edit', [
            'task' => $task,
            ...$this->formOptions(),
        ]);
    }

    public function update(Request $request, Task $task): RedirectResponse
    {
        $task->update($this->validateTask($request));

        return redirect()->route('tasks.index')->with('success', 'Task updated.');
    }

    public function destroy(Task $task): RedirectResponse
    {
        if ($linked = LinkedRecords::message($task)) {
            return back()->with('error', $linked);
        }

        $task->delete();

        return redirect()->route('tasks.index')->with('success', 'تمت أرشفة المهمة.');
    }

    private function formOptions(): array
    {
        return [
            'departments' => Department::orderBy('name')->get(),
            'caseSheetTypes' => CaseSheetType::where('is_active', true)->orderBy('display_order')->get(),
            'stages' => Stage::orderBy('name')->get(),
            // For the create/edit form's education-type -> stage cascade
            // (UI-only, same as Index.vue's — `tasks` has no
            // education_type_id column, see this controller's index() docblock).
            'educationTypes' => EducationType::orderBy('name')->get(['id', 'name']),
            // Editable so a task can be moved between academic years and
            // legacy session-less tasks can be assigned one.
            'academicSessions' => AcademicSession::orderByDesc('start_date')->get(['id', 'name']),
        ];
    }

    private function validateTask(Request $request): array
    {
        return $request->validate([
            // Must be one of the chosen stage's own departments (2026-10-13, by request).
            'department_id' => ['required', Rule::exists('departments', 'id')->where('stage_id', $request->integer('stage_id'))],
            'case_sheet_type_id' => ['required', 'exists:case_sheet_types,id'],
            'stage_id' => ['required', 'exists:stages,id'],
            'title' => ['required', 'string', 'max:255'],
            // Ignored if an older app still sends it: required_count is the
            // only cap now (2026-10-13, by request).
            'required_per_doctor' => ['exclude'],
            'required_count' => ['required', 'integer', 'min:1'],
            // Every field is required (2026-10-13, by request).
            'notes' => ['required', 'string'],
            // "الدرجة / العلامة" — present in the original's add/edit task
            // forms (0.00–100.00) but missing from the first port.
            'grade' => ['required', 'numeric', 'min:0', 'max:100'],
            'academic_session_id' => ['nullable', 'exists:academic_sessions,id'],
            'is_required' => ['sometimes', 'boolean'],
        ]);
    }
}
