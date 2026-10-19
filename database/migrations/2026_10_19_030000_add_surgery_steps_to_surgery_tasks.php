<?php

use App\Support\TaskScoring;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Tasks already on the surgery sheet get its sections as graded steps
 * (2026-10-19, by request), as new ones do when the sheet is chosen; see
 * TaskScoring::withSurgerySteps(). Runs after the pediatric tasks moved to
 * their sheets, so the pediatric extraction gets them too.
 */
return new class extends Migration
{
    public function up(): void
    {
        $surgery = DB::table('case_sheet_types')->where('type_code', 'surgery')->value('id');
        if (! $surgery) {
            return;
        }

        foreach (DB::table('tasks')->where('case_sheet_type_id', $surgery)->get(['id', 'scoring']) as $task) {
            $scoring = $task->scoring ? json_decode($task->scoring, true) : null;
            if (! empty($scoring['steps'])) {
                continue;
            }
            DB::table('tasks')->where('id', $task->id)->update([
                'scoring' => json_encode(TaskScoring::withSurgerySteps($scoring), JSON_UNESCAPED_UNICODE),
            ]);
        }
    }

    public function down(): void
    {
        // The steps are part of each task's setup now and editable there.
    }
};
