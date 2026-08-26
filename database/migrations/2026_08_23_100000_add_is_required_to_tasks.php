<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Whether a task is أساسية (mandatory) or اختيارية (optional) — a concept
 * that didn't exist anywhere in this app before (confirmed via grep;
 * `required_per_doctor`/`required_count` are unrelated completion counts,
 * not a mandatory/elective flag). Defaults to true so every existing task
 * — which today is implicitly mandatory, there being no other option —
 * keeps its current effective meaning with no data migration needed.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tasks', function (Blueprint $table) {
            $table->boolean('is_required')->default(true)->after('grade');
        });
    }

    public function down(): void
    {
        Schema::table('tasks', function (Blueprint $table) {
            $table->dropColumn('is_required');
        });
    }
};
