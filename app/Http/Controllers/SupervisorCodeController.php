<?php

namespace App\Http\Controllers;

use App\Models\Doctor;
use App\Models\Task;
use App\Models\TaskInstance;
use App\Models\User;
use App\Services\PatientScreeningException;
use App\Services\SupervisorCode;
use App\Services\TaskGradeException;
use App\Services\TaskInstanceGrader;
use App\Services\TaskStartException;
use App\Services\TaskStartRequests;
use App\Support\FormSettings;
use App\Support\TaskSteps;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Validation\ValidationException;

/**
 * The student's side of the supervisor code (2026-10-22, by request): on
 * the student's own account, the supervisor types their code to start a
 * task, sign the case's next step with its grade, add a step, or complete it. Each
 * action runs exactly as from task progress, under the supervisor whose
 * code it is. Wrong codes lock the student out for a while, so codes
 * can't be guessed. See App\Services\SupervisorCode.
 */
class SupervisorCodeController extends Controller
{
    private const MAX_WRONG = 5;

    private const LOCK_SECONDS = 900;

    public function start(Request $request): JsonResponse
    {
        $doctor = $this->doctor();
        $validated = $request->validate([
            'task_id' => ['required', 'integer'],
            'code' => ['required', 'string', 'max:20'],
            'form_type' => ['required', 'in:electronic,paper'],
            'photo' => ['nullable', 'image', 'mimes:jpeg,jpg,png,webp', 'max:15360'],
            'notes' => ['nullable', 'string', 'max:2000'],
        ]);
        $task = Task::findOrFail($validated['task_id']);
        $supervisor = $this->supervisor($doctor, 'start', $validated['code'], $task);

        try {
            $instance = TaskStartRequests::startWithCode($doctor, $task, $validated['form_type'], $request->file('photo'), $validated['notes'] ?? null, $supervisor);
        } catch (TaskStartException|PatientScreeningException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->json(['message' => 'تم بدء المهمة.', 'instance_id' => $instance->id, 'supervisor' => $this->name($supervisor)]);
    }

    public function signStep(Request $request, TaskInstance $taskInstance): JsonResponse
    {
        $doctor = $this->ownCase($taskInstance);
        $validated = $request->validate([
            'code' => ['required', 'string', 'max:20'],
            'step' => ['required', 'string', 'max:40'],
            'grade' => ['nullable', 'numeric', 'min:0'],
        ]);
        $this->ensureAssigned($taskInstance);
        $supervisor = $this->supervisor($doctor, 'step', $validated['code'], $taskInstance->task);

        TaskSteps::sign($taskInstance, $validated['step'], $validated['grade'] ?? null, $this->name($supervisor));

        return response()->json(['message' => 'تم توقيع الخطوة.', 'supervisor' => $this->name($supervisor)]);
    }

    /**
     * Adds a step to this case (2026-10-30, by request), as the supervisor
     * does from task progress; it is then signed like the task's own steps.
     */
    public function addStep(Request $request, TaskInstance $taskInstance): JsonResponse
    {
        $doctor = $this->ownCase($taskInstance);
        $validated = $request->validate([
            'code' => ['required', 'string', 'max:20'],
            'label' => ['required', 'string', 'max:100'],
            'max' => ['required', 'numeric', 'min:0.5', 'max:100'],
        ]);
        $this->ensureAssigned($taskInstance);
        $supervisor = $this->supervisor($doctor, 'add_step', $validated['code'], $taskInstance->task);

        TaskSteps::addExtra($taskInstance, trim($validated['label']), (float) $validated['max']);

        return response()->json(['message' => 'تمت إضافة الخطوة.', 'supervisor' => $this->name($supervisor)]);
    }

    public function complete(Request $request, TaskInstance $taskInstance): JsonResponse
    {
        $doctor = $this->ownCase($taskInstance);
        $validated = $request->validate([
            'code' => ['required', 'string', 'max:20'],
            'grade' => ['nullable', 'numeric', 'min:0'],
            'notes' => ['nullable', 'string', 'max:2000'],
        ]);
        $this->ensureAssigned($taskInstance);
        $supervisor = $this->supervisor($doctor, 'finish', $validated['code'], $taskInstance->task);

        try {
            TaskInstanceGrader::complete($taskInstance, $validated['grade'] ?? null, $validated['notes'] ?? null);
        } catch (TaskGradeException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->json(['message' => 'تم إكمال المهمة.', 'supervisor' => $this->name($supervisor)]);
    }

    /** The supervisor behind $code who may do $action on $task; counts wrong codes. */
    private function supervisor(Doctor $doctor, string $action, string $code, ?Task $task): User
    {
        if (! FormSettings::codeAllows($action)) {
            throw ValidationException::withMessages(['code' => 'استخدام كود المشرف لهذا الإجراء غير مفعّل.']);
        }
        $key = 'supervisor-code:'.$doctor->id;
        if (RateLimiter::tooManyAttempts($key, self::MAX_WRONG)) {
            $minutes = (int) ceil(RateLimiter::availableIn($key) / 60);
            throw ValidationException::withMessages(['code' => "محاولات خاطئة كثيرة. حاول بعد {$minutes} دقيقة."]);
        }

        $supervisor = $task ? SupervisorCode::resolve($code, FormSettings::ACTIONS[$action], $task) : null;
        if (! $supervisor) {
            RateLimiter::hit($key, self::LOCK_SECONDS);
            throw ValidationException::withMessages(['code' => 'الكود غير صحيح أو انتهت صلاحيته، أو ليس لصاحبه صلاحية هذا الإجراء.']);
        }
        RateLimiter::clear($key);

        return $supervisor;
    }

    private function ownCase(TaskInstance $taskInstance): Doctor
    {
        $doctor = $this->doctor();
        abort_unless((int) $taskInstance->doctor_id === (int) $doctor->id, 403);
        $taskInstance->loadMissing('task');

        return $doctor;
    }

    private function ensureAssigned(TaskInstance $taskInstance): void
    {
        if ($taskInstance->status !== 'assigned') {
            throw ValidationException::withMessages(['code' => 'هذه الحالة ليست قيد التنفيذ.']);
        }
    }

    private function name(User $user): string
    {
        return $user->full_name ?? $user->name ?? 'المشرف';
    }

    private function doctor(): Doctor
    {
        $doctor = Auth::guard('doctor')->user() ?? request()->user();
        abort_unless($doctor instanceof Doctor, 403);

        return $doctor;
    }
}
