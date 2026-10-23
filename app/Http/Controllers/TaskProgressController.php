<?php

namespace App\Http\Controllers;

use App\Support\TaskSteps;
use App\Support\CaseSheetSignatures;
use App\Support\TaskScoring;
use App\Models\ClinicSetting;
use App\Models\Doctor;
use App\Models\Group;
use App\Models\Stage;
use App\Models\PatientRegistration;
use App\Models\Task;
use App\Models\TaskInstance;
use App\Services\AcademicSessionHelper;
use App\Services\PatientScreeningException;
use App\Services\TaskGradeException;
use App\Services\TaskInstanceGrader;
use App\Services\TaskProgressFilters;
use App\Services\ScopeHelper;
use App\Services\TaskProgressGroupSummary;
use App\Services\TaskStartException;
use App\Services\TaskStarter;
use App\Services\TaskStartRequests;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\View\View;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Ports admin/task_progress_view.php + admin/ajax/get_group_doctors.php —
 * the **admin-side** task progress screen, which is a different thing from
 * the per-doctor screen (DoctorTaskProgressController / admin/doctor_task_progress.php):
 * this one is browsed by day → education type → stage → group, then shows
 * every doctor in that group as a department-tabbed matrix with per-slot
 * task cards and start/complete/edit actions.
 *
 * The original's QR-scanner modal on this page is not ported — camera
 * scanning is deferred to the Flutter client (see README "Not yet built").
 */
class TaskProgressController extends Controller
{
    public function index(Request $request): Response
    {
        $selectedDay = $request->string('day')->toString();
        $selectedEducationType = $request->integer('education_type') ?: null;
        $selectedStage = $request->integer('stage') ?: null;

        $session = AcademicSessionHelper::resolve();
        $data = TaskProgressFilters::build($request->user(), $selectedDay, $selectedEducationType, $selectedStage, $session?->id);

        return Inertia::render('TaskProgress/Index', [
            'days' => $data['days'],
            'educationTypes' => $data['education_types'],
            'stages' => $data['stages'],
            'groups' => $data['groups'],
            'filters' => $data['filters'],
            // Matches Doctors/Groups/Tasks — this screen previously had no
            // active-year banner at all.
            'currentSession' => $session?->only('id', 'name'),
            // Badge on the "الطلبات" tab (2026-10-14).
            'pendingRequests' => TaskStartRequests::visibleTo($request->user())->where('status', 'pending')->count(),
            // "إلغاء بدء المهمة" (2026-10-23): its own permission.
            'canCancel' => (new \App\Services\PermissionManager($request->user()))->can('task_progress', 'cancel'),
        ]);
    }

    /**
     * The department-tabbed doctor/task matrix for one group — the port of
     * get_group_doctors.php. Returned as JSON and fetched client-side (the
     * original loads it by AJAX too, and it's re-fetched after every
     * start/complete/edit action).
     */
    public function group(Request $request, Group $group): JsonResponse
    {
        return response()->json(self::gradesFor($request, TaskProgressGroupSummary::build($group, $request->user(), AcademicSessionHelper::resolveId())));
    }

    /**
     * Every doctor of one stage — what task progress shows while groups are
     * turned off in clinic settings. Limited to the stages the user may see.
     */
    public function stage(Request $request, int $stage): JsonResponse
    {
        $stage = ScopeHelper::scopeStages(Stage::whereKey($stage), $request->user())->firstOrFail();

        return response()->json(self::gradesFor($request, TaskProgressGroupSummary::buildForStage($stage, $request->user(), AcademicSessionHelper::resolveId())));
    }

    /**
     * Printable task progress (2026-10-13, by request) — the web side of the
     * app's PDF (task_progress_pdf.dart) and the original's
     * task_progress_print.php: a whole group (or a whole stage while groups
     * are off), optionally narrowed to one department or one doctor.
     */
    public function print(Request $request): View
    {
        $user = $request->user();
        $sessionId = AcademicSessionHelper::resolveId();

        if ($groupId = $request->integer('group')) {
            $data = TaskProgressGroupSummary::build(Group::findOrFail($groupId), $user, $sessionId);
        } else {
            $stage = ScopeHelper::scopeStages(Stage::whereKey($request->integer('stage')), $user)->firstOrFail();
            $data = TaskProgressGroupSummary::buildForStage($stage, $user, $sessionId);
        }

        $departmentId = $request->integer('department') ?: null;
        $doctorId = $request->integer('doctor') ?: null;

        $departments = collect($data['departments'])
            ->when($departmentId, fn ($c) => $c->where('id', $departmentId))
            ->map(function ($department) use ($doctorId) {
                $department['doctors'] = collect($department['doctors'])
                    ->when($doctorId, fn ($c) => $c->where('id', $doctorId))
                    ->values()
                    ->all();

                return $department;
            })
            ->filter(fn ($department) => count($department['doctors']) > 0)
            ->values();

        return view('print.task-progress', [
            'settings' => ClinicSetting::current(),
            'group' => $data['group'],
            'departments' => $departments,
            'scopeLine' => implode(' — ', array_filter([
                $departmentId && $departments->isNotEmpty() ? 'القسم: '.$departments->first()['name'] : null,
                $doctorId && $departments->isNotEmpty() ? 'الطبيب: '.$departments->first()['doctors'][0]['name'] : null,
            ])),
            'autoprint' => $request->boolean('autoprint'),
        ]);
    }

    /**
     * Resolves a scanned QR payload for the admin task-progress screen —
     * the web counterpart of Api\TaskInstanceQrController::scan().
     *
     * Handles both payload shapes this app issues: a `task_instance` code
     * (from an existing assigned case) and a `pending_task` code (from the
     * doctor's "رموز المهام المعلقة" page, which identifies a doctor+task
     * pair that has no instance yet). Returns what was found so the page
     * can jump straight to that doctor's row or offer to start the task.
     */
    public function scan(Request $request): JsonResponse
    {
        $validated = $request->validate(['payload' => ['required', 'string']]);

        $decoded = json_decode($validated['payload'], true);

        if (! is_array($decoded)) {
            return response()->json(['message' => 'رمز غير صالح.'], 422);
        }

        if (($decoded['type'] ?? null) === 'task_instance' && ! empty($decoded['id'])) {
            $instance = TaskInstance::with(['task.department', 'task.caseSheetType', 'doctor'])->find($decoded['id']);

            if (! $instance) {
                return response()->json(['message' => 'حالة المهمة غير موجودة.'], 404);
            }

            return response()->json([
                'kind' => 'task_instance',
                'instance_id' => $instance->id,
                'status' => $instance->status,
                'doctor' => ['id' => $instance->doctor?->id, 'name' => $instance->doctor?->name],
                'task' => [
                    'id' => $instance->task?->id,
                    'title' => $instance->task?->title,
                    'department' => $instance->task?->department?->name,
                    'case_sheet' => $instance->task?->caseSheetType?->name_ar,
                ],
                'case_sheet_url' => route('case-sheet.open', $instance->id),
            ]);
        }

        if (($decoded['type'] ?? null) === 'pending_task' && ! empty($decoded['task_id']) && ! empty($decoded['doctor_id'])) {
            $task = Task::with('department')->find($decoded['task_id']);
            $doctor = Doctor::find($decoded['doctor_id']);

            if (! $task || ! $doctor) {
                return response()->json(['message' => 'المهمة أو الطبيب غير موجود.'], 404);
            }

            return response()->json([
                'kind' => 'pending_task',
                'doctor' => ['id' => $doctor->id, 'name' => $doctor->name],
                'task' => [
                    'id' => $task->id,
                    'title' => $task->title,
                    'department' => $task->department?->name,
                    'required_count' => $task->required_count,
                    // Its steps, signed in the start dialog (2026-10-18).
                    'scoring' => $task->scoring,
                ],
            ]);
        }

        // The doctor's own QR, printed on their ID card (2026-10-14).
        if (($decoded['type'] ?? null) === 'doctor' && ! empty($decoded['id'])) {
            $doctor = Doctor::with(['stage:id,name'])->find($decoded['id']);

            if (! $doctor) {
                return response()->json(['message' => 'الطبيب غير موجود.'], 404);
            }

            return response()->json([
                'kind' => 'doctor',
                'doctor' => ['id' => $doctor->id, 'name' => $doctor->name, 'stage' => $doctor->stage?->name],
                'progress_url' => route('doctors.progress', $doctor->id),
            ]);
        }

        return response()->json(['message' => 'رمز غير معروف — ليس رمز مهمة صالحاً.'], 422);
    }

    /**
     * Ports admin/ajax/assign_task_ajax.php, including its real guards:
     * required_count is the per-doctor cap; refuses
     * once the doctor has already completed their required number; and
     * lazily creates a single `pending` instance when the global pool is
     * empty rather than pre-creating them all.
     */
    public function start(Request $request): RedirectResponse
    {
        $validated = $request->validate([
            'doctor_id' => ['required', 'exists:doctors,id'],
            'task_id' => ['required', 'exists:tasks,id'],
            // Optional (2026-10-12): a task starts from the case QR or the
            // doctor search alone; when a patient is given the screening
            // gate still applies (see TaskStarter).
            'patient_registration_id' => ['nullable', 'exists:patients_simple,id'],
            'notes' => ['nullable', 'string'],
            // Steps done at this first session, signed as it starts (2026-10-18).
            'steps' => ['nullable', 'array', 'max:40'],
            'steps.*.step' => ['required', 'string', 'max:40'],
            'steps.*.grade' => ['nullable', 'numeric', 'min:0'],
        ]);

        $task = Task::findOrFail($validated['task_id']);
        $doctor = Doctor::findOrFail($validated['doctor_id']);
        $patientRegistration = isset($validated['patient_registration_id'])
            ? PatientRegistration::findOrFail($validated['patient_registration_id'])
            : null;

        try {
            $instance = TaskStarter::start($task, $doctor, $patientRegistration, $validated['notes'] ?? null, auth()->id());
        } catch (TaskStartException|PatientScreeningException $e) {
            return back()->with('error', $e->getMessage());
        }
        self::signSteps($instance, $validated['steps'] ?? [], $request);

        return back()->with('success', 'Task started for this doctor.');
    }

    /**
     * Ports admin/ajax/mark_task_completed.php, including its exact grade
     * rules: a grade may only be set when the task itself defines one, and
     * may never exceed it.
     */
    public function complete(Request $request, TaskInstance $taskInstance): RedirectResponse
    {
        $validated = $request->validate([
            'grade' => ['nullable', 'numeric', 'min:0'],
            'notes' => ['nullable', 'string'],
            ...TaskScoring::workItemRules(),
        ]);

        try {
            TaskInstanceGrader::complete($taskInstance, $validated['grade'] ?? null, $validated['notes'] ?? null, $validated['work_items'] ?? null);
        } catch (TaskGradeException $e) {
            return back()->with('error', $e->getMessage());
        }

        return back()->with('success', 'Task marked as completed.');
    }

    /** "إلغاء بدء المهمة" (2026-10-23); see App\Services\TaskCanceller. */
    public function cancel(TaskInstance $taskInstance): RedirectResponse
    {
        try {
            \App\Services\TaskCanceller::cancel($taskInstance);
        } catch (TaskStartException $e) {
            return back()->with('error', $e->getMessage());
        }

        return back()->with('success', 'تم إلغاء بدء المهمة.');
    }

    /** Ports admin/ajax/update_task_instance.php (edit notes + grade). */
    public function updateInstance(Request $request, TaskInstance $taskInstance): RedirectResponse
    {
        $validated = $request->validate([
            'grade' => ['nullable', 'numeric', 'min:0'],
            'notes' => ['nullable', 'string'],
            ...TaskScoring::workItemRules(),
        ]);

        try {
            TaskInstanceGrader::updateNotesGrade($taskInstance, $validated['grade'] ?? null, $validated['notes'] ?? null, $validated['work_items'] ?? null);
        } catch (TaskGradeException $e) {
            return back()->with('error', $e->getMessage());
        }

        return back()->with('success', 'Task instance updated.');
    }

    /** Signs the steps ticked in the start dialog, in order (2026-10-18). */
    private static function signSteps(TaskInstance $instance, array $steps, Request $request): void
    {
        // Steps switched off for the whole system (2026-10-22): none signed.
        if (! \App\Support\FormSettings::on('steps_enabled')) {
            return;
        }
        $signer = CaseSheetSignatures::signerName($request);
        foreach ($steps as $step) {
            TaskSteps::sign($instance->fresh(), $step['step'], $step['grade'] ?? null, $signer);
        }
    }

    /** Grades hidden from staff without `task_progress.view_grade` (2026-10-22). */
    private static function gradesFor(Request $request, array $summary): array
    {
        return (new \App\Services\PermissionManager($request->user()))->can('task_progress', 'view_grade')
            ? $summary
            : \App\Support\FormSettings::withoutGrades($summary);
    }
}
