<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Lets a doctor mark a case as documented on paper instead of (not
 * "instead of" — alongside; see the doc comment on the confirm-paper
 * endpoint) the electronic case sheet. Purely an informational tag —
 * never blocks or hides the electronic "نموذج سريري" flow, per the
 * user's explicit confirmation. Nullable, no FK on the `by` column —
 * same convention as `screening_checked_by`/`screening_checked_at` on
 * `patients_simple`.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('task_instances', function (Blueprint $table) {
            $table->integer('paper_case_sheet_confirmed_by')->nullable()->after('patient_registration_id');
            $table->timestamp('paper_case_sheet_confirmed_at')->nullable()->after('paper_case_sheet_confirmed_by');
        });
    }

    public function down(): void
    {
        Schema::table('task_instances', function (Blueprint $table) {
            $table->dropColumn(['paper_case_sheet_confirmed_by', 'paper_case_sheet_confirmed_at']);
        });
    }
};
