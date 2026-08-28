<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Task;
use App\Support\QrCodeFactory;
use Illuminate\Http\Request;
use Illuminate\Http\Response as HttpResponse;

/**
 * Flutter's equivalent of `Doctor\PendingTasksQrController::qr()` — same
 * payload, same access check, PNG instead of an Inertia-rendered page.
 * Added 2026-08-27: each unstarted case row in the doctor app's "مهامي"
 * list now shows this QR (identical across every remaining unstarted slot
 * of the same task — there's no finer-grained identity until one is
 * claimed, matching `TaskStarter`'s existing fungible-pending-slot
 * design), so a senior/admin can scan it straight from that row to start
 * the case, the same way the web's "رموز المهام المعلقة" page already
 * works.
 */
class PendingTaskQrController extends Controller
{
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
