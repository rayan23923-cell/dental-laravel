<?php

namespace App\Http\Controllers;

use App\Models\Doctor;
use App\Models\ScannerScan;
use App\Models\TaskInstance;
use App\Models\TaskInstanceAttachment;
use App\Models\User;
use App\Services\PermissionManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;

/**
 * Photos of a task's paper case sheet (2026-10-13, by request). Staff with
 * the task-progress screen attach them from the computer or from the
 * paired phone (`scan_id`, a photo the phone sent; see ScannerPairing);
 * a doctor attaches them to their own cases, from their own device.
 * Deleting needs `task_progress,finish` for staff, or being the doctor who
 * added it.
 */
class TaskInstanceAttachmentController extends Controller
{
    private const DIR = 'task-forms';

    public function index(TaskInstance $taskInstance): JsonResponse
    {
        $this->authorizeInstance($taskInstance);

        return $this->list($taskInstance);
    }

    public function store(Request $request, TaskInstance $taskInstance): JsonResponse
    {
        $principal = $this->authorizeInstance($taskInstance);

        $validated = $request->validate([
            'photo' => ['required_without:scan_id', 'image', 'mimes:jpeg,jpg,png,webp', 'max:15360'],
            'scan_id' => ['required_without:photo', 'integer'],
        ]);

        $dir = self::DIR.'/'.$taskInstance->id;

        if (isset($validated['scan_id'])) {
            // Only a photo the user's own paired phone sent, and only once.
            $scan = $principal instanceof User
                ? ScannerScan::whereKey($validated['scan_id'])->whereNotNull('photo_path')
                    ->whereHas('pairing', fn ($q) => $q->where('user_id', $principal->id))->first()
                : null;
            if (! $scan || ! Storage::disk('local')->exists($scan->photo_path)) {
                throw ValidationException::withMessages(['scan_id' => 'لم تعد صورة الموبايل متوفرة. التقطها من جديد.']);
            }
            $path = $dir.'/'.basename($scan->photo_path);
            Storage::disk('public')->writeStream($path, Storage::disk('local')->readStream($scan->photo_path));
            Storage::disk('local')->delete($scan->photo_path);
            $scan->update(['photo_path' => null]);
        } else {
            $path = $request->file('photo')->store($dir, 'public');
        }

        $taskInstance->attachments()->create([
            'path' => $path,
            'size' => (int) Storage::disk('public')->size($path),
            'uploaded_by_user_id' => $principal instanceof User ? $principal->id : null,
            'uploaded_by_doctor_id' => $principal instanceof Doctor ? $principal->id : null,
        ]);

        return $this->list($taskInstance, 201);
    }

    public function destroy(TaskInstanceAttachment $attachment): JsonResponse
    {
        $principal = $this->authorizeInstance($attachment->taskInstance);

        if ($principal instanceof Doctor) {
            abort_unless($attachment->uploaded_by_doctor_id === $principal->id, 403);
        } else {
            abort_unless((new PermissionManager($principal))->can('task_progress', 'finish'), 403);
        }

        $attachment->delete();

        return $this->list($attachment->taskInstance);
    }

    /** Staff (the route's permission middleware has checked them) or the instance's own doctor. */
    private function authorizeInstance(TaskInstance $taskInstance): User|Doctor
    {
        $doctor = Auth::guard('doctor')->user();
        if ($doctor && request()->routeIs('doctor.*')) {
            abort_unless($taskInstance->doctor_id === $doctor->id, 403);

            return $doctor;
        }

        $user = Auth::guard('web')->user();
        abort_unless($user instanceof User, 403);

        return $user;
    }

    private function list(TaskInstance $taskInstance, int $status = 200): JsonResponse
    {
        return response()->json([
            'data' => $taskInstance->attachments()->get()->map->toView()->values(),
        ], $status);
    }
}
