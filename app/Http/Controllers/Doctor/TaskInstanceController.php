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
}
