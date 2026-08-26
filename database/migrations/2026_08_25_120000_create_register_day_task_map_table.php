<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Day-governed diagnosis: which `Task`s ("التشخيص") are offered on which
 * `RegisterDay` — the same relationship `register_day_service_map`
 * already gives `Service`, but for `Task`. No legacy counterpart exists
 * for this table (confirmed against both the current schema and the
 * imported `clinic_system2` dump — the original app has no day/diagnosis
 * link at all), so unlike almost everything else in this project's
 * schema this is a genuinely new table, not an import. Same shape as
 * `register_day_service_map`'s actual DDL: two plain int columns, no
 * surrogate id, no FK constraints (that table has none either).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('register_day_task_map', function (Blueprint $table) {
            $table->integer('day_id');
            $table->integer('task_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('register_day_task_map');
    }
};
