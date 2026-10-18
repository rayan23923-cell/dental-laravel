<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Each step of a case signed off with its grade, one after another
 * (2026-10-18, by request); see App\Support\TaskSteps.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('task_instances', function (Blueprint $table) {
            $table->json('step_signoffs')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('task_instances', function (Blueprint $table) {
            $table->dropColumn('step_signoffs');
        });
    }
};
