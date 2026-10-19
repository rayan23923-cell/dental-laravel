<?php

use App\Support\TaskScoring;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Tasks already on the operative sheet get its sections as graded steps
 * (2026-10-19, by request), as new ones do when the sheet is chosen; see
 * TaskScoring::withSheetSteps().
 */
return new class extends Migration
{
    public function up(): void
    {
        $operative = DB::table('case_sheet_types')->where('type_code', 'operative')->value('id');
        if (! $operative) {
            return;
        }

        foreach (DB::table('tasks')->where('case_sheet_type_id', $operative)->get(['id', 'scoring']) as $task) {
            $scoring = $task->scoring ? json_decode($task->scoring, true) : null;
            if (! empty($scoring['steps'])) {
                continue;
            }
            DB::table('tasks')->where('id', $task->id)->update([
                'scoring' => json_encode(TaskScoring::withSheetSteps($scoring, 'operative'), JSON_UNESCAPED_UNICODE),
            ]);
        }
    }

    public function down(): void
    {
        // The steps are part of each task's setup now and editable there.
    }
};
