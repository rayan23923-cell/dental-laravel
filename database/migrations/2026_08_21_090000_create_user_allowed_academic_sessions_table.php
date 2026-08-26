<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A fourth scope dimension alongside the original's three
 * (`user_allowed_departments`/`_stages`/`_education_types`) — restricts
 * which academic years a staff member's own account can see, the same
 * "zero rows = unrestricted" rule App\Services\ScopeHelper already applies
 * to the other three (see its docblock).
 *
 * The original app has no such concept — academic sessions as a whole are a
 * subsystem this rebuild added (see README "Doctors, groups and tasks tied
 * to an academic session"), so there was nothing to port here. Shaped to
 * match its three siblings exactly, columns and constraints both: composite
 * primary key, no surrogate `id`, no timestamps, and — checked directly
 * against their live table definitions rather than assumed — **no foreign
 * key constraints either**, so this doesn't add one where they have none.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('user_allowed_academic_sessions', function (Blueprint $table) {
            $table->unsignedBigInteger('user_id');
            $table->unsignedInteger('academic_session_id');
            $table->primary(['user_id', 'academic_session_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('user_allowed_academic_sessions');
    }
};
