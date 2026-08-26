<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\TaskInstanceResource;
use App\Models\Doctor;
use App\Models\TaskInstance;
use App\Support\QrCodeFactory;
use App\Support\TaskInstanceVisibility;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;

/**
 * QR check-in for task instances (a doctor's assigned case), replacing the
 * original app's QR system.
 *
 * The original had QR generation scattered across several pages with
 * incompatible payload shapes — includes/qr_generator_modal.php encodes
 * `{"t":"ti","i":<task_instance_id>,"s":"P|A|C"}`,
 * doctor/doctor_pending_tasks_qr.php encodes a *different* shape,
 * `{"t":"task","task_id":<id>,"s":"P"}` — and the one endpoint that
 * actually processes a scanned code (process_qr_result.php) only handles a
 * third shape (`{"type":"doctor","id":...}`) by writing to a
 * `qr_scan_logs` table that **does not exist** in the imported schema
 * (verified: not in database/schema_import.sql, not created by any
 * migration script in the original app either) — so that flow would throw
 * a SQL error today even in the original app. Everything else falls
 * through to a no-op "here's your raw text back" response.
 *
 * Given that fragmentation, this rebuild defines one clean, versioned
 * payload instead of reproducing three incompatible ones:
 * `{"type":"task_instance","id":<task_instance_id>}`. Same underlying
 * concept (scan a code to open a specific assigned case), one real,
 * working implementation.
 */
class TaskInstanceQrController extends Controller
{
    public function show(Request $request, TaskInstance $taskInstance): Response
    {
        $doctor = $request->user();

        if ($doctor instanceof Doctor) {
            abort_unless($taskInstance->doctor_id === $doctor->id, 403);
        }

        return QrCodeFactory::pngResponse(
            QrCodeFactory::payload('task_instance', $taskInstance->id),
            (int) $request->integer('size', 300),
        );
    }

    /**
     * The doctor app's "scan this code" endpoint: given the raw decoded QR
     * text, resolves and returns the referenced task instance.
     */
    public function scan(Request $request): JsonResponse
    {
        $request->validate(['payload' => ['required', 'string']]);

        $decoded = json_decode($request->string('payload'), true);

        abort_if(
            ! is_array($decoded) || ($decoded['type'] ?? null) !== 'task_instance' || empty($decoded['id']),
            422,
            'Not a recognized task instance QR code.'
        );

        $taskInstance = TaskInstance::with(['task.department', 'task.caseSheetType'])
            ->findOrFail($decoded['id']);

        $doctor = $request->user();
        if ($doctor instanceof Doctor) {
            abort_unless($taskInstance->doctor_id === $doctor->id, 403, 'This case is assigned to a different doctor.');
        }

        if (TaskInstanceVisibility::canSeeStudentInfo($doctor)) {
            $taskInstance->load(['doctor', 'assignedBy']);
        }

        return (new TaskInstanceResource($taskInstance))->response();
    }
}
