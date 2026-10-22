<?php

namespace App\Services;

use App\Models\Doctor;
use App\Models\Task;
use App\Models\TaskInstance;
use App\Models\TaskStartRequest;
use App\Models\User;
use App\Notifications\TaskStartRequestNotice;
use App\Support\CaseSheetResolver;
use App\Support\FormSettings;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;

/**
 * "طلبات بدء المهام" (2026-10-14, by request). A doctor asks for one of
 * their stage's tasks to be started, attaching either the electronic case
 * sheet (their pre-instance draft, see CaseSheetResolver) or a photo of
 * the paper one. Staff who may start tasks review it from task progress:
 * approving runs the normal TaskStarter (same guards), then hands the
 * draft or the photo over to the new task instance.
 */
class TaskStartRequests
{
    public const PHOTO_DIR = 'task-start-requests';

    public static function create(Doctor $doctor, Task $task, string $formType, ?UploadedFile $photo, ?string $notes): TaskStartRequest
    {
        self::ensureCanStart($doctor, $task, $formType);
        if (TaskStartRequest::where('doctor_id', $doctor->id)->where('task_id', $task->id)->where('status', 'pending')->exists()) {
            throw ValidationException::withMessages(['task_id' => 'لديك طلب بدء لهذه المهمة بانتظار الموافقة.']);
        }
        if ($formType === 'paper' && ! $photo) {
            throw ValidationException::withMessages(['photo' => 'أرفق صورة النموذج الورقي.']);
        }

        $request = self::record($doctor, $task, $formType, $photo, $notes);

        foreach (self::reviewersOf($request) as $user) {
            Notifier::send($user, new TaskStartRequestNotice(
                'طلب بدء مهمة جديد',
                "{$doctor->name} يطلب بدء مهمة \"{$task->title}\".",
                $request->id,
                'new',
            ));
        }

        return $request;
    }

    /**
     * Started on the spot with a supervisor's code (2026-10-22, see
     * SupervisorCode): the doctor's pending request for this task, or a new
     * one, approved by $supervisor straight away. The photo is optional
     * here, since the supervisor is with the student.
     *
     * @throws TaskStartException|PatientScreeningException
     */
    public static function startWithCode(Doctor $doctor, Task $task, string $formType, ?UploadedFile $photo, ?string $notes, User $supervisor): TaskInstance
    {
        self::ensureCanStart($doctor, $task, $formType);
        $request = TaskStartRequest::where('doctor_id', $doctor->id)->where('task_id', $task->id)->where('status', 'pending')->first();
        if ($request && $photo && ! $request->photo_path) {
            $request->update(['form_type' => $formType, 'photo_path' => $photo->store(self::PHOTO_DIR, 'public')]);
        }
        $request ??= self::record($doctor, $task, $formType, $photo, $notes);

        $instance = self::approve($request, $supervisor, null);
        $request->update(['review_note' => 'بكود المشرف']);

        return $instance;
    }

    private static function ensureCanStart(Doctor $doctor, Task $task, string $formType): void
    {
        if ((int) $task->stage_id !== (int) $doctor->stage_id) {
            throw ValidationException::withMessages(['task_id' => 'هذه المهمة ليست من مهام مرحلتك.']);
        }
        if (! FormSettings::formTypeEnabled($formType)) {
            throw ValidationException::withMessages(['form_type' => $formType === 'paper' ? 'النموذج الورقي غير مفعّل.' : 'النموذج الإلكتروني غير مفعّل.']);
        }
        $started = TaskInstance::where('doctor_id', $doctor->id)->where('task_id', $task->id)
            ->whereIn('status', ['assigned', 'completed'])->count();
        if ($started >= (int) $task->required_count) {
            throw ValidationException::withMessages(['task_id' => 'بدأت كل الحالات المطلوبة لهذه المهمة.']);
        }
    }

    private static function record(Doctor $doctor, Task $task, string $formType, ?UploadedFile $photo, ?string $notes): TaskStartRequest
    {
        return TaskStartRequest::create([
            'doctor_id' => $doctor->id,
            'task_id' => $task->id,
            'form_type' => $formType,
            'photo_path' => $formType === 'paper' && $photo ? $photo->store(self::PHOTO_DIR, 'public') : null,
            'notes' => $notes,
            'status' => 'pending',
        ]);
    }

    /** Active staff who may start tasks and can see this request's task. */
    public static function reviewersOf(TaskStartRequest $request): \Illuminate\Support\Collection
    {
        return User::query()->where('status', 'active')->get()
            ->filter(fn (User $user) => (new PermissionManager($user))->can('task_progress', 'start')
                && self::visibleTo($user)->whereKey($request->id)->exists())
            ->values();
    }

    /** Requests a staff member may review: tasks of the stages and departments they can see. */
    public static function visibleTo(User $user): Builder
    {
        return TaskStartRequest::query()->whereHas('task', function ($q) use ($user) {
            ScopeHelper::scopeStages($q, $user, 'stage_id');
            ScopeHelper::scopeDepartments($q, $user, 'department_id');
        });
    }

    /** @throws TaskStartException|PatientScreeningException */
    public static function approve(TaskStartRequest $request, User $reviewer, ?string $note): TaskInstance
    {
        self::ensurePending($request);

        $instance = TaskStarter::start($request->task, $request->doctor, null, $note ?: $request->notes, $reviewer->id);

        DB::transaction(function () use ($request, $reviewer, $note, $instance) {
            // Electronic: the doctor's draft becomes this instance's sheet.
            if ($request->form_type === 'electronic') {
                $resource = CaseSheetResolver::resourceForTask($request->task);
                $model = CaseSheetResolver::modelFor($resource);
                $draftId = CaseSheetResolver::existingDraftRecordId($resource, $request->doctor_id, $request->task_id);
                if ($model && $draftId && ! CaseSheetResolver::existingRecordId($resource, $instance->id)) {
                    $model::whereKey($draftId)->update(['task_instances_id' => $instance->id]);
                }
            }

            // Paper: the photo joins the instance's paper-form attachments.
            if ($request->photo_path && Storage::disk('public')->exists($request->photo_path)) {
                $path = 'task-forms/'.$instance->id.'/'.basename($request->photo_path);
                Storage::disk('public')->move($request->photo_path, $path);
                $instance->attachments()->create([
                    'path' => $path,
                    'size' => (int) Storage::disk('public')->size($path),
                    'uploaded_by_doctor_id' => $request->doctor_id,
                ]);
                $request->photo_path = null;
            }

            $request->fill([
                'status' => 'approved',
                'reviewed_by_user_id' => $reviewer->id,
                'reviewed_at' => now(),
                'review_note' => $note,
                'task_instance_id' => $instance->id,
            ])->save();
        });

        return $instance;
    }

    public static function reject(TaskStartRequest $request, User $reviewer, ?string $note): void
    {
        self::ensurePending($request);

        $request->update([
            'status' => 'rejected',
            'reviewed_by_user_id' => $reviewer->id,
            'reviewed_at' => now(),
            'review_note' => $note,
        ]);

        Notifier::send($request->doctor, new TaskStartRequestNotice(
            'لم تتم الموافقة على طلب البدء',
            "لم تتم الموافقة على بدء مهمة \"{$request->task?->title}\".".($note ? " السبب: {$note}" : ''),
            $request->id,
            'rejected',
        ));
        PushNotifier::send($request->doctor, 'طلب بدء مهمة', "لم تتم الموافقة على بدء مهمة \"{$request->task?->title}\".".($note ? " السبب: {$note}" : ''), [
            'task_start_request_id' => (string) $request->id,
        ]);
    }

    /** A doctor withdraws their own pending request. */
    public static function cancel(TaskStartRequest $request): void
    {
        self::ensurePending($request);
        if ($request->photo_path) {
            Storage::disk('public')->delete($request->photo_path);
        }
        $request->delete();
    }

    private static function ensurePending(TaskStartRequest $request): void
    {
        if ($request->status !== 'pending') {
            throw ValidationException::withMessages(['request' => 'تمت مراجعة هذا الطلب مسبقاً.']);
        }
    }
}
