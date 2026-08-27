<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * `groups.academic_session_id`, `tasks.academic_session_id`, and
 * `task_assignments.academic_session_id` are all present in
 * `database/schema_import.sql` (the dump this project's local dev DB was
 * seeded from) and `AcademicSessionController`/`Group`/`Task` code has
 * relied on them existing ever since — but production's actual, older
 * `clinic_system2` database (adopted as-is via
 * `2024_01_01_000000_import_clinic_schema` being marked already-run
 * rather than executed, since its tables already existed there) predates
 * whichever point the legacy app added these columns. First production
 * hit: `GET /api/v1/academic-sessions` throwing
 * `SQLSTATE[42S22]: Unknown column 'groups.academic_session_id'`.
 * `Schema::hasColumn` guards make this safe to run regardless of which of
 * the three tables are actually missing it on a given database (unlike
 * `doctors.academic_session_id`, added by its own already-run migration,
 * these three never got one — the base import was assumed sufficient).
 */
return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasColumn('groups', 'academic_session_id')) {
            Schema::table('groups', function (Blueprint $table) {
                $table->integer('academic_session_id')->nullable()->after('stage_id');
            });
        }

        if (! Schema::hasColumn('tasks', 'academic_session_id')) {
            Schema::table('tasks', function (Blueprint $table) {
                $table->integer('academic_session_id')->nullable()->after('stage_id');
            });
        }

        if (! Schema::hasColumn('task_assignments', 'academic_session_id')) {
            Schema::table('task_assignments', function (Blueprint $table) {
                $table->integer('academic_session_id')->nullable()->after('completed_count');
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasColumn('groups', 'academic_session_id')) {
            Schema::table('groups', fn (Blueprint $table) => $table->dropColumn('academic_session_id'));
        }

        if (Schema::hasColumn('tasks', 'academic_session_id')) {
            Schema::table('tasks', fn (Blueprint $table) => $table->dropColumn('academic_session_id'));
        }

        if (Schema::hasColumn('task_assignments', 'academic_session_id')) {
            Schema::table('task_assignments', fn (Blueprint $table) => $table->dropColumn('academic_session_id'));
        }
    }
};
