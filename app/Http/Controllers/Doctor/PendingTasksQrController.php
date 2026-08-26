<?php

namespace App\Http\Controllers\Doctor;

use App\Http\Controllers\Controller;
use App\Models\Task;
use App\Support\PendingTaskFinder;
use App\Support\QrCodeFactory;
use Illuminate\Http\Response as HttpResponse;
use Illuminate\Support\Facades\Auth;
use Inertia\Inertia;
use Inertia\Response;

/**
 * "رموز المهام المعلقة" — port of
 * dental_clinics2/doctor/doctor_pending_tasks_qr.php.
 *
 * "Pending" here means a task in the doctor's stage that the doctor has
 * **no instance of at all** (the original's `t.id NOT IN (SELECT task_id
 * FROM task_instances WHERE doctor_id = ?)`) — i.e. not yet started, which
 * is a different sense of "pending" from `task_instances.status='pending'`.
 * The QR is what a supervisor scans to start the task for this doctor.
 */
class PendingTasksQrController extends Controller
{
    public function index(): Response
    {
        $doctor = Auth::guard('doctor')->user();

        $tasks = PendingTaskFinder::forDoctor($doctor)
            ->map(fn ($t) => [
                'id' => $t->id,
                'title' => $t->title,
                'department' => $t->department?->name,
                'required_count' => $t->required_count,
                'notes' => $t->notes,
                'grade' => $t->grade,
            ]);

        return Inertia::render('Doctor/PendingTasksQr', [
            'tasks' => $tasks,
        ]);
    }

    /**
     * PNG for one pending task. Payload identifies the doctor+task pair
     * (there is no instance yet to point at), so a scan can create and
     * assign one.
     */
    public function qr(Task $task): HttpResponse
    {
        $doctor = Auth::guard('doctor')->user();
        abort_unless($task->stage_id === $doctor->stage_id, 403);

        $payload = QrCodeFactory::rawPayload([
            'type' => 'pending_task',
            'task_id' => $task->id,
            'doctor_id' => $doctor->id,
        ]);

        return QrCodeFactory::pngResponse($payload, 300, 'private, max-age=600');
    }
}
