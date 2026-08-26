<?php

namespace App\Http\Controllers;

use App\Models\Task;
use App\Models\TaskInstance;
use App\Support\QrCodeFactory;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Auth;

class TaskInstanceController extends Controller
{
    /**
     * Same payload/generation as Api\TaskInstanceQrController::show() — for
     * printing/displaying from the admin UI.
     */
    public function qr(TaskInstance $taskInstance): Response
    {
        return QrCodeFactory::pngResponse(
            QrCodeFactory::payload('task_instance', $taskInstance->id),
        );
    }

    public function store(Request $request, Task $task): RedirectResponse
    {
        $validated = $request->validate([
            'doctor_id' => ['required', 'exists:doctors,id'],
        ]);

        TaskInstance::create([
            'task_id' => $task->id,
            'doctor_id' => $validated['doctor_id'],
            'status' => 'assigned',
            'assigned_date' => now(),
            'assigned_by' => Auth::id(),
        ]);

        return back()->with('success', 'Task assigned to doctor.');
    }

    public function update(Request $request, TaskInstance $taskInstance): RedirectResponse
    {
        $validated = $request->validate([
            'status' => ['required', 'in:pending,assigned,completed'],
            'grade' => ['nullable', 'numeric', 'min:0', 'max:999.99'],
            'notes' => ['nullable', 'string'],
        ]);

        if ($validated['status'] === 'completed' && $taskInstance->status !== 'completed') {
            $validated['completion_date'] = now();
        } elseif ($validated['status'] !== 'completed' && $taskInstance->status === 'completed') {
            // Matches admin/ajax/toggle_task_instance.php's "uncomplete"
            // action: reverting away from completed clears completion_date
            // rather than leaving a stale timestamp on a no-longer-complete
            // instance.
            $validated['completion_date'] = null;
        }

        $taskInstance->update($validated);

        return back()->with('success', 'Task instance updated.');
    }

    public function destroy(TaskInstance $taskInstance): RedirectResponse
    {
        $taskInstance->delete();

        return back()->with('success', 'Task assignment removed.');
    }
}
