<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * "المطلوب لكل طبيب" was dropped (2026-10-13, by request): `required_count`
 * is now the one per-doctor cap. Brings existing rows in step so the legacy
 * column never disagrees with it (Task::booted() keeps new saves in step).
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::table('tasks')->update(['required_per_doctor' => DB::raw('required_count')]);
    }

    public function down(): void
    {
        // Data-only; nothing to undo.
    }
};
