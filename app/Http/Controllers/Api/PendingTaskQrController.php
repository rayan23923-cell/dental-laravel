<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Task;
use App\Support\PendingTaskFinder;
use App\Support\QrCodeFactory;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response as HttpResponse;

/**
 * Flutter's equivalent of `Doctor\PendingTasksQrController` — same payload,
 * same access check, JSON/PNG instead of an Inertia-rendered page. Added
 * 2026-08-27: each unstarted case row in the doctor app's "مهامي" list
 * shows this QR (identical across every remaining unstarted slot of the
 * same task — there's no finer-grained identity until one is claimed,
 * matching `TaskStarter`'s existing fungible-pending-slot design), so a
 * senior/admin can scan it straight from that row to start the case, the
 * same way the web's "رموز المهام المعلقة" page already works.
 *
 * `index()` added 2026-09-01, by request — the dedicated "رموز المهام
 * المعلقة" page itself (a grid of every pending task type, not just the
 * per-row button already inline in "مهامي") had no Flutter counterpart at
 * all before this; `index()` is `Doctor\PendingTasksQrController::index()`'s
 * exact same `PendingTaskFinder::forDoctor()` list, JSON instead of an
 * Inertia page.
 */
class PendingTaskQrController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $doctor = $request->user();

        $tasks = PendingTaskFinder::forDoctor($doctor)->map(fn ($t) => [
            'id' => $t->id,
            'title' => $t->title,
            'department' => $t->department?->name,
            'required_count' => $t->required_count,
            'notes' => $t->notes,
            'grade' => $t->grade,
        ]);

        return response()->json(['data' => $tasks]);
    }

    public function show(Request $request, Task $task): HttpResponse
    {
        $doctor = $request->user();
        abort_unless($task->stage_id === $doctor->stage_id, 403);

        $payload = QrCodeFactory::rawPayload([
            'type' => 'pending_task',
            'task_id' => $task->id,
            'doctor_id' => $doctor->id,
        ]);

        return QrCodeFactory::pngResponse($payload, (int) $request->integer('size', 300), 'private, max-age=600');
    }
}
