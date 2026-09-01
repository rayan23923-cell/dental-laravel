# Tasks, Academic Structure & Permissions

## Domain overview

A **task** is a required clinical-procedure type (e.g. an Operative filling)
that a student/doctor must complete some number of times
(`tasks.required_count`) within an academic stage before graduating.
`task_instances` rows are the actual attempts — there's no per-instance FK
back to a specific "slot"; the slot model is purely **positional**
(`instances[$slot]`), matching the original legacy app exactly. An instance's
`status` is one of `pending`/`assigned`/`completed`; "unassigned" is a
**computed** state (`required_count − existing instances`), not a DB value.

Everything is scoped by a taxonomy: **academic session/year** →
**education type** → **stage** → **department**, plus **groups** (a cohort
of doctors with weekly time slots under one stage). A fourth,
orthogonal system — the **permission matrix** — is a role/user × module ×
action grid (`view`/`create`/`edit`/`delete`/...) that gates which pages and
actions an account can reach, further narrowed by a **4-dimension access
scope** (department/stage/education-type/academic-session) that restricts
*which rows* a scoped account can see within an otherwise-permitted module.

The web app (Laravel/Inertia/Vue) and the Flutter mobile client share one
backend (`/api/v1`), and this whole subsystem was built to parity across
both — most entries below have a matching pair of web/Flutter changes done
together.

## Academic taxonomy (sessions/years, stages, education types, departments)

**Education types → stages → departments** form a fixed cascade, ported from
the legacy app's `admin/manage_doctors.php` / `manage_tasks.php` /
`admin/ajax/{doctors,departments,education_types}_crud.php` and
`get_stages_list.php`/`get_stages_by_edu.php`/`get_departments_by_stage.php`
(the legacy app has ~5 near-duplicate cascade-filter endpoints doing the
same thing across different pages — a deliberate, pervasive pattern there).
An audit (2026-08-18) found and fixed four real gaps against the live
schema/controllers:

1. Doctor create/edit forms didn't filter the stage dropdown by the chosen
   education type — fixed client-side (`filteredStages` computed +
   watcher clearing an invalid `stage_id`), disabling the stage select
   until an education type is picked. `Patients`/`Tasks` forms don't need
   this — neither table has an `education_type_id` column.
2. Task forms didn't filter the department dropdown by stage
   (`departments.stage_id` is real) — fixed the same way, with
   `stage_id IS NULL` departments always selectable.
3. `ScopeHelper` wrongly exempted **both** `super_admin` and `admin` from
   department/stage/education-type scoping; the legacy app only exempts
   `super_admin`. Fixed to match exactly.
4. The scoping helper (`scopeDepartments`/`scopeStages`) existed but had
   **zero call sites** anywhere — fully inert. Wired into
   `EducationTypeController::index`, `StageController::index` (stage
   restriction takes priority, falls back to education-type restriction),
   `DepartmentController::index`, and `DoctorController::index`, mirrored
   on the `Api\*` controllers too. Added a missing
   `ScopeHelper::scopeEducationTypes()`. `scope*()` methods were widened to
   accept any `Authenticatable` and no-op for a `Doctor` principal, since
   `/api/v1` shares a Sanctum guard between staff and doctor tokens and
   role-based scoping is staff-only in the legacy app.

**Important semantic** (easy to get backwards): a user with **zero** rows in
`user_allowed_departments`/`_stages`/`_education_types` is **unrestricted**
— restriction only starts once at least one row exists.

### Academic sessions / years

`academic_sessions` (`id, name, start_date, end_date, is_active, is_current`)
existed in the imported schema with **zero** Laravel representation despite
being live-used across 47 legacy PHP files. Built from scratch (2026-08-18),
porting real paths and skipping confirmed-superseded duplicates. Three
distinct, easy-to-conflate concepts, carried over from `SessionHelper.php`:
`is_active` (soft-enable), `is_current` (exactly one system-wide default),
and a per-browser-session **"selected"** session (which session an admin is
currently *viewing*, independent of `is_current`) — legacy stores this in
`$_SESSION['academic_session_id']` with a 3-level fallback (selected →
current → latest active), ported as
`App\Services\AcademicSessionHelper::resolve()` using Laravel's session.
Delete is guarded exactly as legacy: refuses if the session has any linked
`groups`/`tasks`, and the current session can't be deleted at all.

Because Sanctum tokens are stateless, the API has no "selected session" to
persist — `Api\AcademicSessionController::show()` always reflects the
session id in the URL, and `POST /groups` accepts an optional
`academic_session_id` (falls back to `is_current`) instead of a browser
session.

**A fresh-install deadlock, found and fixed**: `resolve()` originally used
`firstOrFail()`, which 500'd `AcademicSessions/Index` and `Groups/Index` on
a zero-row database — nobody could ever create the first session. Fixed by
making `resolve()`/`resolveId()` nullable and having every caller treat "no
session yet" as valid.

**Session filtering convention**: everywhere the legacy app's own idiom is
used — `academic_session_id = ? OR IS NULL` — so a `NULL` session means
"visible under every year" (e.g. every doctor imported from the legacy DB is
session-less). This is deliberate, not a bug, and is used consistently for
Doctors/Groups/Tasks/Task-Progress *listing and assignment* screens. Session
**stats** pages (below) are the one deliberate exception — they scope
strictly, no `OR NULL` leak, since a session-less task showing up on *every*
year's stats page would make the page meaningless.

**Required/done/remaining, session-wide**: `required = Σ required_count`,
`done = Σ completed instances`, `remaining = Σ max(0, required_count −
completed)`, computed only over tasks explicitly tied to that session.

**Doctors/groups/tasks tied to a session (2026-08-19)** — requirement: a new
academic year gets its own doctors/groups/tasks, and prior years stay
intact. What was actually there: `groups.academic_session_id` and
`tasks.academic_session_id` already existed, but **`doctors` had no session
column at all**, nor did `doctor_group_members` — a doctor's year was only
ever implied by group membership, so a doctor with no group couldn't be
listed/filtered, and (a real data-loss bug) `GroupController::addDoctors`'s
"one group at a time" rule ran an **unscoped**
`whereIn('doctor_id', …)->delete()` — adding a doctor to a 2025 group
**deleted their 2024 membership row outright** (present on both the web
controller and its `Api\GroupController` mirror, so Flutter could destroy
history too). Fixed with migration
`2026_08_19_120000_add_academic_session_to_doctors.php` (nullable, indexed
columns on both tables) and the rule became **"one group per academic
session"**: `addDoctors` now scopes its delete to the group's session, so a
doctor enrolled in a 2024 group and then a 2025 group ends with two
membership rows, one per year. `availableDoctors` correspondingly means "not
in a group *this* session."

Session filtering was then applied across Doctors list/create/edit/print
roster, Groups list, Tasks list/create (previously **not** session-aware at
all — task create never stamped `academic_session_id`, so every
Laravel-created task was session-less), Task detail (only offers doctors
from its own year), and the session stats page (counts via direct enrolment
**or** group membership, since an intake can exist before groups do). Other
bugs fixed in the same pass: an ambiguous-column SQL error once
`doctor_group_members` gained `academic_session_id` (qualified as
`groups.academic_session_id`); `tasks.grade` (0–100 grade a task can define)
was missing from the Laravel task forms entirely; the API doctor search
repeated an unnested `orWhere` bug that let a search escape scope filters
(nested it); `DoctorResource` could fatal on `whenLoaded('academicSession')`
for a session-less doctor (null-guarded).

**Renamed to "العام الدراسي" and enforced single-active-year (2026-08-25)** —
three asks: rename the concept for clarity, guarantee exactly one *active*
year at a time, and make each year's doctors/groups/tasks/task-progress
genuinely independent with an active-year banner visible everywhere.
- `AcademicSession::booted()` gained a `static::saving()` hook: saving a row
  with `is_current = true` wipes `is_current` on every other row in the same
  request, in the model layer — replacing six duplicated "wipe all, set one"
  blocks across the web/API controllers' `store()`/`update()`/`setCurrent()`,
  and protecting *any* write path (tinker, a seeder) automatically.
- New `GET /academic-sessions/current` → `{id, name}` or `null`, so Flutter
  stops re-deriving "which year is active" five separate times.
- **Real scoping gap in `Api\GroupController::index()`**: unlike
  `Api\DoctorController`/`Api\TaskController`, it only filtered by year when
  the client explicitly passed `academic_session_id` — and Flutter's own
  provider never sent it, so **the Flutter Groups list silently showed every
  year's groups mixed together.** Fixed with the same
  `resolveId()` + `where(...)->orWhereNull(...)` pattern the other two
  controllers already used.
- **The biggest gap — task progress**: `TaskProgressGroupSummary::build()`,
  `DoctorTaskSummary::build()`, and `TaskProgressFilters::build()` (shared by
  the web and API task-progress controllers) filtered tasks only by
  `stage_id`, with **no year filter at all** — a task from any year for that
  stage appeared in the matrix regardless of which year was active. All
  three gained a resolved `$academicSessionId` parameter and the same
  `OR NULL` filter.
- Web/dashboard `TaskProgressController::index()`/`DashboardController::index()`
  gained a `currentSession` prop so Task-Progress and the dashboard show an
  active-year banner (previously they had none).
- UI text unified to singular "العام الدراسي" / plural "الأعوام الدراسية" —
  the web app previously had three different phrasings live simultaneously.
- Live check found the real dev DB had **zero** rows with `is_current=1` at
  all (silently papered over by `resolve()`'s fallback-to-latest-active);
  set explicitly via tinker so the state stopped being ambiguous. Also found
  and, on user confirmation, deleted a genuine duplicate "2027" session row
  (same name/dates, 0 groups/tasks) that had confused which row was active.
- Follow-up: both the web (`AcademicSessions/Index.vue`, a Tailwind toggle
  pill) and Flutter (`CupertinoSwitch`) admin screens replaced their old
  status-badge/button with a single toggle calling `setCurrent()`, disabled
  on the row that's already current since there's no "turn off" action —
  only "turn a different year on."

Flutter side (`flutter_app/README.md`, 2026-08-25): renamed labels app-wide
(also fixing gendered Arabic agreement — `مفعّل`/`غير مفعّل`/`النشط حالياً`
replacing feminine forms that no longer agreed with masculine `العام`); new
`CurrentAcademicYear` domain class (deliberately not reusing the CRUD model,
to avoid misleadingly-defaulted fields on a read-only object); a
non-`.autoDispose` `currentAcademicYearProvider` (read by 5 screens at
once); and a shared `AcademicYearBanner` widget at 5 call sites (Doctors,
Groups, Tasks, Task Progress list screens, and the staff dashboard) that
renders nothing while loading/erroring/inactive.

## Tasks & required-task tracking

**Required/done/remaining computation** ported from
`task_progress_view.php`'s SQL (`COUNT`/`SUM(CASE …)` per task, grouped).
`tasks.required_count` is the target; the per-doctor progress screen
(below) uses the same math per task.

**`is_required` flag (2026-08-23, ported to both web and Flutter)**: new
`tasks.is_required` boolean column (default `true`) for نوع المهمة —
أساسية (mandatory) vs. اختيارية (optional); didn't exist in any form
before. Also added: an education-type dropdown to the Tasks create/edit
forms (previously only an unfiltered stage select — now cascades exactly
like the Tasks list already did; `tasks` has no `education_type_id` column,
so it's UI-only and never sent to the server; edit derives the initial
education type from the task's stored stage), and "Add Task" now carries
the list's active stage/education-type filter into the create form.

**A real bug found during verification**: `Api\TaskController::store()`
returned `is_required: false` in its *immediate* JSON response when the
field was omitted, even though the DB default is `true` and a fresh `GET`
correctly showed `true`. Cause: a freshly-`create()`d Eloquent model never
learns a column's DB-level default if that column wasn't in the passed
attributes — accessing it returns `null`, and `TaskResource`'s
`(bool) $this->is_required` turned `null` into `false`. Fixed with
`$task->refresh()` right after `create()` — closes the gap for every column
with a DB default, not just this one.

Flutter (`task_form_screen.dart`) got the same education-type cascade (via
`taskEducationTypesProvider`), the same filter carry-over from the task
list's FAB (passed as router `extra`), and the أساسية/اختيارية field using
the app's existing `RadioGroup<T>` pattern, defaulting new tasks to
أساسية, with a badge on the task-list tiles.

## Task progress matrix & NFC lookup

Two **separate** legacy screens exist and both were ported:

**Admin task progress ("إدارة تقدم المهام", 2026-08-19)** — a
browse-and-act screen (`admin/task_progress_view.php` +
`get_group_doctors.php`), not a report. Flow: filter by day (only days some
`group_slots` row actually uses, in the legacy app's explicit week order,
not alphabetical) → education type → stage → pick a group → a
**department-tabbed matrix** (one tab per department of the group's stage),
each row a doctor with المطلوب/مكتملة/قيد التنفيذ/معلقة/غير مخصص counts,
expandable into one task card per required slot. Actions, ported with real
server-side guards (from `assign_task_ajax.php`/`mark_task_completed.php`/
`update_task_instance.php`, not just the happy path):
- **بدء المهمة** — `required_per_doctor` falls back to `required_count`;
  refused once a doctor has completed their required number; lazily
  creates **one** instance at a time rather than pre-creating all N
  (deliberate, to avoid overproduction).
- **تأشير كمكتملة** — a grade may only be set if the task defines one
  (`tasks.grade`) and can never exceed it.
- **تعديل** — notes + grade on an existing instance, same grade rule.

Not ported to web at the time: the QR-scanner modal (deferred to Flutter)
and the print views.

**Doctor task progress ("تقدم مهام الطبيب", 2026-08-19)** — the
per-doctor **browsable** progress screen
(`admin/doctor_task_progress.php`), distinct from the session-wide
aggregate stats page. `DoctorTaskProgressController@show`
(`GET /doctors/{doctor}/progress`) groups all of a doctor's session-scoped
`task_instances` by `task_id`, each with `required_count`/`completed`/
`remaining`. **A real bug fixed here**: legacy's "uncomplete" action clears
`completion_date` back to `NULL` when reverting `completed → assigned`; the
ported `TaskInstanceController::update` only ever *set* the date, never
cleared it — leaving a stale completion timestamp on a no-longer-complete
instance. Fixed in both web and API controllers. Access matches legacy
exactly: `super_admin`/`admin` only, not `editor`.

**Full matrix ported to Flutter (2026-08-23)** — Flutter's original
"تقدم المهام (NFC)" screen was deliberately scoped small (scan → resolve
doctor → single unambiguous pending task). The user asked for full parity
with the web's day → education-type/stage → group → department (tabs) →
doctor (expandable) → task-card matrix, with NFC folded into the doctor
search box as an alternate input rather than a separate screen. No API
existed for this (`Api\TaskProgressController` only had `nfcScan()`/
`start()`); rather than duplicate `index()`'s filter query and `group()`'s
matrix logic, **three shared services were extracted** and are now called
by both the web and API controllers:
- `App\Services\TaskProgressFilters` — the day/education-type/stage/group
  query.
- `TaskProgressGroupSummary` — the department-tabbed doctor/task-card
  matrix.
- `TaskInstanceGrader` (+ `TaskGradeException`, mirroring `TaskStarter`/
  `TaskStartException`'s shape) — the shared "a grade can't exceed the
  task's own grade" rule.

`Api\TaskProgressController` gained `filters()`/`group()`/`complete()`/
`updateInstance()`, thin delegations to the same services, gated by
`permission:task_progress,{view,finish}`. The web page was
regression-tested end-to-end after the refactor to confirm unchanged
behavior.

Flutter's `task_progress_screen.dart` replaced `nfc_lookup_screen.dart`
(removed) at `/admin/task-progress`. Every department tab shares one search
box (leading search icon, trailing NFC icon) filtering the doctor list
client-side, expandable doctor rows with the same three actions as web. A
real layout bug was found live: the fixed filter row plus header/tabs/
search box no longer fit once the keyboard opened for a group's detail view
(`BOTTOM OVERFLOWED BY 121 PIXELS`) — fixed by hiding the filter row once a
group is selected.

**Two real bugs, reported live by the user (2026-08-23)**, found by
reproducing the exact report rather than guessing:
1. The home-dashboard shortcut still pushed the old, now-removed
   `/admin/task-progress/nfc` route — `GoException: no routes for
   location`, making the feature entirely unreachable from the home
   screen. The admin hub's own tile had been updated when the screen was
   replaced; this second reference was missed. Fixed by pointing it at
   `/admin/task-progress`.
2. The stage filter dropdown could show a stale, invalid selection after
   changing education type — `DropdownButtonFormField`'s `initialValue` is
   read once at first build, not on rebuild, so an *external* reset (changing
   education type resets `stageId` to `null` and swaps the stage list) left
   the widget still showing the old value. Same bug class as an earlier
   appointment-form fix this session. Fixed with
   `key: ValueKey('stage-field-$educationTypeId')` to force a clean reset.

### NFC doctor lookup

**Backend (web side)**: `nfc_tag_id` on the doctor record, resolved via
`nfcScan()`; a real bug found and fixed there — a blank `nfc_tag_id`
normalized to `''` instead of `null`.

**Flutter (2026-08-23)**: added `nfc_manager` (pinned at 4.1.1 by this
project's SDK constraint). Two integration points: scanning a tag to fill
`nfc_tag_id` on the doctor create/edit form, and (originally) a standalone
lookup screen later folded into the Task Progress search box (above). UID
extraction reads the real installed package source directly
(`NfcTagAndroid.from(tag)?.id`) rather than trusting the pub.dev docs'
suggested per-tech fallback chain — a simpler, tech-agnostic path was found
by inspection. Shared via `core/nfc/nfc_uid_reader.dart`.
`android.permission.NFC` + a **non-required** `android.hardware.nfc`
feature flag were added so the app still installs on non-NFC devices.

**A genuine hardware fault, not a code bug**: on the connected POS
terminal, `checkAvailability()` never returned `enabled` —
`adb shell dumpsys nfc` showed the state stuck at `turning on`, and
`adb logcat` traced it to the device's NFC HAL failing to talk to its own
controller chip (`Failed to send header` from the bootloader handshake).
Unlike the printer's earlier AIDL failure, there's no software fallback for
read-only NFC tag hardware — flagged plainly as backend-verified and
code-reviewed but not physically tap-tested on this unit, rather than
claimed as working.

**NFC alongside search on Doctors/Groups admin lists (2026-08-25)**: added
`Api\DoctorController::nfcLookup()` (`GET /doctors-nfc-lookup?tag_id=...`)
— a lighter, reusable twin of `nfcScan()` without the pending-task-shortcut
logic irrelevant to an admin list. Also added `doctor_id` as a filter on
`Api\GroupController::index()` (a card scan can't match a *group name*, so
it's a separate, combinable filter). On the doctor list, a scan sets the
search text *and* jumps the education-type/stage dropdowns to match; on the
group list (which can't search by doctor name meaningfully) a scan sets a
`_doctorId` filter shown as a removable chip instead.

**Cascading filters + search added across Doctors/Groups/Taxonomy admin
(2026-08-25, Flutter)**: the user's report that "picking a stage should
only show stages under the chosen education type" turned out to be a real
existing bug in two places — the taxonomy department dialog's stage
dropdown, and the doctor form's stage dropdown — both fed the full
unfiltered list. Fixed both with the same cascade pattern already used by
the Tasks form. Also newly added (not bug fixes): search on the group list
(didn't exist anywhere before, web or API — required a new `search`
`when()` clause on `Api\GroupController::index()`), a UI-only education-type
field on the group form, and search+filters on the taxonomy list itself
(client-side, since the lookup endpoints return their whole small table).
`Api\DoctorController::index()` was also found missing `education_type_id`/
`stage_id`/`username`-search filters that the web controller already had —
ported verbatim. The shared cascade widget was extracted from
`task_list_screen.dart`'s private implementation into public
`core/widgets/cascading_dropdown.dart`, now used by 5 screens.

## Groups

A group belongs to one required `stage_id` and optionally one
`academic_session_id` (nullable — legacy/global groups with no session
appear under every session, via the same `OR NULL` idiom). **Business rule,
ported then corrected**: a doctor belongs to only one group at a time,
enforced at the application layer (delete-then-insert on
`doctor_group_members`, not a DB constraint) — originally ported as a
global "one group ever" rule that silently destroyed prior-year membership
(see "Doctors, groups and tasks tied to an academic session" above); now
"one group per academic session." Only the modern multi-select
doctor-management flow was ported; an older single-add form the legacy app
had already superseded was deliberately not ported. A separate, unrelated
legacy day-of-week doctor-rostering feature (`admin/groups.php`,
`doctor_groups` table) is not this module and was not touched.

**Admin screens rebuilt to match the legacy app (2026-08-19)**:
- **إدارة الأطباء** (`Doctors/Index.vue`): filter row (education type →
  cascading stage select, debounced search now also matching `username`);
  a real bug fixed — the search's `orWhere` chain sat beside the
  scope/filter constraints unparenthesized, so a search could **break out
  of the education-type/stage filter and the permission scope entirely**;
  wrapped in a nested `where(...)`. Row selection + bulk delete
  (`DELETE /doctors-bulk`) added, matching the legacy app's bulk action
  which the earlier port lacked.
- **إدارة المجموعات** (`Groups/Index.vue`): the same filter row, plus
  legacy's behavior of listing nothing until a filter is actually applied;
  inline add-group form with repeatable day/time slot rows (Sunday–Thursday);
  group card with per-group doctor search, تحديد الكل, bulk removal, and
  an "إضافة أطباء للمجموعة" modal listing only doctors currently in no
  group.

**Phase 3 admin (Flutter, 2026-08-21)**: `Api\GroupController` (full CRUD +
`availableDoctors`/`addDoctors`/`removeDoctors`) already existed;
built the Flutter weekly-slot editor and member add/remove against it as-is
(needed a new `ApiClient.deleteJson()` extension for a `DELETE` with a
request body). One pre-existing gap noted and left out of scope at the
time: `groups` API routes carried no `role:`/`permission:` gate at all,
unlike other admin resources.

## Permission matrix

`app/Http/Middleware/EnsureUserHasRole.php` (`role:...`) is the coarse gate
on `routes/web.php` — which *pages* a role can reach at all (any
authenticated user → dashboard/profile; `super_admin`/`admin`/`editor` →
doctors/patients/tasks/task-instance actions; `super_admin`/`admin` only →
education-types/stages/departments/activity-logs/permissions/
department-roles). `permission:module,action`
(`EnsureUserHasPermission`) is the finer-grained layer on top — which
*actions* a specific user can take within a page they can already reach.

**Table audit (grepped the entire legacy codebase for real reads/writes,
not guessed)**:

| Table | Status | Ported? |
|---|---|---|
| `user_permissions` | Live — per-user module/action grants, read by 14+ real legacy pages | Yes — `UserPermission` + `PermissionManager` |
| `department_role_assignments` | Live, real data — senior/HR role per department+stage | Yes — `DepartmentRoleAssignment` |
| `department_role_activity_log` | Live audit trail, written but never read back | Yes, logged here too |
| `user_allowed_departments`/`_stages`/`_education_types` | Live — read by `scope_helper.php` | Yes — `ScopeHelper` (pure composite-key pivots, no `id`) |
| `roles`, `permissions`, `role_permissions` | Orphaned parallel system — used only by a self-contained legacy CRUD screen; real access control never reads them | No |
| `department_permissions` | Dead, 0 rows | No |
| `role_stage_department_permissions` | Dead, 0 references, 0 rows | No |
| `user_stage_department_permissions` | Has data but zero PHP reads/writes it — orphaned | No |

**A real bug in the legacy app, fixed here**: `department_role_assignments`
has two redundant status columns, `is_active` and `status`. Legacy's admin
UI only ever writes `status`, but three of its own read paths filter on
`is_active` while `PermissionManager::hasDepartmentRole()` filters on
`status` — so deactivating a role via the UI didn't actually revoke it
everywhere. `DepartmentRoleAssignment` here treats `status` as the single
source of truth and syncs `is_active` on every save via a `saving()` hook.

**Matrix corrected to the legacy definition (2026-08-19)** — checked
against `get_user_permissions.php`, the earlier port was wrong three ways:
wrong module list (7 modules, 3 invented — `appointments`/`dental-charts`/
`payments` aren't real modules; `dashboard`/`users`/`groups`/`stages`/
`task_progress`/`reports`/`settings` were missing entirely); uniform
`view/create/edit/delete/export` actions instead of legacy's real
**per-module** action sets (`task_progress`: view/view_all/export/start/
finish/open_case_sheet; `tasks`: +assign; `reports`: view/export/print;
etc. — 44 grant pairs total, now `App\Support\PermissionMatrix`, copied
verbatim from the legacy definition); and grants that enforced nothing —
now wired to the actual routes (`task_progress` view/start/finish on the
admin task-progress screen, `groups` view/create/edit/delete, `stages`
CRUD, `settings` view/edit).

**A latent bug in the legacy app, found but deliberately not reproduced**:
four legacy places check `task_progress.edit`, but `task_progress` has no
`edit` action in its own matrix — it can never be granted. Three of those
checks read `finish || edit` (so they still work via `finish`), but
`admin/ajax/update_task_status.php` checks `edit` alone — permanently
denying every non-super_admin. This port gates the equivalent action on
`finish` instead, matching the effective (working) behavior rather than the
broken literal one.

**Extended to every action on every module (2026-08-19)** — originally only
`destroy` was gated on 6 resources; extended to view/create/edit/delete (+
export on doctors) across every module in `UserPermissionController::MODULES`,
mirrored onto `routes/api.php` (which had **zero** `permission:` gating
before — a Flutter client could bypass every grant a web session was
blocked by). Also found: `departments` had been in the module list since
the matrix was built but **no route ever actually checked it** — fixed. A
real behavior change worth noting: because `PermissionManager::can()` only
bypasses for `super_admin` (not plain `admin`), non-super `admin` accounts
now need explicit grants for view/create/edit too, not just delete.

Two more bugs found in the same pass: `EnsureUserHasPermission` would
`TypeError` (instead of cleanly 403ing) if a `Doctor`-token Sanctum
principal hit a newly-gated API route, since `PermissionManager`'s
constructor requires a `User` — fixed by checking `instanceof User` first.
And `Route::resource('appointments', ...)` registered a `show` route with
no matching controller method — never triggered, but fixed by excluding
`show` from that resource (its `Api\AppointmentController` counterpart does
implement it, left alone).

### Access-scope restriction (the 4th permission dimension)

**Added 2026-08-21**: alongside the legacy app's three scope dimensions
(department/stage/education-type — see Taxonomy section), a fourth was
added from scratch: which academic years a staff account may see at all.
**A pre-existing gap found while building this**: the three original
dimensions already had working setters
(`ScopeHelper::setAllowedDepartments()` etc.) and correctly-filtering
`scopeX()` readers — but a repo-wide search found **no call site for any of
the three setters**. There was no UI anywhere to actually restrict a user,
ever. Fixed by building `Permissions/Edit.vue`'s "نطاق الوصول" section
covering all **four** dimensions together as multi-select checkbox lists,
each with a clear "بلا قيد — يرى الكل" indicator when empty (matching
`ScopeHelper`'s "zero rows = unrestricted" rule as a state to *display*,
not just an accident of no selection).

`user_allowed_academic_sessions` (composite PK, no surrogate id, no
timestamps, no FK constraints — shaped to match its three siblings exactly).
**One deliberate difference**: `scopeAcademicSessions()` includes
`NULL`-session rows even for a restricted user (the other three don't) —
`academic_session_id` nullable means "visible under every year," and
restricting sessions shouldn't hide session-less data the other three
dimensions have no equivalent escape hatch for.

Wired into the same call sites the other three dimensions use
(`DoctorController`, `DoctorPrintController`, `GroupController`,
`TaskProgressController`, and their `Api\*` mirrors) — deliberately *not*
into `TaskController`/`GroupController::availableDoctors()`, which were
never scoped by any of the three original dimensions either. This is a
second, independent filter from the navbar's "which session am I currently
viewing" switcher — a permission stacked on top of a viewport, not a
replacement for it.

**Exposed to the Flutter permissions screen (2026-08-30)**, closing a gap
the original Phase 3 admin pass had left open by explicit design (see
below): `Api\UserPermissionController::show()` gained `scope_options`/
`scope`, `update()` gained a validated `scope` object, both calling the
same `ScopeHelper::setAllowed*()` methods the web controller calls — no new
backend logic, just parity. Flutter added four new
`_ScopeDimensionTile`s to the permission edit screen.

## Web ↔ Flutter parity notes

**Phase 3 admin build-out (2026-08-21)** brought the Flutter admin app up
to CRUD parity across this whole subsystem:
- **Doctors/Tasks/taxonomy**: `education-types`/`stages`/`departments` were
  API-read-only before this (`Api\LookupController`); added
  `store`/`update`/`destroy` for each, direct ports of the matching web
  controller methods, gated identically to the web routes (read directly
  from `routes/web.php` rather than assumed — worth noting `departments`'
  gate only exists because of the earlier "was in MODULES but never
  actually checked" fix).
- **Groups**: no backend changes needed, `Api\GroupController` already had
  full CRUD.
- **Academic sessions**: only `setCurrent` was missing relative to the web
  controller; the web's `select()` (browser-session "viewing" state) was
  deliberately not ported — Sanctum is stateless, no equivalent.
- **Case sheet types**: no backend changes needed (full detail belongs to
  the case-sheet-types doc, not this one) — `destroy` already correctly
  422s when a task still references the type.
- **Permissions**: `Api\UserPermissionController` had `show`/`update` but no
  `index`; added, mirroring the web controller's user-listing query
  exactly. The web controller's scope-restriction handling was
  deliberately *not* ported yet at this point (flagged explicitly in the
  controller's docblock) — that gap was closed later, 2026-08-30, above. A
  real RTL bug was found and fixed along the way: a `"$granted / $total"`
  count label rendered with both numbers swapped inside the app's Arabic
  context (Unicode bidi reordering two numbers joined only by a neutral
  separator) — the same root cause also affected the academic-sessions
  admin's date-range display and was fixed identically in both places.

Across nearly every entry above, the pattern holds: shared services
(`TaskProgressFilters`/`TaskProgressGroupSummary`/`TaskInstanceGrader`,
`AcademicSessionHelper`, `ScopeHelper`, `PermissionMatrix`) are extracted
once and called by both the web (Inertia/Vue) controllers and the
`Api\*` controllers Flutter talks to, specifically to avoid the
decimal-cast/scoping/edge-case drift bugs this project repeatedly found
when logic was duplicated between the two clients.
