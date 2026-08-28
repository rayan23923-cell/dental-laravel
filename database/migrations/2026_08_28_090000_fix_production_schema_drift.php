<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Fixes the real, code-affecting gaps surfaced by `php artisan schema:diagnose`
 * against production (2026-08-28) — production's actual `clinic_system2`
 * database predates `database/schema_import.sql` in these specific spots
 * (same root cause as the two earlier one-off fixes documented in
 * README.md: `academic_sessions`/`groups`/`tasks`/`task_assignments`
 * missing `academic_session_id`, and `academic_sessions.id` missing
 * AUTO_INCREMENT — this migration is the systematic follow-up instead of
 * discovering the rest one bug report at a time).
 *
 * The full diagnostic found 152 gaps; only the ones an actual model in
 * this codebase writes to are fixed here — verified via grep against
 * `app/`, not assumed:
 * - `periodontal_charts` (~135 columns) — `App\Models\PeriodontalChart`'s
 *   own `$fillable` includes every one of them; this table was completely
 *   unusable on production before this migration.
 * - `user_activity_log` (10 columns) — `App\Services\ActivityLogger`
 *   writes all of them on every logged action (used via
 *   `App\Traits\LogsActivity` across the admin area).
 * - `complete_denture_records.last_tooth_extracted_teeth` — in
 *   `App\Models\CompleteDentureRecord`'s `$fillable`.
 *
 * Deliberately NOT fixed (confirmed via grep — nothing in `app/`
 * references them, so they're inert legacy artifacts, not bugs):
 * - `app_settings`, `endodontics_images`, `mikrotik_settings` tables.
 * - `clinic_settings.mikrotik_*`/`jwt_secret_key` — explicitly excluded
 *   from this rebuild per the project's standing "no MikroTik backup"
 *   requirement (see `ClinicSetting.php`'s own doc comment).
 * - `doctor_tasks.academic_session_id` — the `doctor_tasks` table itself
 *   is referenced nowhere outside `ImportLegacyData.php`'s doc comment.
 * - `patients_simple.gender` — superseded by the `sex` enum column,
 *   nothing in `app/` reads or writes `gender`.
 */
return new class extends Migration
{
    public function up(): void
    {
        $this->addColumns('periodontal_charts', [
            'student_name' => "varchar(255) DEFAULT NULL",
            'student_group' => "varchar(100) DEFAULT NULL",
            'case_start_date' => "date DEFAULT NULL",
            'mentor_name' => "varchar(255) DEFAULT NULL",
            'patient_name' => "varchar(255) DEFAULT NULL",
            'patient_first_name' => "varchar(255) DEFAULT NULL",
            'patient_middle_name' => "varchar(255) DEFAULT NULL",
            'patient_surname' => "varchar(255) DEFAULT NULL",
            'patient_dob' => "date DEFAULT NULL",
            'patient_marital_status' => "varchar(50) DEFAULT NULL",
            'history_present_illness' => "text DEFAULT NULL",
            'med_general_health' => "text DEFAULT NULL",
            'med_hospitalization' => "varchar(10) DEFAULT NULL",
            'med_hospitalization_reason' => "text DEFAULT NULL",
            'med_medication' => "text DEFAULT NULL",
            'med_others_disease' => "varchar(10) DEFAULT 'no'",
            'med_osteoporosis' => "varchar(10) DEFAULT 'no'",
            'med_malignancies' => "varchar(10) DEFAULT 'no'",
            'med_git' => "varchar(10) DEFAULT 'no'",
            'med_respiratory' => "varchar(10) DEFAULT 'no'",
            'med_asthma' => "varchar(10) DEFAULT 'no'",
            'med_epilepsy' => "varchar(10) DEFAULT 'no'",
            'med_urinary' => "varchar(10) DEFAULT 'no'",
            'med_skin_dis' => "varchar(10) DEFAULT 'no'",
            'med_cva' => "varchar(10) DEFAULT 'no'",
            'med_hiv' => "varchar(10) DEFAULT 'no'",
            'med_diabetes' => "varchar(10) DEFAULT 'no'",
            'med_hepatitis' => "varchar(10) DEFAULT 'no'",
            'med_blood_pressure' => "varchar(10) DEFAULT 'no'",
            'med_blood_dis' => "varchar(10) DEFAULT 'no'",
            'med_heart_surgery' => "varchar(10) DEFAULT 'no'",
            'med_disease_notes' => "text DEFAULT NULL",
            'med_allergy_others' => "varchar(10) DEFAULT 'no'",
            'med_allergy_food' => "varchar(10) DEFAULT 'no'",
            'med_allergy_antibiotics' => "varchar(10) DEFAULT 'no'",
            'med_allergy_aspirin' => "varchar(10) DEFAULT 'no'",
            'med_allergy_local_anest' => "varchar(10) DEFAULT 'no'",
            'med_allergy_notes' => "text DEFAULT NULL",
            'med_women_pregnancy' => "varchar(10) DEFAULT NULL",
            'med_women_weeks' => "varchar(50) DEFAULT NULL",
            'med_women_pills' => "varchar(10) DEFAULT NULL",
            'med_women_nursing' => "varchar(10) DEFAULT NULL",
            'med_other_conditions' => "text DEFAULT NULL",
            'dental_last_visit_date' => "date DEFAULT NULL",
            'dental_last_visit_reason' => "text DEFAULT NULL",
            'dental_complications' => "text DEFAULT NULL",
            'dental_prev_perio_treatment' => "varchar(10) DEFAULT NULL",
            'dental_prev_perio_when' => "varchar(255) DEFAULT NULL",
            'dental_prev_perio_for' => "varchar(255) DEFAULT NULL",
            'oral_chemical_agent' => "varchar(10) DEFAULT NULL",
            'family_systemic_disease' => "varchar(10) DEFAULT NULL",
            'family_systemic_disease_details' => "text DEFAULT NULL",
            'hist_smoker_type' => "varchar(255) DEFAULT NULL",
            'hist_smoker_frequency' => "varchar(255) DEFAULT NULL",
            'hist_smoker_duration' => "varchar(255) DEFAULT NULL",
            'alcohol_consumption' => "varchar(10) DEFAULT NULL",
            'behavioural_habits' => "text DEFAULT NULL",
            'dietary_habit' => "text DEFAULT NULL",
            'hist_brushing_duration' => "varchar(50) DEFAULT NULL",
            'exam_bpe_ur' => "varchar(10) DEFAULT NULL",
            'exam_bpe_ua' => "varchar(10) DEFAULT NULL",
            'exam_bpe_ul' => "varchar(10) DEFAULT NULL",
            'exam_bpe_lr' => "varchar(10) DEFAULT NULL",
            'exam_bpe_la' => "varchar(10) DEFAULT NULL",
            'exam_bpe_ll' => "varchar(10) DEFAULT NULL",
            'exam_radiograph_periapical' => "tinyint(1) DEFAULT 0",
            'exam_radiograph_bitewing' => "tinyint(1) DEFAULT 0",
            'exam_radiograph_panoramic' => "tinyint(1) DEFAULT 0",
            'exam_radiograph_cbct' => "tinyint(1) DEFAULT 0",
            'exam_other_investigations' => "text DEFAULT NULL",
            'oral_hygiene' => "text DEFAULT NULL",
            'periodontal_condition' => "text DEFAULT NULL",
            'notes' => "text DEFAULT NULL",
            'diagnosis_pattern' => "varchar(255) DEFAULT NULL",
            'diagnosis_stage' => "varchar(50) DEFAULT NULL",
            'diagnosis_grade' => "varchar(50) DEFAULT NULL",
            'diagnosis_status' => "varchar(50) DEFAULT NULL",
            'diagnosis_risk_factors' => "text DEFAULT NULL",
            'img_chief_complaint' => "text DEFAULT NULL",
            'img_medical_history' => "text DEFAULT NULL",
            'img_smoker_yes' => "tinyint(1) DEFAULT 0",
            'img_smoker_no' => "tinyint(1) DEFAULT 0",
            'img_smoker_prev' => "tinyint(1) DEFAULT 0",
            'img_smoker_stopped' => "varchar(255) DEFAULT NULL",
            'img_diabetes_yes' => "tinyint(1) DEFAULT 0",
            'img_diabetes_no' => "tinyint(1) DEFAULT 0",
            'img_diabetes_controlled_yes' => "tinyint(1) DEFAULT 0",
            'img_diabetes_controlled_no' => "tinyint(1) DEFAULT 0",
            'img_diabetes_lab' => "varchar(255) DEFAULT NULL",
            'img_brushing_once' => "tinyint(1) DEFAULT 0",
            'img_brushing_twice' => "tinyint(1) DEFAULT 0",
            'img_brushing_three' => "tinyint(1) DEFAULT 0",
            'img_brushing_manual' => "tinyint(1) DEFAULT 0",
            'img_brushing_powered' => "tinyint(1) DEFAULT 0",
            'img_interproximal_yes' => "tinyint(1) DEFAULT 0",
            'img_interproximal_no' => "tinyint(1) DEFAULT 0",
            'img_interproximal_type' => "varchar(255) DEFAULT NULL",
            'img_fam_hist_yes' => "tinyint(1) DEFAULT 0",
            'img_fam_hist_no' => "tinyint(1) DEFAULT 0",
            'img_fam_hist_details' => "text DEFAULT NULL",
            'img_prev_treatment' => "text DEFAULT NULL",
            'img_tmj_yes' => "tinyint(1) DEFAULT 0",
            'img_tmj_no' => "tinyint(1) DEFAULT 0",
            'img_facial_yes' => "tinyint(1) DEFAULT 0",
            'img_facial_no' => "tinyint(1) DEFAULT 0",
            'img_facial_details' => "text DEFAULT NULL",
            'img_missing_teeth' => "varchar(255) DEFAULT NULL",
            'img_soft_tissue_yes' => "tinyint(1) DEFAULT 0",
            'img_soft_tissue_no' => "tinyint(1) DEFAULT 0",
            'img_soft_tissue_comments' => "text DEFAULT NULL",
            'img_occlusal_yes' => "tinyint(1) DEFAULT 0",
            'img_occlusal_no' => "tinyint(1) DEFAULT 0",
            'img_mobile_yes' => "tinyint(1) DEFAULT 0",
            'img_mobile_no' => "tinyint(1) DEFAULT 0",
            'img_mobile_teeth' => "varchar(255) DEFAULT NULL",
            'img_caries_yes' => "tinyint(1) DEFAULT 0",
            'img_caries_no' => "tinyint(1) DEFAULT 0",
            'img_caries_teeth' => "varchar(255) DEFAULT NULL",
            'women_pregnancy' => "varchar(10) DEFAULT NULL",
            'pregnancy_weeks' => "varchar(50) DEFAULT NULL",
            'women_birth_control' => "varchar(10) DEFAULT NULL",
            'women_nursing' => "varchar(10) DEFAULT NULL",
            'treatment_plan' => "text DEFAULT NULL",
            'treatment_plan_date' => "date DEFAULT NULL",
            'senior_doctor_name' => "varchar(255) DEFAULT NULL",
            'approval_date' => "date DEFAULT NULL",
            'senior_signature' => "longtext DEFAULT NULL",
            'patient_age' => "int(11) DEFAULT NULL",
            'patient_gender' => "varchar(10) DEFAULT NULL",
            'patient_address' => "text DEFAULT NULL",
            'patient_occupation' => "varchar(255) DEFAULT NULL",
        ]);

        $this->addColumns('user_activity_log', [
            'username' => "varchar(255) DEFAULT NULL",
            'user_role' => "varchar(50) DEFAULT NULL",
            'module' => "varchar(100) DEFAULT NULL",
            'description' => "text DEFAULT NULL",
            'record_id' => "int(11) DEFAULT NULL",
            'data' => "text DEFAULT NULL",
            'request_method' => "varchar(10) DEFAULT NULL",
            'request_url' => "varchar(500) DEFAULT NULL",
            'deleted_at' => "datetime DEFAULT NULL",
            'delete_after' => "datetime DEFAULT NULL",
        ]);

        $this->addColumns('complete_denture_records', [
            'last_tooth_extracted_teeth' => "varchar(255) DEFAULT NULL",
        ]);
    }

    public function down(): void
    {
        // Deliberately no-op: dropping ~145 live-data columns on a
        // production rollback is far more dangerous than leaving them in
        // place. Re-run `php artisan schema:diagnose` if this needs
        // auditing later.
    }

    /** @param array<string, string> $columns column name => raw SQL type/default clause */
    private function addColumns(string $table, array $columns): void
    {
        foreach ($columns as $name => $definition) {
            if (! Schema::hasColumn($table, $name)) {
                DB::statement("ALTER TABLE `{$table}` ADD COLUMN `{$name}` {$definition}");
            }
        }
    }
};
