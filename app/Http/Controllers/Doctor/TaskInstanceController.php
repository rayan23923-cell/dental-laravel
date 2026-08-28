<?php

namespace App\Http\Controllers\Doctor;

use App\Http\Controllers\Controller;
use App\Models\TaskInstance;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;

class TaskInstanceController extends Controller
{
    public function update(Request $request, TaskInstance $taskInstance): RedirectResponse
    {
        $doctor = Auth::guard('doctor')->user();
        abort_unless($taskInstance->doctor_id === $doctor->id, 403);

        $validated = $request->validate([
            'status' => ['required', 'in:pending,assigned,completed'],
            'notes' => ['nullable', 'string'],
        ]);

        if ($validated['status'] === 'completed' && $taskInstance->status !== 'completed') {
            $validated['completion_date'] = now();
        }

        $taskInstance->update($validated);

        return back()->with('success', 'Task updated.');
    }

    /**
     * "شكرا، تم توثيقه ورقياً" (2026-08-28) — same non-exclusive
     * paper-documented confirmation as the API equivalent; see that
     * method's doc comment for why this never blocks or hides the
     * electronic case-sheet flow.
     */
    public function confirmPaper(TaskInstance $taskInstance): RedirectResponse
    {
        $doctor = Auth::guard('doctor')->user();
        abort_unless($taskInstance->doctor_id === $doctor->id, 403);

        $taskInstance->update([
            'paper_case_sheet_confirmed_by' => $doctor->id,
            'paper_case_sheet_confirmed_at' => now(),
        ]);

        return back()->with('success', 'تم تأكيد توثيق الحالة ورقياً.');
    }
}
