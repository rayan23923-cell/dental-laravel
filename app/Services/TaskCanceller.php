<?php

namespace App\Services;

use App\Models\TaskInstance;
use App\Models\TaskStartRequest;
use App\Support\CaseSheetResolver;
use App\Support\FormSettings;
use Illuminate\Support\Facades\DB;

/**
 * "إلغاء بدء المهمة" (2026-10-23, by request): takes back a started case
 * that isn't completed, so the doctor's task shows as not started again.
 * The case's signed steps, grade and paper photos go with it; a case sheet
 * already filled stays as the doctor's draft for that task
 * (CaseSheetResolver::detachFrom).
 */
class TaskCanceller
{
    /** @throws TaskStartException */
    public static function cancel(TaskInstance $instance): void
    {
        if (! FormSettings::on('task_cancel_enabled')) {
            throw new TaskStartException('إلغاء بدء المهام متوقف حالياً من الإعدادات العامة.');
        }
        if ($instance->status !== 'assigned') {
            throw new TaskStartException('لا يمكن إلغاء إلا مهمة بدأت ولم تكتمل.');
        }

        DB::transaction(function () use ($instance) {
            CaseSheetResolver::detachFrom($instance);
            TaskStartRequest::where('task_instance_id', $instance->id)->update(['task_instance_id' => null]);
            // One by one so each photo's file is removed too.
            $instance->attachments->each->delete();
            $instance->delete();
        });
    }
}
