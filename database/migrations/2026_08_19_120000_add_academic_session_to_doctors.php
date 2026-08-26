<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ties a doctor to the academic session they were enrolled in.
 *
 * `groups` and `tasks` already carry `academic_session_id`, but `doctors`
 * never did — in the original a doctor's session is only *implied* by their
 * group membership. That breaks down across years for two reasons:
 *
 *  1. a doctor with no group belongs to no session at all, so a new intake
 *     can't be listed or filtered until groups exist;
 *  2. `doctor_group_members` has no session column and the original enforces
 *     "one group at a time" by deleting every prior membership — so adding
 *     a doctor to a 2025 group **erases their 2024 group**, destroying the
 *     previous year's record.
 *
 * Nullable, so existing doctors stay visible under every session until an
 * admin assigns them (the same "no value = unrestricted" convention this
 * codebase already uses for scoping and for session-less groups/tasks).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('doctors', function (Blueprint $table) {
            $table->unsignedInteger('academic_session_id')->nullable()->after('stage_id');
            $table->index('academic_session_id');
        });

        // Membership becomes per-session, so a doctor can hold a 2024 group
        // and a 2025 group at once and last year's record survives.
        Schema::table('doctor_group_members', function (Blueprint $table) {
            $table->unsignedInteger('academic_session_id')->nullable()->after('doctor_id');
            $table->index(['doctor_id', 'academic_session_id']);
        });
    }

    public function down(): void
    {
        Schema::table('doctors', function (Blueprint $table) {
            $table->dropIndex(['academic_session_id']);
            $table->dropColumn('academic_session_id');
        });

        Schema::table('doctor_group_members', function (Blueprint $table) {
            $table->dropIndex(['doctor_id', 'academic_session_id']);
            $table->dropColumn('academic_session_id');
        });
    }
};
