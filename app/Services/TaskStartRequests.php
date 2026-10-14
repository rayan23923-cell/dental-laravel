<?php

namespace App\Services;

use App\Models\Doctor;
use App\Models\Task;
use App\Models\TaskInstance;
use App\Models\TaskStartRequest;
use App\Models\User;
use App\Support\CaseSheetResolver;
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
        if ((int) $task->stage_id !== (int) $doctor->stage_id) {
            throw ValidationException::withMessages(['task_id' => 'هذه المهمة ليست من مهام مرحلتك.']);
        }
        if (TaskStartRequest::where('doctor_id', $doctor->id)->where('task_id', $task->id)->where('status', 'pending')->exists()) {
            throw ValidationException::withMessages(['task_id' => 'لديك طلب بدء لهذه المهمة بانتظار الموافقة.']);
        }
        $started = TaskInstance::where('doctor_id', $doctor->id)->where('task_id', $task->id)
            ->whereIn('status', ['assigned', 'completed'])->count();
        if ($started >= (int) $task->required_count) {
            throw ValidationException::withMessages(['task_id' => 'بدأت كل الحالات المطلوبة لهذه المهمة.']);
        }
        if ($formType === 'paper' && ! $photo) {
            throw ValidationException::withMessages(['photo' => 'أرفق صورة النموذج الورقي.']);
        }

        return TaskStartRequest::create([
            'doctor_id' => $doctor->id,
            'task_id' => $task->id,
            'form_type' => $formType,
            'photo_path' => $formType === 'paper' ? $photo->store(self::PHOTO_DIR, 'public') : null,
            'notes' => $notes,
            'status' => 'pending',
        ]);
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
