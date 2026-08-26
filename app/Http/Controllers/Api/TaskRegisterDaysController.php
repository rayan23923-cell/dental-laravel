<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Task;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Syncs which `RegisterDay`s a task ("التشخيص") is offered on — the
 * settings-screen half of day-governed diagnosis (see
 * `RegisterDay::tasks()`'s docblock). Deliberately not a method on
 * `Api\TaskController` (gated `permission:tasks,*`, task CRUD) or
 * `Api\ServiceController` — this is a `settings,edit` action on an
 * *existing* task, same reasoning `RegisterDayController`'s own docblock
 * gives for keeping this feature's endpoints separate from unrelated
 * permission modules. No index/store/destroy here: tasks themselves are
 * created/edited/deleted in Tasks admin, this only syncs one pivot.
 */
class TaskRegisterDaysController extends Controller
{
    public function update(Request $request, Task $task): JsonResponse
    {
        $validated = $request->validate([
            'day_ids' => ['array'],
            'day_ids.*' => ['integer', 'exists:register_days,id'],
        ]);

        $task->days()->sync($validated['day_ids'] ?? []);

        return response()->json($task->load('days'));
    }
}
