<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * "نطاق الوصول" with nothing picked used to mean "sees everything"
 * (2026-10-18, by request it now means nothing): "الكل" becomes a choice of
 * its own, kept in these two flags. Stages and departments still follow the
 * level above when none are picked.
 *
 * Existing accounts keep what they had: those with nothing picked get "الكل",
 * except the desk roles, whose work never reads the scoped data.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->boolean('scope_all_education_types')->default(false);
            $table->boolean('scope_all_academic_sessions')->default(false);
        });

        $users = DB::table('users')->whereNotIn('role', ['reception', 'lab', 'accountant']);
        (clone $users)->whereNotIn('id', DB::table('user_allowed_education_types')->select('user_id'))
            ->update(['scope_all_education_types' => true]);
        (clone $users)->whereNotIn('id', DB::table('user_allowed_academic_sessions')->select('user_id'))
            ->update(['scope_all_academic_sessions' => true]);
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn(['scope_all_education_types', 'scope_all_academic_sessions']);
        });
    }
};
