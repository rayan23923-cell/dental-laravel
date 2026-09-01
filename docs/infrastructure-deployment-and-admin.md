# Infrastructure, Admin/Settings, Deployment & Data Migration

This covers the parts of the rebuild that aren't a specific clinical
feature: the web app's module inventory, the JSON API that the Flutter
client is built against, the admin-only screens (clinic settings, backup,
activity log, case-sheet-type management), the PDF/print exports, the real
production data import from the legacy `clinic_system2` database, and the
GitHub-Actions-to-cPanel production deployment — including the schema-drift
bugs that adopting an already-live database surfaced.

## Web app module inventory

Inertia/Vue modules built (each has a controller + Vue pages; most have a
matching `/api/v1` endpoint too, see below):

| Module | Controller | Notes |
|---|---|---|
| Doctors | `DoctorController` | full CRUD, profile-photo upload |
| Doctor import/export | `DoctorImportExportController` | Excel bulk import + export |
| Patients | `PatientController` | CRUD against `patients` — the table `appointments`/`surgeries` actually FK to, not `patients_admin`/`patients_simple` |
| Education Types / Stages / Departments | one controller each | inline create + modal edit, lookup tables |
| Tasks | `TaskController` | task **definitions** (department + case-sheet-type + stage + title + required counts) |
| Task assignment | `TaskInstanceController` | assign a task to a doctor, mark complete + grade, remove |
| Dental Charts | `DentalChartController` | CRUD against `dental_charts`; FDI tooth picker writing the `tooth_data` JSON column |
| Appointments | `AppointmentController` | CRUD + pin/unpin |
| Payments | `PaymentController` | create/list/delete against one appointment at a time |
| Activity Log | `ActivityLogController` | read-only, filterable |
| TV board (public) | closure in `routes/web.php` | no auth, polls the TV-board API client-side every 20s |
| Doctor area (`doctor` guard) | `Doctor\{Dashboard,Profile,TaskInstance}Controller` | doctors' own web UI, separate from the admin/staff side |
| Clinical specialty records (×12) | one controller per table | generic field-driven forms (shared `Specialty/{Index,Form,Show}.vue`), not 12 bespoke screens |
| User Permissions | `UserPermissionController` | module × action grant matrix |
| Department Roles | `DepartmentRoleAssignmentController` | senior/HR per department+stage |
| Academic Sessions | `AcademicSessionController` | CRUD + set-current + per-session stats |
| Groups | `GroupController` | groups + weekly slots + doctor membership |

Deleting an **Education Type** cascades — the schema has `ON DELETE CASCADE`
from `departments.education_type_id` and `doctors.education_type_id`, so
removing one takes its departments and doctors with it. Inherited schema
behavior, not something added here; the delete confirmation says so.

### Which task-related tables are actually live

The schema inherits six task tables: `tasks`, `task_instances`,
`task_assignments`, `task_progress`, `doctor_tasks`, `doctor_task_progress`.
Rather than guess, the original PHP codebase was grepped for real usage:
**`tasks`** + **`task_instances`** are used pervasively (`task_instances.status`
plus `grade` is the real workflow state); **`doctor_tasks`** is used by
exactly one legacy file as an apparent parallel/older mechanism; the other
three had zero `SELECT`/`INSERT`/`UPDATE` hits anywhere. Decision: the Task
module is built against `tasks` + `task_instances` only; the rest are
imported for schema fidelity but have no models/controllers.

`case_sheet_types` real values, pulled from the live `clinic_system2` DB:
`operative`, `partial_denture`, `complete_denture`, `surgery`, `periodontal`,
`prosthodontics`, `orthodontics`, `pediatric`, `prevention`, `oral_medicine`,
`other`.

### Appointments: a real schema/code contradiction

`appointments.doctor_id`'s FK constraint says `REFERENCES users(id)`, but
the legacy `tv_patients.php` joins it against `doctors`. Traced to the real
write path (`admin/ajax/pin_appointments.php`): it populates `doctor_id`
from `users` — so the FK is correct and the legacy join is a **pre-existing
display bug** (silently working only because both tables are auto-increment
int with overlapping ids). This rebuild's `Appointment::doctor()` points at
`User`, deliberately not reproducing the original's bug. One consequence:
`users` has no `education_type_id`/`stage_id`, so the legacy per-education-type
filter on pinned appointments isn't carried over — it couldn't have been
filtering correctly against the right table in the first place.

### TV waiting-room board

Public, read-only `GET /api/v1/tv-board` mirrors `tv_patients.php`: doctors'
scheduled patients (`patients` → `groups` → `group_slots`) plus pinned
same-day appointments. `tv_queue` looks purpose-built for this but a full
codebase grep found **zero references** to it outside SQL dumps — it's a
dead table, no model/routes built against it. `TvBoard.vue` (`/tv`) polls
the endpoint client-side every 20s.

### Activity logging

`user_activity_log` is written via `App\Services\ActivityLogger::log()`,
but instead of the original's explicit `logCreate()` call per controller
action, this rebuild uses a model trait (`App\Traits\LogsActivity`) hooked
into Eloquent's `created`/`updated`/`deleted` events — logging can't be
forgotten. Applied to `Doctor`, `Patient`, `Task`, `TaskInstance`,
`DentalChart`, `Appointment`, `Payment`; deliberately not applied to lookup
tables or the 12 API-only specialty models (signal-to-noise, not a
limitation — adding the trait elsewhere is a one-line change).

The actor is resolved from whichever guard authenticated the request (web
session or Sanctum, `User` or `Doctor`) via `ActivityLogger::currentActor()`.
`user_activity_log.user_id` has **no FK constraint** (confirmed against
`information_schema`) and is overloaded — a `Doctor`'s id and a `User`'s id
can both legally land there; `username`/`user_role` disambiguate, matching
the original schema's own design. Web: `/activity-logs`
(admin/super_admin). API: `GET /api/v1/activity-logs` (staff-only, 403 for
a doctor token).

### File uploads

`storage:link` is live. Two real upload flows: **doctor profile photo**
(`doctors.profile_image`, web + API multipart, max 2MB, `storage/doctors/`,
old file deleted on update) and **surgery images** (`POST
/api/v1/surgery-images`, max 5MB, `storage/surgeries/{id}/`) — the latter
changed the endpoint's contract from a plain `image_path` string field to a
real multipart upload. Other `*_image`/`*_path` fields across the schema
don't have upload handling yet.

### Doctor Excel import/export

`phpoffice/phpspreadsheet` v5, matching the legacy dependency. **Not** a
faithful port: the original's template promised 5 columns (First/Last
Name, Email, Phone, Username) but its importer only ever read columns 0–1
and fabricated every name as `"طبيب {username}"`, silently discarding the
rest — an incomplete implementation, not a competing source of truth, so
this rebuild's importer reads all 5 columns as the template actually
promises. Also fixed: the legacy exporter queried a `d.study_type` column
that doesn't exist on the current `doctors` table (leftover from an older
schema version) — the rebuild's export uses the real current columns.
Both web (`/doctors-template`, `/doctors-export`, `/doctors-import`) and
API routes are wired, the API delegating to the same spreadsheet-building
methods rather than duplicating them.

### QR check-in (task instances)

`endroid/qr-code` v6. Not a port: the legacy app defined **three
incompatible QR payload shapes** across three different files for the same
concept, and the one endpoint that actually processed a scanned code
(`process_qr_result.php`) inserted into a `qr_scan_logs` table that **does
not exist anywhere in the imported schema** — that code path would throw a
SQL error even in the live original today. Every other shape fell through
to a no-op. Replaced with one clean, versioned payload —
`{"type":"task_instance","id":<task_instance_id>}` — with a real working
generate → scan → open loop:

| Method | Path | Notes |
|---|---|---|
| GET | `/api/v1/task-instances/{id}/qr` | PNG QR (`?size=`); 403 on another doctor's instance |
| GET | `/task-instances/{id}/qr` | same, web session auth |
| POST | `/api/v1/task-instances/scan` | `{"payload": "..."}` → resolves and returns the `TaskInstanceResource`; 422 unrecognized, 403 cross-doctor |
| GET | `/api/v1/task-instances/{id}` | plain show endpoint |

No web camera-scanning UI was built — the QR consumer is the mobile client.

### Dental Chart module

Built against `dental_charts` (confirmed as the actively-used table via
`doctor/save_dental_chart.php`) plus child tables `dental_follow_ups`,
`tooth_conditions`, `tooth_treatments` (models/relations only, no
dedicated CRUD yet). `dental_charts.patient_id` is a **varchar holding the
patient's name**, not an FK — a denormalized snapshot, not this app's
"bug." `tooth_data` is a JSON array of `{tooth_number, tooth_position,
condition_type, severity, notes}`, rendered/edited by
`ToothSelector.vue` (32 permanent FDI 11–48 or 20 primary FDI 51–85 teeth
by quadrant). "Pediatric Dentistry" is not a separate table — its legacy
form (`doctor/pediatric.php`) actually submits to the same
`save_dental_chart.php` with `chart_type='primary'`, so it's already fully
covered by this module.

### A route-name collision that broke every web redirect app-wide

`Route::resource()` (web) and `Route::apiResource()` (api) defaulted to the
**same route names** for the same resource (e.g. both produced
`doctors.index`) — Laravel's named-route lookup keeps only the
last-registered match, so every `redirect()->route('doctors.index')` after
a create/update/delete across the *entire* web app (doctors, patients,
tasks, dental charts, appointments, payments, all 12 specialty records) was
silently redirecting the browser to the JSON API response instead of back
to the Inertia page. The DB write itself was fine, which is why it stayed
invisible through eleven modules of testing — nothing had checked a
redirect's `Location:` header until the twelfth. Fixed by wrapping
`routes/api.php` in `Route::name('api.')->prefix('v1')->group(...)`, giving
API routes distinct names (`api.doctors.index`) without touching any
resource registration or controller code (grepped first to confirm no
controller referenced a route by name).

## JSON API for Flutter

Every web module has a matching token-authenticated (`Authorization:
Bearer <token>`) JSON endpoint under `/api/v1`, versioned so a shipped
mobile build doesn't break as the API evolves.

**Auth**: `POST /api/v1/login` — unified (see
`docs/auth-and-public-pages.md`): one `login`/`password`/`device_name`
body tried against staff (`users`) then doctors (`doctors`), returning
`account_type` so the client knows which resource shape it got back. Plus
`POST /api/v1/logout`, `GET /api/v1/me`. (An earlier, now-removed
`/api/v1/doctor/login` split by account type before the unification.)

**Doctors / Patients**: standard REST, `DoctorResource`/`PatientResource`.

**Lookups** (read-only): `education-types`, `stages`, `departments`.

**Tasks**: standard REST at `/api/v1/tasks`, `TaskResource` nests
`department`/`case_sheet_type`/`stage`/`instances`.

**Academic sessions**: standard REST; `show` also returns a `stats` block
(`doctors`, `groups`, `required_tasks`, `done_tasks`, `remaining_tasks`).
No "selected session" concept over the API since Sanctum is stateless.

**Groups**: standard REST plus `GET /api/v1/groups-available-doctors`
(`?stage_id=`) and bulk `POST`/`DELETE /api/v1/groups/{id}/doctors` (`{
"doctor_ids": [...] }`) — adding a doctor removes them from any other group
first, same one-group rule as the web UI.

**Backup** (admin): `GET/POST /api/v1/backup`, `PUT /api/v1/backup/auto`.
No file-download endpoint over the API — metadata only; raw `.sql` downloads
stay a web-UI link.

**Case sheet forms**: `GET /api/v1/case-sheet-forms` (the sheets,
`{resource, title}`), `GET /api/v1/case-sheet-forms/{resource}` (layout
only — fields/types/options/groups, no record).

**Task instances** (doctor-facing task list):

| Method | Path | Notes |
|---|---|---|
| GET | `/api/v1/my-task-instances` | authenticated doctor's own tasks (403 for a `User`); `?status=` filter |
| POST | `/api/v1/task-instances` | assign task to doctor |
| PUT | `/api/v1/task-instances/{id}` | update status/grade/notes; doctor can only touch their own (403); `status=completed` auto-stamps `completion_date` |
| DELETE | `/api/v1/task-instances/{id}` | remove assignment |

**Appointments / Payments**: standard REST, with `?doctor_id=`,
`?patient_id=`, `?pinned=1` / `?appointment_id=` filters.

**TV board**: `GET /api/v1/tv-board` — the API's only unauthenticated
endpoint.

**Case-sheet ↔ task-instance linkage for Flutter** (added later): Flutter's
case-sheet screens originally never sent `task_instances_id` on create, so
a sheet filled from the app floated free of the case it was meant for. The
web's `type_code` → resource resolution and "does a record already exist
for this instance" lookup was extracted out of `CaseSheetController` into
`App\Support\CaseSheetResolver` (one shared home instead of a second,
divergent copy), and a new `Api\CaseSheetController::open()` (`GET
/api/v1/task-instances/{taskInstance}/case-sheet`) gives Flutter the same
resolve-or-create behavior as the web, returning `{resource, record_id,
case_sheet_type}`. Access branching mirrors the web controller exactly
(doctor: own-instance-only; staff: `PermissionManager::can('task_progress',
'open_case_sheet')`) but is checked in code rather than via `permission:`
route middleware, since that middleware assumes a staff `User` principal
and would break the doctor half of the same endpoint. A new
`Api\PendingTaskQrController::show()` (`GET
/api/v1/pending-tasks/{task}/qr`) gives Flutter the "pending_task" QR (a
task+doctor pair with no instance yet) it previously had no way to
generate. On the Flutter side, `CaseSheetFormScreen` now threads
`taskInstanceId` through as a `task_instances_id` query param, and a
`showQrDialog()` helper generalizes QR display across the doctor's task
list, the case-sheet form's AppBar, and the task-instance detail screen.

## Admin & settings screens

**Clinic settings** — port of `admin/clinic_settings.php`: a single-row
`clinic_settings` table (`ClinicSetting::current()` does `firstOrCreate`).
MikroTik fields (`mikrotik_ip/user/pass/ssh_port`) and `jwt_secret_key`
exist on the imported table but are deliberately excluded from `$fillable`
and every form — out of scope by explicit request. Everything else is
ported (name/description/logo/address/phone/email/website/hours/
currency/timezone, university+college name for print headers, notification
toggles). Two real bugs caught by testing: `$fillable` initially omitted
`id`, but `clinic_settings.id` is `NOT NULL` with no auto-increment or
default — the very first `firstOrCreate()` threw `Field 'id' doesn't have a
default value` (fixed by adding `id` to `$fillable`); and `clinic_logo`'s
real column default is the literal string `'default-logo.png'`, a filename
that only ever existed in the *original* app's `uploads/` folder — a fresh
settings row would build a broken image URL from it, fixed by having
`logoUrl()`/`universityLogoUrl()` check `Storage::disk('public')->exists()`
first and fall back to the static SVG. Shared app-wide via Inertia
(`clinicSettings: { name, logo_url }`, wrapped in `once()`). Access:
`role:super_admin,admin` (no separate `permission:` gate — `'settings'` was
never added as a module). API: `GET`/`PUT /api/v1/clinic-settings`.
Deliberately not ported: `register_settings.php` and
`admin/patient_register.php` (writes to a different table, `patients_admin`
— would create a second, disconnected patient list).

**Database backup** — port of `admin/backup.php` +
`admin/ajax/backup_db.php`: manual trigger, daily-auto toggle, list of
recent backups, minus the MikroTik SCP upload step (out of scope). A real
bug found while reading the original (not reproduced): its
`clinic_settings_upsert()` wrote to a `CREATE TABLE IF NOT EXISTS
clinic_settings (setting_key, setting_value, ...)` key/value shape that
never matched the real single-row `clinic_settings` profile table — every
insert after the no-op `CREATE TABLE` threw an "unknown column" error the
code silently swallowed, so **the daily-backup toggle and last-backup
timestamp were never actually saved in the original**. Fixed for real here
with two proper columns (`enable_daily_backup`, `last_backup_at`) on the
actual table. The "daily" part is a real schedule, not a page-load side
effect — the original only ran its auto-backup when an admin happened to
load the dashboard that day; replaced with `php artisan backup:run`
(`App\Console\Commands\RunDatabaseBackup`) via
`Schedule::command('backup:run')->daily()`, which does its own
already-ran-today de-dup. Server setup: Windows Task Scheduler → action
`php artisan schedule:run`, trigger "daily, repeat every 1 minute," since
XAMPP has no built-in cron on Windows. Storage: `storage/app/private/backups/`
(Laravel's private `local` disk, not a public folder like the original's
`admin/downloads/backups/`); downloads go through `BackupController::download`,
which rejects path separators/`..` before touching the filesystem and sits
behind `role:super_admin,admin` — a real authorization check where the
original had a guessable public URL. Creation: `DatabaseBackupService`
tries the bundled XAMPP `mysqldump.exe` first, falls back to a PHP/PDO
structure+data dump — same two-tier strategy as the original, minus the
MikroTik step. API: `GET`/`POST /api/v1/backup`, `PUT /api/v1/backup/auto`
(no download endpoint over the API).

**Activity log** — see "Activity logging" above.

**Case sheet types management** — an audit pass read every remaining
unported `admin/*.php` page directly and cross-checked
`includes/navbar.php` for whether it's actually linked (not assumed from
the filename). Findings: `view_reports.php`, `login_as_doctor.php`/
`logout_from_doctor.php`, and `assign_tasks.php` are only reachable from a
retired, no-longer-`require`d navbar file — orphaned, not ported.
`case_sheet_manager.php` was **live, real, and missing**: `CaseSheetType`
had a model but no CRUD screen. Ported `admin/ajax/case_sheet_types_crud.php`'s
real logic — `type_code` immutable after creation
(`^[a-z0-9_]+$`, unique), `display_order` auto-set to `max+1`, delete
blocked with an exact count message if any `tasks` row still references
the type. The original's bulk `update_order` reorder action has no
front-end drag-handle UI actually wired to it — not ported, same
"build what's reachable today" rule applied elsewhere. Added as a sixth
item ("أنواع النماذج السريرية") in the "إدارة البيانات الأساسية" nav
dropdown, gated `role:super_admin,admin` matching what the original AJAX
backend actually enforces (not the more decorative navbar permission
check). API: standard REST at `/api/v1/case-sheet-types`.

**Other admin-area fixes bundled with this work**: `HandleInertiaRequests::share()`
originally only ever shared `flash.success`, so the Academic Sessions
delete-guard's `flash.error` messages (e.g. blocking deletion of the
current session) never reached the page — a blocked action silently did
nothing with no explanation. Fixed by sharing `flash.error` too.

**Admin dashboard** rebuilt from a placeholder (a closure rendering two
raw counters) to port `dashboard.php`: three headline counters, a
done-vs-not-done task bar plus an instance-status breakdown (the more
useful number now that instances drive the workflow), permission-filtered
quick-access cards, latest-5 doctors/patients, and the on-demand
required/completed/remaining-by-department-and-stage section. Session-scoped
like the rest of the app. Deliberately not ported: the "login as doctor"
impersonation card (orphaned feature in the original), the backup card
(MikroTik, out of scope), and the "new patient" counter's original
three-table sum (`patients`+`patients_simple`+`patients_admin`) — this
rebuild counts only `patients`, the table the schema's FKs actually
reference.

**Email settings, password reset, notifications, profiles** — first
established what the original actually has: a full grep for
`mail(`/PHPMailer/SMTP across the legacy codebase found **nothing but its
own settings getter** — no mail config, no mail ever sent, no password
reset of any kind exists in the original at all. So this whole area is new
functionality, not a port, apart from the settings/profile screens
themselves:
- **SMTP settings**: seven new columns on `clinic_settings`
  (`mail_host/port/username/password/encryption/from_address/from_name`),
  edited from the settings page. `MailSettingsServiceProvider` applies them
  over `.env` at boot; with nothing configured it leaves Laravel's
  `MAIL_MAILER=log` default, so reset links land in the log and are
  testable before real SMTP exists. Stored password is `encrypted`-cast and
  `$hidden`; a blank submission keeps the existing value.
- **Password reset**: doctors are a separate guard/table from staff, so
  they get their own broker (`passwords.doctors`), routes
  (`/doctor/forgot-password`, `/doctor/reset-password/{token}`, throttled
  6/min), and an Arabic notification — reusing Laravel's built-in
  notification would have built a URL against the staff route and landed a
  doctor on the wrong form. The reset endpoint reports the same neutral
  status regardless of whether the address exists, so it can't be used to
  enumerate registered doctors.
- **Email notifications**: `App\Services\Notifier` is the single gate —
  sends only when both `enable_notifications` and `enable_email` are on,
  skips notifiables with no address, and swallows+logs delivery failures so
  a dead mail server can't fail the request that triggered it (e.g. task
  assignment). This is what finally gives the original's two decorative,
  never-read toggles real meaning.
- **Profile pages**: both staff and doctor rebuilt to match the original's
  two-separate-forms shape (`update_profile` / `change_password`). The
  doctor page previously merged both into one form with an optional
  password field and **no current-password check** — anyone with a live
  session could change the password without knowing the old one; now split
  and verified. The staff page was still the stock Breeze scaffold
  (name+email only, despite `phone`/`profile_image` being real columns the
  original exposes); a delete-account form with no original counterpart was
  dropped as out of place for self-service.

Password reset was later replaced app-wide (2026-08-29) with a 5-minute
one-time OTP code instead of an emailed link, and needed two more rounds of
fixes the same/next day before OTP delivery actually worked in production
— the root cause both times traced back to production email only starting
to send for real on 2026-08-28 (see below), and finally to a raw DB
datetime string being handed to `diffInSeconds()` without being cast to a
`Carbon` instance first.

## PDF/print exports

**Doctor printing (web)** — port of `admin/print_doctors.php` (roster
grouped by stage, per-stage counts, summary box, signature lines, clinic
logo watermark) and `print_doctor_card.php` (single doctor ID card).
Written as Blade views, not Inertia pages, deliberately — standalone print
documents with their own letterhead and `@media print` rules; rendering
them inside the app shell would print the nav alongside them. One roster
endpoint serves both original buttons (filtered vs. selected-rows print).
Gated on `doctors.export`.

**PDF printing (Flutter)** — the user asked for PDF printing "the same way
it exists in dentalclinic," but research found the legacy pages
(`print_doctors.php`, `print_doctor_card.php`, `task_progress_print.php`)
are not real server-generated PDFs at all — plain HTML with `@media print`
CSS, printed via `window.print()` in a browser tab. There's no browser tab
on a mobile app to reproduce that trick in, so Flutter's version is a
genuine client-side PDF (`pdf`/`printing` packages), same content/layout,
built the way a mobile app actually can. Confirmed the legacy app has **no
standalone "group" print** at all — its only "group" report is the
task-progress print scoped to a group — so the Flutter group roster PDF is
new, not ported. Arabic text needs a bundled font since the `pdf` package
renders its own glyphs: **Tajawal** (OFL) was bundled rather than the
originally-planned Cairo, because Cairo and most modern Google-Fonts Arabic
families now ship variable-font-only with no separate static Bold file the
package can load as a second font instance.

Three PDFs share one `buildLetterhead()` widget
(`core/pdf/pdf_letterhead.dart`): doctor roster (per-stage tables +
summary box), group roster (slots + member table), and task-progress
(cover block + one table per department, iterating every required slot so
unfilled ones print too, matching the legacy page). A real bug was found
live: the letterhead's university/college name rendered blank on first use
because `ref.read(clinicSettingsProvider).valueOrNull` read the
`FutureProvider`'s synchronous `AsyncLoading` state instead of waiting for
the fetch — fixed by awaiting `clinicSettingsProvider.future` instead. The
`pdf` package has no native table rowspan, so a doctor's name was
originally repeated on every one of their task rows in the task-progress
report; later changed (2026-08-29, by request after a real 68-row export
was reviewed) to only print the name on the first row of each doctor's
block, blank on the rest — the standard faux-rowspan technique. This report
has no web/Blade counterpart — it's Flutter-only, a client-side port of
`admin/task_progress_print.php`.

## Production data migration

`php artisan app:import-legacy-data`
(`app/Console/Commands/ImportLegacyData.php`) — a one-time import of the
real clinic data from `clinic_system2` into this app, reading directly via
`DB::table('clinic_system2.<table>')` since both databases live on the same
MySQL server (no second connection needed). Before this, `dental_laravel`
held only hand-entered test data (1 doctor, 1 group, 1 task, the admin
account); the real 139 doctors and their task/case-sheet history lived only
in the legacy database.

**Why it isn't a straight table copy**: column sets are structurally
identical between the two schemas for nearly every table, but **row ids are
not** — `departments` and `case_sheet_types` were seeded independently
while this app was being built (e.g. source department id 6 "operative" is
id 16 here). Every foreign key is remapped through an id map built by
matching on a natural key (name / type_code) before any row is inserted;
copying ids verbatim would have silently mispointed every imported doctor,
task, and case sheet.

**Data-quality issues found and fixed** (caught by a dry run inside a
rolled-back transaction before anything was committed for real): MySQL's
old `'0000-00-00'` placeholder date, present in user-entered clinical
fields, rejected outright by this app's strict-mode connection — sanitized
to `NULL`. `dental_charts.chart_type` (`enum('primary','permanent') NOT
NULL DEFAULT 'permanent'`) had one source row with `''` — falls back to the
column's own default. `tooth_treatments.treatment_type` had 30 of 49 rows
with `''` — falls back to the enum's own `'other'` member (confirmed the
only other such case via a full enum audit).

**Deliberately not imported**: the source `admin` user (collides with this
app's own); MikroTik fields/`jwt_secret_key` (out of scope); the confirmed
orphaned `roles`/`permissions`/`role_permissions`/etc. tables
(`user_permissions` is the table real access control actually reads);
`doctor_tasks`/`task_assignments`/`task_progress`/`doctor_task_progress`
(confirmed dead); `register_days`; and `clinic_settings`' operational
fields (logo/base_url/mail/theme) — this app already had those configured
for real, and overwriting them with stale source values would have undone
that configuration; only descriptive identity fields were merged in. The
two real logo files and one doctor photo present on disk in the source
app's `uploads/` were copied across by filename and verified present with
`Storage::disk('public')->exists()` before their columns were set.

**A design detail confirmed while writing the activity-log import**:
`user_activity_log.user_id` is overloaded in both schemas — 13 source log
rows had `user_role='doctor'` with a `user_id` that only resolves against
`doctors`, not `users`. The importer branches on `user_role` and remaps
through the correct id map rather than dropping those rows.

**Verification**: a dry run in a rolled-back transaction, then FK-integrity
checks (zero orphaned foreign keys across every remapped table) against the
committed data, then a full feature pass against the real imported data —
doctor login, every core listing page, `CaseSheetController::open()`
routing a real task instance, imported staff permission grants working
through `PermissionManager`/`ScopeHelper`, the API doctors endpoint, the
doctor-roster print, and a real surgery case-sheet print with its QR. Final
row counts: 139 doctors, 138 group memberships, 15 tasks / 34 instances, 18
surgeries / 28 medications, 6 dental charts / 49 tooth treatments, 1 each of
6 specialty-record types, 36 `patients_simple`, 3 academic sessions, 22 user
permissions, 349 activity-log rows.

## Production deployment (GitHub Actions → cPanel)

The project is live at `cdclinics.com`, deployed automatically from
`hakamiraqi/cdc` on every push to `main`, replacing the original PHP
`dental_clinics2` app that had been running at that domain (its files are
untouched on disk, just no longer served).

**Workflow** (`.github/workflows/deploy.yml`): `composer install --no-dev
--optimize-autoloader` and `npm ci && npm run build` run in the CI runner
itself, so the *built* app (`vendor/`, `public/build/`) ships, not raw
source the server would need to build. The SSH private key (repo secret
`SSH_PRIVATE_KEY`, passphrase in `SSH_KEY_PASSPHRASE`) is written to a temp
file with its passphrase stripped in-place (`ssh-keygen -p -N ""`) so the
ephemeral CI job can use it non-interactively. The built tree ships to
`/home/cdclinics/dental_laravel/`, then `php artisan migrate --force` +
cache commands run over SSH.

**Why `tar czf - | ssh ... tar xzf -` instead of `rsync`**: the first
deploy attempt used `rsync -e ssh` and failed — the shared-hosting account
has no `rsync` binary at all (confirmed via `which rsync` in cPanel's
Terminal), and `rsync` needs the binary on both ends regardless of
transport. Switched to piping a `tar` stream over `ssh`, which only needs
universally-present `ssh`/`tar`. Trade-off: unlike `rsync --delete`, this
never removes files deleted from the repo — accepted for now.

**Why `migrate --force` failed on the very first production run**:
`2024_01_01_000000_import_clinic_schema` replays the full 61-table
`clinic_system2` DDL via raw SQL — exactly the schema production's
database *already had*, since it's the same live database the legacy PHP
app runs against. `CREATE TABLE` failed immediately on the first table
with `SQLSTATE[42S01]... already exists`. One-time fix: manually recorded
that migration as already-run without executing it (`DB::table('migrations')->insert(...)`
via `tinker`), after which `migrate --force` ran clean for every
genuinely-new migration. Every migration from that point on runs
automatically through the normal pipeline.

**Why the domain switch-over used a symlink instead of cPanel's Document
Root field**: cPanel's Domains UI on this account only exposes an editable
Document Root for subdomains/addon domains — the primary domain's row shows
"No configuration options currently exist." Worked around over SSH instead:
`mv public_html public_html_old_backup && ln -s
/home/cdclinics/dental_laravel/public public_html` — identical effect
Apache-side, and trivially reversible. Side benefit: a leftover debug file
(`public_html/phpinfo.php`, guarded only by a static `?key=` query string)
is no longer web-reachable either, since nothing points at the old backup
directory anymore.

Production `.env` lives only on the server, excluded from the `tar`
transfer (`--exclude='.env'`) so a deploy never overwrites it; `DB_*`
values point at the same `cdclinics_clinic_system` database the legacy app
used, reused as-is from the legacy app's own `config/db.php`. Verified
end-to-end on production with a disposable test account (not the real
`admin`), confirming DB connectivity/sessions/auth against real data (139
doctors, 36 task-progress rows), then removed the test account.

Still open at the time of writing: `Force HTTPS Redirect` was off in
cPanel; `public_html_old_backup` is being kept as a rollback safety net.

## Production schema drift, and the diagnostic tooling built for it

Adopting an already-live database by marking its baseline migration
"already run" instead of executing it is only as safe as the assumption
that the target database actually matches what that migration would have
created — and in this project that assumption turned out to be wrong in
specific, narrow spots.

**Bug 1 — missing `academic_session_id` on three tables.** First real
post-deploy bug report: the Flutter "الأعوام الدراسية" screen showed a
generic error; `laravel.log` on production named it exactly —
`SQLSTATE[42S22]: Unknown column 'groups.academic_session_id'`. Root cause:
production's real `clinic_system2` database predated whichever point the
legacy app added that column to `groups`/`tasks`/`task_assignments`
specifically. `doctors.academic_session_id` was fine because it had its own
dedicated, actually-executed migration; the other three never got one,
since the baseline import was assumed sufficient. Fix: a new migration
guarded per-table with `Schema::hasColumn(...)`, confirmed locally that dev
needed all three too (never surfaced there since local dev's DB has its own
separate history).

**Bug 2 — same day, `academic_sessions.id` missing AUTO_INCREMENT.**
Creating a new academic year hit `SQLSTATE[HY000]: 1364 Field 'id' doesn't
have a default value`. `schema_import.sql` adds the primary key and
`AUTO_INCREMENT` via separate `ALTER TABLE` statements after `CREATE
TABLE` (mysqldump's usual style) — production's real table was missing
both, same root cause as bug 1: an older table than the dump the schema was
built from. Fixed with a migration that checks `information_schema` before
doing anything (no-op wherever already correct).

**The diagnostic built instead of another reactive round-trip.** Two
unrelated drift bugs in one day made clear this wasn't a one-off. Added
`php artisan schema:diagnose`
(`app/Console/Commands/DiagnoseSchemaDrift.php`) — read-only, parses every
`CREATE TABLE`/`ADD PRIMARY KEY`/`MODIFY ... AUTO_INCREMENT` statement
straight out of `schema_import.sql` and diffs it against
`information_schema` on whatever database it's run against, reporting every
missing table, column, primary key, or AUTO_INCREMENT gap in one pass.

**Run against production, it found 152 gaps.** Each was cross-checked
against actual app code (grep for the column/table name) before deciding
what to fix, since a "missing" column the dump expects doesn't necessarily
mean this rebuild still uses it:
- **Real bugs, fixed** (`2026_08_28_090000_fix_production_schema_drift.php`):
  `periodontal_charts` was missing ~135 columns `PeriodontalChart::$fillable`
  actively uses — the entire Periodontal Chart sheet was unusable on
  production before this; `user_activity_log` was missing 10 columns
  `ActivityLogger` writes on every logged action (activity logging silently
  broken); `complete_denture_records.last_tooth_extracted_teeth` was
  missing.
- **Deliberately left alone**: `app_settings`/`endodontics_images`/
  `mikrotik_settings` tables, `clinic_settings.mikrotik_*`/`jwt_secret_key`,
  `doctor_tasks.academic_session_id`, `patients_simple.gender` — confirmed
  via grep that nothing in `app/` references any of them; inert legacy
  artifacts, not bugs in this rebuild.

A quirk in the diagnostic tool itself: `information_schema`'s column-name
casing (`TABLE_NAME` vs `table_name`) isn't consistent across MySQL/MariaDB
versions — the command crashed on its first production run
(`Undefined property: stdClass::$table_name`) despite working locally,
because the two servers returned different casing for the same query.
Fixed by normalizing every row through `array_change_key_case(..., CASE_LOWER)`
rather than assuming either server's casing.

**Production email**: `.env` had `MAIL_MAILER=log` (the local-dev default)
since the very first deploy, so real password-reset/notification emails
were being written to the log instead of sent — invisible to any end user.
Switched to `smtp` via the cPanel-hosted mailbox
`adminstrator@cdclinics.com` (spelled without the second "i" — the real
account address). A Laravel-12-specific gotcha: Symfony Mailer (which
Laravel 12 uses under the hood) renamed the old `MAIL_ENCRYPTION=ssl/tls`
values — `MAIL_SCHEME=ssl` throws `UnsupportedSchemeException` on the first
send. The `smtp` transport only accepts `smtp` (STARTTLS, port 587) or
`smtps` (implicit TLS, port 465, what this mailbox uses). Verified via
`Mail::raw(...)` through `tinker` on production and confirmed delivered via
Webmail.

## Local dev setup

1. Database `dental_laravel` already created (XAMPP MySQL, `root` / same
   password as the PHP app's `config/db.php`).
2. `composer install && npm install`.
3. `.env` already configured + `php artisan key:generate` run.
4. `php artisan migrate --seed`
5. `npm run build` (production) or `npm run dev` (Vite dev server).

**Scheduled tasks (production-parity backups)**: Laravel's scheduler needs
something to actually call `php artisan schedule:run` every minute — XAMPP
sets up no cron on Windows. One-time setup: Windows Task Scheduler → new
task → trigger "daily, repeat every 1 minute for a duration of 1 day" →
action `C:\xampp\php\php.exe artisan schedule:run` with "start in" set to
the project root. Without this, the manual backup button and the
daily-backup toggle still work; only the unattended daily run doesn't fire.

## Installable builds (brief)

A Windows `.msix` installer and an Android release APK (Android 8.1/API 27+)
were built by direct user request. Two real bugs surfaced getting the
release APK working on a real device: release builds had no `INTERNET`
permission at all (the Flutter template only grants it in the
debug/profile manifests, never `src/main/AndroidManifest.xml`, so every
release build had silently zero network access), and
`network_security_config.xml` only allowlisted the Android emulator's
`10.0.2.2` loopback — `targetSdkVersion 36` blocks cleartext HTTP to any
other host regardless of the device's own OS version, so a real Android 8.1
phone was blocked too. Verified on a real (`armeabi-v7a`, not the initially
assumed `arm64-v8a`) Android 8.1 device via `adb`; the Windows `.msix`
remained unverified on real end-user hardware. Full detail, including the
architecture and phased build-out this belongs to, is covered in the
Flutter app architecture doc.
