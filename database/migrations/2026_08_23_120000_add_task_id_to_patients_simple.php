<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * "التشخيص" (diagnosis) — a plain task pick at registration time, purely
 * informational (shows which stage/education-type the task belongs to,
 * doesn't gate or filter anything). No FK: a task could be retired later
 * without blocking historical registrations, same reasoning as every
 * other additive link column this session. `integer()`, not
 * `unsignedInteger()` — `tasks.id` is a plain signed `int(11)` (confirmed
 * via `SHOW COLUMNS FROM tasks`), and a mismatched signedness is what
 * broke the `appointments.patient_registration_id` FK earlier (errno 150)
 * even though there's no FK here to trip on; kept consistent anyway.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('patients_simple', function (Blueprint $table) {
            $table->integer('task_id')->nullable()->after('service_id');
        });
    }

    public function down(): void
    {
        Schema::table('patients_simple', function (Blueprint $table) {
            $table->dropColumn('task_id');
        });
    }
};
