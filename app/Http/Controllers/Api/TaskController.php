<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\TaskResource;
use App\Models\Department;
use App\Models\Task;
use App\Services\AcademicSessionHelper;
use App\Services\ScopeHelper;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class TaskController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $query = Task::with(['department', 'caseSheetType', 'stage.educationType'])
            ->when($request->integer('department_id'), fn ($q, $id) => $q->where('department_id', $id))
            ->when($request->integer('stage_id'), fn ($q, $id) => $q->where('stage_id', $id));

        // The original's tasks_ajax/get_tasks.php scope-checks via
        // canAccessStage() before ever running the query — this endpoint
        // had no equivalent until now, meaning a scoped user could query
        // any stage/department id directly. No-op for unrestricted users
        // (see ScopeHelper's own docblock).
        $query = ScopeHelper::scopeStages($query, $request->user(), 'stage_id');
        $query = ScopeHelper::scopeDepartments($query, $request->user(), 'department_id');

        // Same "= session OR IS NULL" rule as the web list and the original's
        // tasks_ajax/get_tasks.php. A client may pass an explicit
        // academic_session_id to browse another year, or all_sessions=1 to
        // lift the filter entirely.
        $sessionId = $request->integer('academic_session_id') ?: AcademicSessionHelper::resolveId();
        if ($sessionId && ! $request->boolean('all_sessions')) {
            $query->where(fn ($q) => $q
                ->where('academic_session_id', $sessionId)
                ->orWhereNull('academic_session_id'));
        }

        $tasks = $query->orderByDesc('id')->paginate(15);

        return TaskResource::collection($tasks)->response();
    }

    public function show(Task $task): JsonResponse
    {
        $task->load(['department', 'caseSheetType', 'stage', 'instances.doctor']);

        return (new TaskResource($task))->response();
    }

    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
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
            'grade' => ['required', 'numeric', 'min:0', 'max:100'],
            'academic_session_id' => ['nullable', 'exists:academic_sessions,id'],
            'is_required' => ['sometimes', 'boolean'],
        ]);

        // Defaults to the active session, as add_task.php does.
        $validated['academic_session_id'] ??= AcademicSessionHelper::resolveId();

        $task = Task::create($validated);

        // A real bug, found live: when `is_required` is omitted (its rule
        // is 'sometimes'), the DB column default (true) applies on INSERT,
        // but the in-memory model returned by create() never learns that —
        // it still has no `is_required` attribute set at all, so the
        // resource's `(bool) $this->is_required` cast turned the missing
        // value into `false` instead of reflecting the real, defaulted `true`
        // now sitting in the row. refresh() re-reads the row create() just
        // inserted, closing that gap for every column with a DB-level default.
        $task->refresh();

        return (new TaskResource($task))->response()->setStatusCode(201);
    }

    public function update(Request $request, Task $task): JsonResponse
    {
        $validated = $request->validate([
            // Checked against the task's (new or current) stage below.
            'department_id' => ['sometimes', Rule::exists('departments', 'id')->where('stage_id', $request->integer('stage_id') ?: $task->stage_id)],
            'case_sheet_type_id' => ['sometimes', 'exists:case_sheet_types,id'],
            'stage_id' => ['sometimes', 'exists:stages,id'],
            'title' => ['sometimes', 'string', 'max:255'],
            'required_per_doctor' => ['exclude'],
            'required_count' => ['sometimes', 'integer', 'min:1'],
            'notes' => ['sometimes', 'required', 'string'],
            'grade' => ['sometimes', 'required', 'numeric', 'min:0', 'max:100'],
            'academic_session_id' => ['nullable', 'exists:academic_sessions,id'],
            'is_required' => ['sometimes', 'boolean'],
        ]);

        // Moving the task to another stage without a new department would
        // leave it under the old stage's department.
        if (isset($validated['stage_id']) && ! isset($validated['department_id'])
            && ! Department::whereKey($task->department_id)->where('stage_id', $validated['stage_id'])->exists()) {
            throw ValidationException::withMessages(['department_id' => __('validation.exists', ['attribute' => 'department id'])]);
        }

        $task->update($validated);

        return (new TaskResource($task))->response();
    }

    public function destroy(Task $task): JsonResponse
    {
        $task->delete();

        return response()->json(null, 204);
    }
}
