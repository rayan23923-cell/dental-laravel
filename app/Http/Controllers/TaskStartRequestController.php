<?php

namespace App\Http\Controllers;

use App\Models\Doctor;
use App\Models\Task;
use App\Models\TaskStartRequest;
use App\Models\User;
use App\Services\PatientScreeningException;
use App\Services\TaskStartException;
use App\Services\TaskStartRequests;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;

/**
 * "طلبات بدء المهام" (2026-10-14, by request) — JSON endpoints shared by the
 * web (session) and the app (Sanctum): doctors file and withdraw requests,
 * staff with task-progress rights list, approve or reject them. See
 * App\Services\TaskStartRequests.
 */
class TaskStartRequestController extends Controller
{
    /** Staff: pending requests plus the most recent reviewed ones, and the badge count. */
    public function index(Request $request): JsonResponse
    {
        $base = fn () => TaskStartRequests::visibleTo($request->user());

        $pending = $base()->where('status', 'pending')->oldest()->get();
        $reviewed = $base()->whereIn('status', ['approved', 'rejected'])->latest('reviewed_at')->limit(100)->get();

        return response()->json([
            'pending' => $pending->map->toView()->values(),
            'approved' => $reviewed->where('status', 'approved')->map->toView()->values(),
            'rejected' => $reviewed->where('status', 'rejected')->map->toView()->values(),
            'pending_count' => $pending->count(),
        ]);
    }

    public function approve(Request $request, TaskStartRequest $taskStartRequest): JsonResponse
    {
        $this->authorizeReview($request, $taskStartRequest);
        $note = $request->validate(['note' => ['nullable', 'string', 'max:2000']])['note'] ?? null;

        try {
            TaskStartRequests::approve($taskStartRequest, $request->user(), $note);
        } catch (TaskStartException|PatientScreeningException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->json(['request' => $taskStartRequest->fresh()->toView()]);
    }

    public function reject(Request $request, TaskStartRequest $taskStartRequest): JsonResponse
    {
        $this->authorizeReview($request, $taskStartRequest);
        $note = $request->validate(['note' => ['nullable', 'string', 'max:2000']])['note'] ?? null;

        TaskStartRequests::reject($taskStartRequest, $request->user(), $note);

        return response()->json(['request' => $taskStartRequest->fresh()->toView()]);
    }

    /** Doctor: their own requests, newest first. */
    public function mine(): JsonResponse
    {
        $doctor = $this->doctor();

        return response()->json([
            'data' => TaskStartRequest::where('doctor_id', $doctor->id)->latest()->limit(200)->get()->map->toView()->values(),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $doctor = $this->doctor();
        $validated = $request->validate([
            'task_id' => ['required', 'integer'],
            'form_type' => ['required', 'in:electronic,paper'],
            'photo' => ['nullable', 'image', 'mimes:jpeg,jpg,png,webp', 'max:15360'],
            'notes' => ['nullable', 'string', 'max:2000'],
        ]);

        $created = TaskStartRequests::create(
            $doctor,
            Task::findOrFail($validated['task_id']),
            $validated['form_type'],
            $request->file('photo'),
            $validated['notes'] ?? null,
        );

        return response()->json(['request' => $created->toView()], 201);
    }

    public function destroy(TaskStartRequest $taskStartRequest): JsonResponse
    {
        abort_unless((int) $taskStartRequest->doctor_id === (int) $this->doctor()->id, 403);
        TaskStartRequests::cancel($taskStartRequest);

        return response()->json(null, 204);
    }

    private function doctor(): Doctor
    {
        $doctor = Auth::guard('doctor')->user() ?? request()->user();
        abort_unless($doctor instanceof Doctor, 403);

        return $doctor;
    }

    private function authorizeReview(Request $request, TaskStartRequest $taskStartRequest): void
    {
        abort_unless($request->user() instanceof User, 403);
        abort_unless(TaskStartRequests::visibleTo($request->user())->whereKey($taskStartRequest->id)->exists(), 404);
    }
}
