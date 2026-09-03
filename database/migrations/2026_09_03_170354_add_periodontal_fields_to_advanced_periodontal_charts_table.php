<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    /**
     * Merges every ordinary (non-table, non-odontogram) section from
     * `PeriodontalChartForm` into `AdvancedPeriodontalChartForm` (2026-09-03,
     * by request — "اضافة الحقول من periodontal chart الى ادفانسد ماعدا
     * الجدول والمخططات السنية"). Patient Information stays untouched (this
     * resource's own first/last-name-split + DOB + exam-type design is
     * deliberate, not a gap to fill), and neither the BOP/PPD/CAL
     * `chartGroups()` table nor any tooth/odontogram widget is touched —
     * this resource's own 32-tooth `chart_data` grid (AdvancedPerioChart.vue)
     * is exactly what "الجدول والمخططات السنية" excludes.
     *
     * Column types copied verbatim from `periodontal_charts` in
     * database/schema_import.sql so a value written by one form reads
     * identically via the other's column if the two are ever compared.
     */
    public function up(): void
    {
        Schema::table('advanced_periodontal_charts', function (Blueprint $table) {
            // Patient Information — the one field added to this section
            // rather than left alone: nothing in Advanced's own Patient
            // Information previously captured gender, but the merged-in
            // "Women Only" section below only makes sense (and only shows
            // — SectionedForm.vue's `isFemale` reads `patient_gender`/`sex`)
            // once a gender field exists to gate it. Not the full
            // Periodontal Patient Info block (phone/age/address/occupation/
            // marital status stay out, per this migration's own class doc).
            $table->string('patient_gender', 10)->nullable();

            // Women Only
            $table->string('women_pregnancy', 10)->nullable();
            $table->string('pregnancy_weeks', 50)->nullable();
            $table->string('women_birth_control', 10)->nullable();
            $table->string('women_nursing', 10)->nullable();

            // Chief Complaint & Medical History
            $table->text('img_chief_complaint')->nullable();
            $table->text('img_medical_history')->nullable();

            // History
            $table->boolean('img_smoker_yes')->default(false);
            $table->boolean('img_smoker_no')->default(false);
            $table->boolean('img_smoker_prev')->default(false);
            $table->string('img_smoker_stopped')->nullable();
            $table->boolean('img_diabetes_yes')->default(false);
            $table->boolean('img_diabetes_no')->default(false);
            $table->boolean('img_diabetes_controlled_yes')->default(false);
            $table->boolean('img_diabetes_controlled_no')->default(false);
            $table->string('img_diabetes_lab')->nullable();
            $table->boolean('img_brushing_once')->default(false);
            $table->boolean('img_brushing_twice')->default(false);
            $table->boolean('img_brushing_three')->default(false);
            $table->boolean('img_brushing_manual')->default(false);
            $table->boolean('img_brushing_powered')->default(false);
            $table->boolean('img_interproximal_yes')->default(false);
            $table->boolean('img_interproximal_no')->default(false);
            $table->string('img_interproximal_type')->nullable();
            $table->boolean('img_fam_hist_yes')->default(false);
            $table->boolean('img_fam_hist_no')->default(false);
            $table->text('img_fam_hist_details')->nullable();
            $table->text('img_prev_treatment')->nullable();

            // Examination
            $table->boolean('img_tmj_yes')->default(false);
            $table->boolean('img_tmj_no')->default(false);
            $table->boolean('img_facial_yes')->default(false);
            $table->boolean('img_facial_no')->default(false);
            $table->text('img_facial_details')->nullable();
            $table->string('img_missing_teeth')->nullable();
            $table->boolean('img_soft_tissue_yes')->default(false);
            $table->boolean('img_soft_tissue_no')->default(false);
            $table->text('img_soft_tissue_comments')->nullable();
            $table->boolean('img_occlusal_yes')->default(false);
            $table->boolean('img_occlusal_no')->default(false);
            $table->boolean('img_mobile_yes')->default(false);
            $table->boolean('img_mobile_no')->default(false);
            $table->string('img_mobile_teeth')->nullable();
            $table->boolean('img_caries_yes')->default(false);
            $table->boolean('img_caries_no')->default(false);
            $table->string('img_caries_teeth')->nullable();

            // BPE (Basic Periodontal Examination)
            $table->string('exam_bpe_ur', 10)->nullable();
            $table->string('exam_bpe_ua', 10)->nullable();
            $table->string('exam_bpe_ul', 10)->nullable();
            $table->string('exam_bpe_lr', 10)->nullable();
            $table->string('exam_bpe_la', 10)->nullable();
            $table->string('exam_bpe_ll', 10)->nullable();

            // Radiographs & Investigations
            $table->boolean('exam_radiograph_periapical')->default(false);
            $table->boolean('exam_radiograph_bitewing')->default(false);
            $table->boolean('exam_radiograph_panoramic')->default(false);
            $table->boolean('exam_radiograph_cbct')->default(false);
            $table->text('exam_other_investigations')->nullable();

            // Clinical Examination (`notes` already exists on this table)
            $table->text('oral_hygiene')->nullable();
            $table->text('periodontal_condition')->nullable();

            // Diagnosis
            $table->string('diagnosis_pattern')->nullable();
            $table->string('diagnosis_stage', 50)->nullable();
            $table->string('diagnosis_grade', 50)->nullable();
            $table->string('diagnosis_status', 50)->nullable();
            $table->text('diagnosis_risk_factors')->nullable();

            // Treatment Plan & Approval (`senior_signature` already exists)
            $table->text('treatment_plan')->nullable();
            $table->date('treatment_plan_date')->nullable();
            $table->string('senior_doctor_name')->nullable();
            $table->date('approval_date')->nullable();
            $table->text('clinical_notes')->nullable();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('advanced_periodontal_charts', function (Blueprint $table) {
            $table->dropColumn([
                'patient_gender',
                'women_pregnancy', 'pregnancy_weeks', 'women_birth_control', 'women_nursing',
                'img_chief_complaint', 'img_medical_history',
                'img_smoker_yes', 'img_smoker_no', 'img_smoker_prev', 'img_smoker_stopped',
                'img_diabetes_yes', 'img_diabetes_no', 'img_diabetes_controlled_yes', 'img_diabetes_controlled_no', 'img_diabetes_lab',
                'img_brushing_once', 'img_brushing_twice', 'img_brushing_three', 'img_brushing_manual', 'img_brushing_powered',
                'img_interproximal_yes', 'img_interproximal_no', 'img_interproximal_type',
                'img_fam_hist_yes', 'img_fam_hist_no', 'img_fam_hist_details', 'img_prev_treatment',
                'img_tmj_yes', 'img_tmj_no', 'img_facial_yes', 'img_facial_no', 'img_facial_details',
                'img_missing_teeth', 'img_soft_tissue_yes', 'img_soft_tissue_no', 'img_soft_tissue_comments',
                'img_occlusal_yes', 'img_occlusal_no', 'img_mobile_yes', 'img_mobile_no', 'img_mobile_teeth',
                'img_caries_yes', 'img_caries_no', 'img_caries_teeth',
                'exam_bpe_ur', 'exam_bpe_ua', 'exam_bpe_ul', 'exam_bpe_lr', 'exam_bpe_la', 'exam_bpe_ll',
                'exam_radiograph_periapical', 'exam_radiograph_bitewing', 'exam_radiograph_panoramic', 'exam_radiograph_cbct',
                'exam_other_investigations', 'oral_hygiene', 'periodontal_condition',
                'diagnosis_pattern', 'diagnosis_stage', 'diagnosis_grade', 'diagnosis_status', 'diagnosis_risk_factors',
                'treatment_plan', 'treatment_plan_date', 'senior_doctor_name', 'approval_date', 'clinical_notes',
            ]);
        });
    }
};
