<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Steps a supervisor adds to one case, each with its name and grade
 * (2026-10-19, by request); see App\Support\TaskSteps.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('task_instances', function (Blueprint $table) {
            $table->json('extra_steps')->nullable()->after('step_signoffs');
        });
    }

    public function down(): void
    {
        Schema::table('task_instances', function (Blueprint $table) {
            $table->dropColumn('extra_steps');
        });
    }
};
