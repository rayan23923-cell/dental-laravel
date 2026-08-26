<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Doctor;
use App\Models\Group;
use App\Models\PatientRegistration;
use App\Models\Task;
use App\Models\TaskInstance;
use App\Services\AcademicSessionHelper;
use App\Services\DoctorTaskSummary;
use App\Services\PatientScreeningException;
use App\Services\TaskGradeException;
use App\Services\TaskInstanceGrader;
use App\Services\TaskProgressFilters;
use App\Services\TaskProgressGroupSummary;
use App\Services\TaskStartException;
use App\Services\TaskStarter;
use App\Support\PendingTaskFinder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * The Flutter twin of the web's admin "تقدم المهام" screen
 * (`TaskProgressController`). `filters()`/`group()`/`complete()`/
 * `updateInstance()` delegate to the same `App\Services\TaskProgress*`
 * classes the web controller now uses, so both surfaces share one
 * implementation of the day→education-type→stage→group→department→doctor
 * matrix and the grade-validation rule, rather than a second copy drifting
 * out of sync.
 *
 * `nfcScan()`/`start()` predate that full matrix — they're the
 * Flutter-only twin of the "resolve a scanned code, then start a task"
 * flow the web's `TaskProgressController::scan()`/`start()` already have,
 * keyed off a physical NFC tag's hardware UID rather than a JSON QR
 * payload, since only the Flutter app (via `nfc_manager`) can read NFC at
 * all. Confirmed with the user: scanning a doctor's tag should both
 * identify the doctor **and**, if there's exactly one unambiguous pending
 * task for them, offer it as a direct start shortcut — the same "pending"
 * concept `Doctor\PendingTasksQrController` already defines, reused here
 * via `App\Support\PendingTaskFinder` rather than a second copy. In the
 * fuller matrix screen, this becomes the alternate input for its doctor
 * search box (tap-to-scan instead of typing a name) rather than a
 * separate screen — see `flutter_app/README.md`.
 */
class TaskProgressController extends Controller
{
    public function nfcScan(Request $request): JsonResponse
    {
        $validated = $request->validate(['tag_id' => ['required', 'string']]);
        $tagId = strtoupper(trim($validated['tag_id']));

        $doctor = Doctor::where('nfc_tag_id', $tagId)->first();

        if (! $doctor) {
            return response()->json(['message' => 'لا يوجد طبيب مرتبط بهذه البطاقة.'], 404);
        }

        $candidates = PendingTaskFinder::forDoctor($doctor);

        if ($candidates->count() === 1) {
            $task = $candidates->first();

            return response()->json([
                'kind' => 'pending_task',
                'doctor' => ['id' => $doctor->id, 'name' => $doctor->name, 'username' => $doctor->username],
                'task' => [
                    'id' => $task->id,
                    'title' => $task->title,
                    'department' => $task->department?->name,
                    'required_count' => $task->required_count,
                ],
            ]);
        }

        return response()->json([
            'kind' => 'doctor',
            'doctor' => ['id' => $doctor->id, 'name' => $doctor->name, 'username' => $doctor->username],
        ]);
    }

    public function start(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'doctor_id' => ['required', 'exists:doctors,id'],
            'task_id' => ['required', 'exists:tasks,id'],
            // Required (2026-08-26) — identifies which patient this
            // instance is for, so `PatientScreeningGate` can be enforced.
            // See `PatientRegistration`'s docblock for why the table is
            // `patients_simple`.
            'patient_registration_id' => ['required', 'exists:patients_simple,id'],
            'notes' => ['nullable', 'string'],
        ]);

        $task = Task::findOrFail($validated['task_id']);
        $doctor = Doctor::findOrFail($validated['doctor_id']);
        $patientRegistration = PatientRegistration::findOrFail($validated['patient_registration_id']);

        try {
            $instance = TaskStarter::start(
                $task,
                $doctor,
                $patientRegistration,
                $validated['notes'] ?? null,
                $request->user()?->id
            );
        } catch (TaskStartException|PatientScreeningException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->json([
            'data' => [
                'instance_id' => $instance->id,
                'status' => $instance->status,
                // Added for the task-start printed receipt (Flutter) —
                // assigned_date is the closest thing this schema has to a
                // "started at" timestamp (see TaskInstance's own docblock).
                'notes' => $instance->notes,
                'assigned_date' => $instance->assigned_date,
                // Which staff member started this task — requested for the
                // printed receipt so it also records who initiated it, not
                // just the doctor/student the task is for.
                'started_by' => $instance->assignedBy?->full_name,
                'doctor' => ['id' => $doctor->id, 'name' => $doctor->name],
                'task' => [
                    'id' => $task->id,
                    'title' => $task->title,
                    'department' => $task->department?->name,
                ],
            ],
        ]);
    }

    /** The day/education-type/stage/group filter data — see `TaskProgressFilters`. */
    public function filters(Request $request): JsonResponse
    {
        $day = $request->string('day')->toString() ?: null;
        $educationTypeId = $request->integer('education_type') ?: null;
        $stageId = $request->integer('stage') ?: null;

        return response()->json(TaskProgressFilters::build($request->user(), $day, $educationTypeId, $stageId, AcademicSessionHelper::resolveId()));
    }

    /** The department-tabbed doctor/task matrix for one group — see `TaskProgressGroupSummary`. */
    public function group(Request $request, Group $group): JsonResponse
    {
        return response()->json(TaskProgressGroupSummary::build($group, $request->user(), AcademicSessionHelper::resolveId()));
    }

    /**
     * A doctor's own department-grouped task summary (their "مهامي" screen)
     * — see `DoctorTaskSummary`. Doctor-only, same ownership-check pattern
     * as `TaskInstanceController::mine()`.
     */
    public function mine(Request $request): JsonResponse
    {
        $doctor = $request->user();
        abort_unless($doctor instanceof Doctor, 403, 'Only doctors have their own task summary.');

        return response()->json(DoctorTaskSummary::build($doctor, AcademicSessionHelper::resolveId()));
    }

    public function complete(Request $request, TaskInstance $taskInstance): JsonResponse
    {
        $validated = $request->validate([
            'grade' => ['nullable', 'numeric', 'min:0'],
            'notes' => ['nullable', 'string'],
        ]);

        try {
            TaskInstanceGrader::complete($taskInstance, $validated['grade'] ?? null, $validated['notes'] ?? null);
        } catch (TaskGradeException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->json(['data' => [
            'instance_id' => $taskInstance->id,
            'status' => $taskInstance->status,
            'grade' => $taskInstance->grade,
            'notes' => $taskInstance->notes,
        ]]);
    }

    public function updateInstance(Request $request, TaskInstance $taskInstance): JsonResponse
    {
        $validated = $request->validate([
            'grade' => ['nullable', 'numeric', 'min:0'],
            'notes' => ['nullable', 'string'],
        ]);

        try {
            TaskInstanceGrader::updateNotesGrade($taskInstance, $validated['grade'] ?? null, $validated['notes'] ?? null);
        } catch (TaskGradeException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->json(['data' => [
            'instance_id' => $taskInstance->id,
            'status' => $taskInstance->status,
            'grade' => $taskInstance->grade,
            'notes' => $taskInstance->notes,
        ]]);
    }
}
