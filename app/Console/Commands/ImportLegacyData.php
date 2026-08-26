<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Storage;

/**
 * One-time import of the real production data from the original app's
 * `clinic_system2` database into this app's schema.
 *
 * Both databases live on the same MySQL server (confirmed: the app's
 * default `mysql` connection can query `clinic_system2.*` directly), so this
 * reads via `DB::table('clinic_system2.<table>')` and writes to the local
 * tables through the same connection — no second connection config needed.
 *
 * **Why this isn't a straight table copy.** Column sets are structurally
 * identical between the two schemas for nearly every table (verified table
 * by table before writing this), but the *row ids* are not — this Laravel
 * app seeded `departments` and `case_sheet_types` independently while it was
 * being built, so e.g. source department id 6 ("operative") is id 16 here.
 * Copying foreign keys verbatim would silently point every imported doctor,
 * task and case sheet at the wrong department/type. Every FK column is
 * remapped through an id map built by matching on a natural key (name /
 * type_code) between the two databases before any row is inserted.
 *
 * **What's deliberately NOT imported, and why:**
 * - `mikrotik_settings` and `clinic_settings.mikrotik_*`/`jwt_secret_key` —
 *   the MikroTik backup feature was explicitly excluded from this rebuild by
 *   request; importing router credentials for a feature that doesn't exist
 *   here serves no purpose and just exposes a real secret.
 * - The source `admin` user — collides with this app's own live `admin`
 *   account (same username, different password). Importing it would either
 *   error on the unique constraint or risk clobbering the real login.
 * - `roles`, `permissions`, `role_permissions`, `department_permissions`,
 *   `role_stage_department_permissions`, `user_stage_department_permissions`,
 *   `department_role_activity_log`, `department_role_assignments` —
 *   confirmed orphaned by `App\Services\PermissionManager`'s own docblock:
 *   nothing in real access control reads them (`user_permissions` is the
 *   live table). Importing dead rows would misrepresent them as active.
 * - `doctor_tasks`, `task_assignments`, `task_progress`,
 *   `doctor_task_progress` — confirmed dead legacy tables (see README "The
 *   task system — which tables are actually used").
 * - `register_days`/`register_day_service`/`register_day_service_map`/
 *   `register_services` — back a booking feature never built in this app;
 *   importing the catalog with no screen to show it would be inert data.
 * - `appointments`, `payments`, `patients_admin`, `surgery_images`,
 *   `surgery_follow_ups`, `tooth_conditions`, `treatment_materials` — zero
 *   rows in the source, nothing to move.
 * - `clinic_settings.clinic_logo` / `university_logo` / `base_url` /
 *   `enable_notifications` / `enable_sms` / `enable_email` / `mail_*` /
 *   `theme` — the running app already has these configured for real (Gmail
 *   SMTP, a chosen theme); blindly overwriting with the source's stale
 *   values would silently undo that configuration. Only descriptive
 *   identity fields (name, address, phone, working hours…) are merged in.
 *   Logo image files are copied separately, by filename, once verified to
 *   exist on disk (see importClinicSettings()).
 *
 * Idempotency: not designed to be re-run. It's a one-time migration for a
 * specific handoff; running it twice would duplicate every row. Guarded
 * with a confirmation prompt for that reason.
 */
class ImportLegacyData extends Command
{
    protected $signature = 'app:import-legacy-data {--force : Skip the confirmation prompt}';

    protected $description = 'Import doctors, groups, tasks, case sheets and related data from the legacy clinic_system2 database';

    private const SOURCE = 'clinic_system2';

    public function handle(): int
    {
        if (! $this->option('force') && ! $this->confirm(
            'This copies real data from '.self::SOURCE.' into this database and is not '
            .'meant to be re-run. Continue?'
        )) {
            return self::FAILURE;
        }

        $summary = [];

        DB::transaction(function () use (&$summary) {
            $deptMap = $this->mapByColumn('departments', 'name');
            $eduMap = $this->mapByColumn('education_types', 'name');
            $stageMap = $this->mapByColumn('stages', 'name');
            $csTypeMap = $this->importCaseSheetTypes($summary);
            $sessionMap = $this->importAcademicSessions($summary);

            $doctorMap = $this->importDoctors($eduMap, $stageMap, $summary);
            $groupMap = $this->importGroups($stageMap, $sessionMap, $summary);
            $this->importGroupSlots($groupMap, $summary);
            $this->importDoctorGroupMembers($doctorMap, $groupMap, $summary);
            $taskMap = $this->importTasks($deptMap, $csTypeMap, $stageMap, $sessionMap, $summary);
            $tiMap = $this->importTaskInstances($taskMap, $doctorMap, $summary);

            $this->importPatients($summary);
            $this->importPatientsSimple($summary);

            $dentalChartMap = $this->importCaseSheetTable('dental_charts', $doctorMap, $tiMap, $summary);
            $surgeryMap = $this->importCaseSheetTable('surgeries', $doctorMap, $tiMap, $summary);
            $this->importCaseSheetTable('periodontal_charts', $doctorMap, $tiMap, $summary);
            $this->importCaseSheetTable('prosthodontics_records', $doctorMap, $tiMap, $summary);
            $this->importCaseSheetTable('complete_denture_records', $doctorMap, $tiMap, $summary);
            $this->importCaseSheetTable('orthodontics_records', $doctorMap, $tiMap, $summary);
            $this->importCaseSheetTable('prevention_records', $doctorMap, $tiMap, $summary);
            $this->importCaseSheetTable('oral_medicine_charts', $doctorMap, $tiMap, $summary);

            $this->importSurgeryMedications($surgeryMap, $summary);
            $this->importDentalChartSatellites($dentalChartMap, $summary);

            $userMap = $this->importUsers($summary);
            $this->importUserGrants($userMap, $deptMap, $stageMap, $eduMap, $summary);
            $this->importActivityLog($userMap, $doctorMap, $summary);

            $this->importClinicSettings($summary);
        });

        $this->newLine();
        $this->table(['Table', 'Rows imported'], collect($summary)->map(fn ($n, $t) => [$t, $n])->toArray());

        return self::SUCCESS;
    }

    /**
     * The source database was written under a permissive `sql_mode` that
     * allowed MySQL's old `'0000-00-00'` placeholder for "no date entered" —
     * common in older PHP apps, before NULL became the norm. This app's
     * connection runs strict mode, which rejects that literal outright
     * (confirmed: the dry run failed on `dental_charts.treatment_plan_date`
     * with exactly this value). Applied to every dynamically-copied row
     * rather than special-cased per column, since the same placeholder can
     * appear in any user-entered date field across the case-sheet tables.
     */
    private function sanitizeZeroDates(array $data): array
    {
        foreach ($data as $key => $value) {
            if (is_string($value) && str_starts_with($value, '0000-00-00')) {
                $data[$key] = null;
            }
        }

        return $data;
    }

    /**
     * Builds a source-id → destination-id map by matching rows on a natural
     * key that exists unchanged in both databases. Used for the reference
     * tables that already exist in this app under different auto-increment
     * ids (departments, case_sheet_types) as well as the ones confirmed
     * identical (education_types, stages) — built the same way in both
     * cases rather than trusting "currently identical" to stay true.
     */
    private function mapByColumn(string $table, string $column): array
    {
        $source = DB::table(self::SOURCE.'.'.$table)->pluck('id', $column);
        $dest = DB::table($table)->pluck('id', $column);

        $map = [];
        foreach ($source as $key => $sourceId) {
            if (isset($dest[$key])) {
                $map[$sourceId] = $dest[$key];
            }
        }

        return $map;
    }

    /**
     * case_sheet_types: 9 of 11 source rows already exist here under
     * different ids (matched by type_code); 'other' and 'pediatric' don't
     * exist at all — this app never built screens for them (pediatric.php
     * in the original is a 311-line stub with no table behind it; see
     * README). Creating the catalog rows is still correct: they're harmless
     * reference data, and CaseSheetController::open() already has a
     * documented fallback to the operative sheet for exactly this case, so
     * a task pointing at one of them doesn't break anything.
     */
    private function importCaseSheetTypes(array &$summary): array
    {
        $map = $this->mapByColumn('case_sheet_types', 'type_code');
        $created = 0;

        foreach (DB::table(self::SOURCE.'.case_sheet_types')->get() as $row) {
            if (isset($map[$row->id])) {
                continue;
            }

            $newId = DB::table('case_sheet_types')->insertGetId([
                'type_code' => $row->type_code,
                'name_ar' => $row->name_ar,
                'name_en' => $row->name_en,
                'icon' => $row->icon,
                'color' => $row->color,
                'page_url' => $row->page_url,
                'description' => $row->description,
                'display_order' => $row->display_order,
                'is_active' => $row->is_active,
            ]);
            $map[$row->id] = $newId;
            $created++;
        }

        $summary['case_sheet_types (new)'] = $created;

        return $map;
    }

    private function importAcademicSessions(array &$summary): array
    {
        $map = [];
        $rows = DB::table(self::SOURCE.'.academic_sessions')->get();

        foreach ($rows as $row) {
            $map[$row->id] = DB::table('academic_sessions')->insertGetId([
                'name' => $row->name,
                'start_date' => $row->start_date,
                'end_date' => $row->end_date,
                'is_active' => $row->is_active,
                'is_current' => $row->is_current,
                'created_at' => $row->created_at,
            ]);
        }

        $summary['academic_sessions'] = $rows->count();

        return $map;
    }

    /**
     * Doctors carry no academic_session_id in the source (that column is
     * new here — see the 2026_08_19_120000 migration), so imported doctors
     * come in session-less, the same "visible under every session" state
     * new doctors get by default elsewhere in this app.
     *
     * profile_image is dropped for every doctor except the one whose photo
     * file actually exists on disk in the source app's uploads/ folder —
     * carrying over a path to a file that was never copied here would be a
     * broken image, worse than none (the same reasoning ClinicSetting::
     * logoUrl() already applies via Storage::exists()).
     */
    private function importDoctors(array $eduMap, array $stageMap, array &$summary): array
    {
        $map = [];
        $rows = DB::table(self::SOURCE.'.doctors')->get();
        $uploadsDir = base_path('..'.DIRECTORY_SEPARATOR.'dental_clinics2'.DIRECTORY_SEPARATOR.'uploads');

        foreach ($rows as $row) {
            $profileImage = null;
            if ($row->profile_image) {
                $sourcePath = $uploadsDir.DIRECTORY_SEPARATOR.$row->profile_image;
                if (File::exists($sourcePath)) {
                    $stored = 'doctors/'.basename($row->profile_image);
                    Storage::disk('public')->put($stored, File::get($sourcePath));
                    $profileImage = $stored;
                }
            }

            $map[$row->id] = DB::table('doctors')->insertGetId([
                'name' => $row->name,
                'username' => $row->username,
                'password' => $row->password,
                'phone' => $row->phone,
                'education_type_id' => $eduMap[$row->education_type_id] ?? $row->education_type_id,
                'stage_id' => $stageMap[$row->stage_id] ?? $row->stage_id,
                'academic_session_id' => null,
                'profile_image' => $profileImage,
                'email' => $row->email,
                'created_at' => $row->created_at,
            ]);
        }

        $summary['doctors'] = $rows->count();

        return $map;
    }

    private function importGroups(array $stageMap, array $sessionMap, array &$summary): array
    {
        $map = [];
        $rows = DB::table(self::SOURCE.'.groups')->get();

        foreach ($rows as $row) {
            $map[$row->id] = DB::table('groups')->insertGetId([
                'name' => $row->name,
                'stage_id' => $stageMap[$row->stage_id] ?? $row->stage_id,
                'academic_session_id' => $row->academic_session_id ? ($sessionMap[$row->academic_session_id] ?? null) : null,
            ]);
        }

        $summary['groups'] = $rows->count();

        return $map;
    }

    private function importGroupSlots(array $groupMap, array &$summary): void
    {
        $rows = DB::table(self::SOURCE.'.group_slots')->get();

        foreach ($rows as $row) {
            if (! isset($groupMap[$row->group_id])) {
                continue;
            }

            DB::table('group_slots')->insert([
                'group_id' => $groupMap[$row->group_id],
                'day' => $row->day,
                'start_time' => $row->start_time,
                'end_time' => $row->end_time,
            ]);
        }

        $summary['group_slots'] = $rows->count();
    }

    /**
     * academic_session_id doesn't exist in the source pivot (added by the
     * 2026_08_19_120000 migration). Backfilled from the membership's own
     * group, matching the convention `GroupController::addDoctors` already
     * uses when a caller doesn't specify one — a membership belongs to
     * whichever session its group belongs to.
     */
    private function importDoctorGroupMembers(array $doctorMap, array $groupMap, array &$summary): void
    {
        $groupSessionMap = DB::table('groups')->pluck('academic_session_id', 'id');
        $rows = DB::table(self::SOURCE.'.doctor_group_members')->get();
        $imported = 0;

        foreach ($rows as $row) {
            if (! isset($doctorMap[$row->doctor_id], $groupMap[$row->group_id])) {
                continue;
            }

            $groupId = $groupMap[$row->group_id];

            DB::table('doctor_group_members')->insert([
                'group_id' => $groupId,
                'doctor_id' => $doctorMap[$row->doctor_id],
                'academic_session_id' => $groupSessionMap[$groupId] ?? null,
                'added_at' => $row->added_at,
            ]);
            $imported++;
        }

        $summary['doctor_group_members'] = $imported;
    }

    private function importTasks(array $deptMap, array $csTypeMap, array $stageMap, array $sessionMap, array &$summary): array
    {
        $map = [];
        $rows = DB::table(self::SOURCE.'.tasks')->get();

        foreach ($rows as $row) {
            $map[$row->id] = DB::table('tasks')->insertGetId([
                'department_id' => $deptMap[$row->department_id] ?? $row->department_id,
                'case_sheet_type_id' => $csTypeMap[$row->case_sheet_type_id] ?? $row->case_sheet_type_id,
                'stage_id' => $stageMap[$row->stage_id] ?? $row->stage_id,
                'academic_session_id' => $row->academic_session_id ? ($sessionMap[$row->academic_session_id] ?? null) : null,
                'title' => $row->title,
                'required_per_doctor' => $row->required_per_doctor,
                'done' => $row->done,
                'required_count' => $row->required_count,
                'notes' => $row->notes,
                'grade' => $row->grade,
            ]);
        }

        $summary['tasks'] = $rows->count();

        return $map;
    }

    private function importTaskInstances(array $taskMap, array $doctorMap, array &$summary): array
    {
        $map = [];
        $rows = DB::table(self::SOURCE.'.task_instances')->get();
        $imported = 0;

        foreach ($rows as $row) {
            if (! isset($taskMap[$row->task_id])) {
                continue;
            }

            $map[$row->id] = DB::table('task_instances')->insertGetId([
                'task_id' => $taskMap[$row->task_id],
                'doctor_id' => $row->doctor_id ? ($doctorMap[$row->doctor_id] ?? null) : null,
                'status' => $row->status,
                'assigned_date' => $row->assigned_date,
                'completion_date' => $row->completion_date,
                'notes' => $row->notes,
                'grade' => $row->grade,
                'assigned_by' => $row->assigned_by,
                'created_at' => $row->created_at,
            ]);
            $imported++;
        }

        $summary['task_instances'] = $imported;

        return $map;
    }

    /**
     * The one row in `patients` — this is the table App\Models\Patient
     * actually reads (verified: `patients_admin`, the table the original's
     * admin/patients_list.php queries, is empty in the source and belongs
     * to the parallel intake flow already flagged in README as awaiting a
     * product decision, so there's nothing there to import either way).
     */
    private function importPatients(array &$summary): void
    {
        $rows = DB::table(self::SOURCE.'.patients')->get();

        foreach ($rows as $row) {
            DB::table('patients')->insert(
                $this->sanitizeZeroDates(collect((array) $row)->except('id')->all())
            );
        }

        $summary['patients'] = $rows->count();
    }

    /**
     * `patients_simple` is real data (36 rows) but nothing in this app's
     * built features currently reads it — the case-sheet `patient_id`
     * columns are loose free-text fields in the original (confirmed: values
     * like "hdfhd", "fghfgh" alongside real ids — never an enforced FK), not
     * a relation to this table. Imported anyway rather than dropped: it's
     * real historical data and copying it costs nothing, in case a future
     * feature wants it. Own fresh ids — nothing else references it by id.
     */
    private function importPatientsSimple(array &$summary): void
    {
        $rows = DB::table(self::SOURCE.'.patients_simple')->get();

        foreach ($rows as $row) {
            DB::table('patients_simple')->insert(
                $this->sanitizeZeroDates(collect((array) $row)->except('id')->all())
            );
        }

        $summary['patients_simple'] = $rows->count();
    }

    /**
     * Shared by every case-sheet table that follows the doctor_id +
     * task_instances_id + free-text patient_id shape (confirmed identical
     * column sets table-by-table before writing this). `patient_id` itself
     * is copied verbatim, whatever type it is (varchar or int) — remapping
     * it would mean guessing which patient a loose, often-nonsense string
     * refers to, which is exactly the kind of invention this project avoids.
     *
     * Returns the source-id → destination-id map so satellite tables
     * (surgery_medications, tooth_treatments, treatment_plans) can remap
     * their own foreign keys into these records.
     */
    private function importCaseSheetTable(string $table, array $doctorMap, array $tiMap, array &$summary): array
    {
        $map = [];
        $rows = DB::table(self::SOURCE.'.'.$table)->get();

        foreach ($rows as $row) {
            $data = $this->sanitizeZeroDates(collect((array) $row)->except('id')->all());

            // dental_charts.chart_type is `enum('primary','permanent') NOT
            // NULL DEFAULT 'permanent'`; one source row has it as an empty
            // string, which isn't a valid member and strict mode rejects
            // outright ("Data truncated for column"). Falls back to the
            // column's own stated default rather than guessing between the
            // two real choices — confirmed via a full scan that this is the
            // only enum column, across all eight case-sheet tables, with a
            // source value outside its allowed set.
            if (($data['chart_type'] ?? null) === '') {
                $data['chart_type'] = 'permanent';
            }

            if (array_key_exists('doctor_id', $data) && $data['doctor_id']) {
                $data['doctor_id'] = $doctorMap[$data['doctor_id']] ?? null;
            }
            if (array_key_exists('task_instances_id', $data) && $data['task_instances_id']) {
                $data['task_instances_id'] = $tiMap[$data['task_instances_id']] ?? null;
            }

            $map[$row->id] = DB::table($table)->insertGetId($data);
        }

        $summary[$table] = $rows->count();

        return $map;
    }

    private function importSurgeryMedications(array $surgeryMap, array &$summary): void
    {
        $rows = DB::table(self::SOURCE.'.surgery_medications')->get();
        $imported = 0;

        foreach ($rows as $row) {
            if (! isset($surgeryMap[$row->surgery_id])) {
                continue;
            }

            DB::table('surgery_medications')->insert([
                'surgery_id' => $surgeryMap[$row->surgery_id],
                'medication_name' => $row->medication_name,
                'dosage' => $row->dosage,
                'frequency' => $row->frequency,
                'duration' => $row->duration,
                'notes' => $row->notes,
                'created_at' => $row->created_at,
            ]);
            $imported++;
        }

        $summary['surgery_medications'] = $imported;
    }

    /**
     * tooth_treatments, endodontics_images and treatment_plans all key off
     * a dental_chart id (treatment_plans.chart_id, confirmed against
     * App\Models\TreatmentPlan::chart() and the original's
     * save_treatment_plan.php — the generic column name doesn't say so).
     * tooth_conditions, surgery_images, surgery_follow_ups and
     * treatment_materials are 0 rows in the source; nothing to import.
     */
    private function importDentalChartSatellites(array $dentalChartMap, array &$summary): void
    {
        $treatments = DB::table(self::SOURCE.'.tooth_treatments')->get();
        $imported = 0;
        foreach ($treatments as $row) {
            if (! isset($dentalChartMap[$row->dental_chart_id])) {
                continue;
            }
            DB::table('tooth_treatments')->insert($this->sanitizeZeroDates([
                'dental_chart_id' => $dentalChartMap[$row->dental_chart_id],
                'tooth_number' => $row->tooth_number,
                'tooth_position' => $row->tooth_position,
                // enum('root_canal',...,'other') NOT NULL, no default; 30 of
                // 49 source rows are an empty string (not a valid member —
                // confirmed via a full enum audit across every imported
                // table). Falls back to the enum's own 'other' member rather
                // than inventing which real treatment type was meant.
                'treatment_type' => $row->treatment_type !== '' ? $row->treatment_type : 'other',
                'treatment_status' => $row->treatment_status,
                'treatment_notes' => $row->treatment_notes,
                'treatment_date' => $row->treatment_date,
                'created_at' => $row->created_at,
                'updated_at' => $row->updated_at,
            ]));
            $imported++;
        }
        $summary['tooth_treatments'] = $imported;

        $endo = DB::table(self::SOURCE.'.endodontics_images')->get();
        $endoImported = 0;
        foreach ($endo as $row) {
            if (! isset($dentalChartMap[$row->dental_chart_id])) {
                continue;
            }
            DB::table('endodontics_images')->insert([
                'dental_chart_id' => $dentalChartMap[$row->dental_chart_id],
                'visit_type' => $row->visit_type,
                'image_data' => $row->image_data,
                'created_at' => $row->created_at,
            ]);
            $endoImported++;
        }
        $summary['endodontics_images'] = $endoImported;

        $plans = DB::table(self::SOURCE.'.treatment_plans')->get();
        $plansImported = 0;
        foreach ($plans as $row) {
            if (! isset($dentalChartMap[$row->chart_id])) {
                continue;
            }
            DB::table('treatment_plans')->insert($this->sanitizeZeroDates([
                'chart_id' => $dentalChartMap[$row->chart_id],
                'plan_date' => $row->plan_date,
                'plan_notes' => $row->plan_notes,
                'mark' => $row->mark,
                'doctor_name' => $row->doctor_name,
                'signature' => $row->signature,
                'created_at' => $row->created_at,
                'updated_at' => $row->updated_at,
            ]));
            $plansImported++;
        }
        $summary['treatment_plans'] = $plansImported;
    }

    /**
     * Only 3 of the source's 4 staff users are imported. The 4th is
     * `admin` — it collides with this app's own live `admin` account
     * (confirmed: same username, different password hash). Importing it
     * would violate the unique constraint at best and risk overwriting the
     * real login at worst, so it's skipped entirely. The skipped row's id
     * is remembered so importActivityLog() can still attribute historical
     * log entries written by "admin" to this app's own admin account,
     * without ever creating a second one.
     */
    private function importUsers(array &$summary): array
    {
        $map = [];
        $imported = 0;

        foreach (DB::table(self::SOURCE.'.users')->get() as $row) {
            if ($row->username === 'admin') {
                // See docblock — deliberately not imported. Historical log
                // rows for this id are re-pointed at the real admin account.
                $map[$row->id] = DB::table('users')->where('role', 'super_admin')->value('id');

                continue;
            }

            $map[$row->id] = DB::table('users')->insertGetId([
                'full_name' => $row->full_name,
                'username' => $row->username,
                'email' => $row->email,
                'phone' => $row->phone,
                'password' => $row->password,
                'role' => $row->role,
                'status' => $row->status,
                'notes' => $row->notes,
                'last_login' => $row->last_login,
                'created_at' => $row->created_at,
                'updated_at' => $row->updated_at ?? $row->created_at,
                'profile_image' => null,
            ]);
            $imported++;
        }

        $summary['users (admin skipped, see README)'] = $imported;

        return $map;
    }

    private function importUserGrants(array $userMap, array $deptMap, array $stageMap, array $eduMap, array &$summary): void
    {
        $permImported = 0;
        foreach (DB::table(self::SOURCE.'.user_permissions')->get() as $row) {
            if (! isset($userMap[$row->user_id]) || $row->user_id === null) {
                continue;
            }
            // The skipped source admin's grants are meaningless here —
            // super_admin bypasses every permission check regardless
            // (PermissionManager::isSuperAdmin()).
            $sourceUser = DB::table(self::SOURCE.'.users')->find($row->user_id);
            if ($sourceUser && $sourceUser->username === 'admin') {
                continue;
            }

            DB::table('user_permissions')->insert([
                'user_id' => $userMap[$row->user_id],
                'module' => $row->module,
                'permission' => $row->permission,
                'granted' => $row->granted,
                'created_at' => $row->created_at,
                'updated_at' => $row->updated_at,
            ]);
            $permImported++;
        }
        $summary['user_permissions'] = $permImported;

        $scopeImported = 0;
        foreach (DB::table(self::SOURCE.'.user_allowed_departments')->get() as $row) {
            if (! isset($userMap[$row->user_id])) {
                continue;
            }
            DB::table('user_allowed_departments')->insert([
                'user_id' => $userMap[$row->user_id],
                'department_id' => $deptMap[$row->department_id] ?? $row->department_id,
            ]);
            $scopeImported++;
        }
        foreach (DB::table(self::SOURCE.'.user_allowed_stages')->get() as $row) {
            if (! isset($userMap[$row->user_id])) {
                continue;
            }
            DB::table('user_allowed_stages')->insert([
                'user_id' => $userMap[$row->user_id],
                'stage_id' => $stageMap[$row->stage_id] ?? $row->stage_id,
            ]);
            $scopeImported++;
        }
        foreach (DB::table(self::SOURCE.'.user_allowed_education_types')->get() as $row) {
            if (! isset($userMap[$row->user_id])) {
                continue;
            }
            DB::table('user_allowed_education_types')->insert([
                'user_id' => $userMap[$row->user_id],
                'education_type_id' => $eduMap[$row->education_type_id] ?? $row->education_type_id,
            ]);
            $scopeImported++;
        }
        $summary['user_allowed_* (scope grants)'] = $scopeImported;
    }

    /**
     * `user_id` is overloaded in both schemas, not a clean FK to `users`
     * alone: `App\Services\ActivityLogger::actor()` resolves the acting
     * principal from web/doctor/sanctum guards and, for a doctor, writes
     * the *doctor's* id into this same column with `user_role='doctor'` —
     * confirmed by reading that method, and it faithfully mirrors what the
     * source schema already does (13 rows found with `user_role='doctor'`
     * and a `user_id` that only resolves against `doctors`, not `users` —
     * e.g. id 705, which is not a user but is doctor "Zaman Mohammed").
     * So each row is remapped through $doctorMap when `user_role` says
     * 'doctor', and through $userMap otherwise.
     *
     * user_id is NOT NULL with no formal FK (audit logs commonly survive
     * row deletion), so every resolvable row is kept — rows originally
     * attributed to the source `admin` are re-pointed at this app's real
     * admin account via the map built in importUsers(), preserving the
     * full history under the account that's actually the same
     * administrator rather than being dropped.
     */
    private function importActivityLog(array $userMap, array $doctorMap, array &$summary): void
    {
        $rows = DB::table(self::SOURCE.'.user_activity_log')->get();
        $imported = 0;

        foreach ($rows as $row) {
            $newUserId = $row->user_role === 'doctor'
                ? ($doctorMap[$row->user_id] ?? null)
                : ($userMap[$row->user_id] ?? null);

            if ($newUserId === null) {
                continue;
            }

            DB::table('user_activity_log')->insert([
                'user_id' => $newUserId,
                'username' => $row->username,
                'user_role' => $row->user_role,
                'action' => $row->action,
                'module' => $row->module,
                'description' => $row->description,
                'record_id' => $row->record_id,
                'data' => $row->data,
                'details' => $row->details,
                'ip_address' => $row->ip_address,
                'request_method' => $row->request_method,
                'request_url' => $row->request_url,
                'user_agent' => $row->user_agent,
                'created_at' => $row->created_at,
                'deleted_at' => $row->deleted_at,
                'delete_after' => $row->delete_after,
            ]);
            $imported++;
        }

        $summary['user_activity_log'] = $imported;
    }

    /**
     * Only descriptive identity fields — see the class docblock for why
     * mail/theme/notification settings and the mikrotik/jwt columns are
     * excluded. Logo files are copied by filename from the source app's
     * uploads/ folder into storage/app/public/clinic/ (the path
     * ClinicSettingController::update() itself stores new uploads under),
     * and the column only gets the new path once the copy actually
     * succeeds — otherwise it's left as whatever this app already has,
     * rather than pointing at a file that was never copied.
     */
    private function importClinicSettings(array &$summary): void
    {
        $source = DB::table(self::SOURCE.'.clinic_settings')->first();
        if (! $source) {
            $summary['clinic_settings'] = 0;

            return;
        }

        $update = array_filter([
            'clinic_name' => $source->clinic_name,
            'clinic_description' => $source->clinic_description,
            'clinic_address' => $source->clinic_address,
            'clinic_phone' => $source->clinic_phone,
            'clinic_email' => $source->clinic_email,
            'clinic_website' => $source->clinic_website,
            'clinic_working_hours' => $source->clinic_working_hours,
            'clinic_currency' => $source->clinic_currency,
            'university_name' => $source->university_name,
            'college_name' => $source->college_name,
        ], fn ($v) => filled($v));

        $uploadsDir = base_path('..'.DIRECTORY_SEPARATOR.'dental_clinics2'.DIRECTORY_SEPARATOR.'uploads');

        foreach (['clinic_logo' => 'clinic_logo', 'university_logo' => 'university_logo'] as $sourceCol => $destCol) {
            $filename = $source->{$sourceCol};
            if (! $filename) {
                continue;
            }
            $sourcePath = $uploadsDir.DIRECTORY_SEPARATOR.$filename;
            if (File::exists($sourcePath)) {
                $stored = 'clinic/'.basename($filename);
                Storage::disk('public')->put($stored, File::get($sourcePath));
                $update[$destCol] = $stored;
            }
        }

        DB::table('clinic_settings')->where('id', 1)->update($update);
        $summary['clinic_settings'] = 1;
    }
}
