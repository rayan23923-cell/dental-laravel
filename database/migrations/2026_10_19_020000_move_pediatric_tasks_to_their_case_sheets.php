<?php

use App\Support\CaseSheetResolver;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Pediatric tasks show the case sheet they open (2026-10-19, by request:
 * "Extraction" carried the pediatric type and opened the operative sheet).
 * Each task on the pediatric type moves to its kind of work's type, when
 * that type exists; see CaseSheetResolver::pediatricTypeCode().
 */
return new class extends Migration
{
    public function up(): void
    {
        $pediatric = DB::table('case_sheet_types')->where('type_code', 'pediatric')->value('id');
        if (! $pediatric) {
            return;
        }
        $types = DB::table('case_sheet_types')->pluck('id', 'type_code');

        foreach (DB::table('tasks')->where('case_sheet_type_id', $pediatric)->get(['id', 'title']) as $task) {
            $target = $types[CaseSheetResolver::pediatricTypeCode($task->title)] ?? null;
            if ($target) {
                DB::table('tasks')->where('id', $task->id)->update(['case_sheet_type_id' => $target]);
            }
        }
    }

    public function down(): void
    {
        // The pediatric type opened the operative sheet for everything; nothing to restore.
    }
};
