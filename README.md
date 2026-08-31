# Dental Clinic — Laravel + Inertia (Vue) Rewrite

Rebuild of the `dental_clinics2` PHP application on Laravel 12 + Inertia.js +
Vue 3 + Tailwind, using the real `clinic_system2` database schema, plus a
versioned JSON API (Sanctum) for a future Flutter (Android/iOS) client.

Local dev URL (web app): `http://localhost/dental_laravel/public`
Local dev URL (API base): `http://localhost/dental_laravel/public/api/v1`

**LAN access (test from a phone on the same Wi-Fi)**:
`http://192.168.1.155/dental_laravel/public` — this machine's current local
IP; verified reachable (Apache binds `0.0.0.0:80`, not just `127.0.0.1`;
Windows Firewall has an inbound-allow rule for "Apache HTTP Server"/"XAMPP
HTTP" on port 80). Laravel's asset URLs resolve against the *request's own*
host, not a hardcoded `APP_URL` — confirmed by curling this address
directly: CSS/JS tags correctly came back as `192.168.1.155/...`, not
`localhost/...`, so pages render correctly from another device without any
config change. This IP changes if the machine reconnects to Wi-Fi or moves
networks — re-check with `ipconfig` if it stops working.

This file is the living technical reference for the rebuild — kept accurate
as modules are added. When in doubt, this describes what is **actually
implemented and verified**, not a plan.

## Stack

- Laravel 12, PHP 8.2
- Inertia.js + Vue 3 + Tailwind (Laravel Breeze scaffold)
- Laravel Sanctum — token auth for the JSON API
- MySQL/MariaDB, database `dental_laravel` (separate from the original PHP
  app's live `clinic_system2` database — nothing here touches that data)

## Login (web)

```
email:    admin@clinic.test
password: password
```
Role: `super_admin`. Change before any real deployment.

## Auth model — two separate guards

The original PHP app has two independent login systems (staff vs. doctors).
This rebuild keeps that separation:

| Guard | Table | Web login | API login |
|---|---|---|---|
| `web` (default) | `users` | `/login` (session) | `POST /api/v1/login` (Sanctum token) |
| `doctor` | `doctors` | `/doctor/login` (session) | `POST /api/v1/doctor/login` (Sanctum token) |

`users.role` is an enum: `super_admin`, `admin`, `editor`, `doctor`,
`accountant`, `senior`, `hr`. The `doctor` role value on `users` is currently
unused by any guard — doctor identity/auth goes through the separate
`doctors` table and `doctor` guard, not a `users` row with `role=doctor`.

Both `User` and `Doctor` models use Sanctum's `HasApiTokens`, so a single
`auth:sanctum` middleware authenticates either kind of token — Sanctum
resolves the token to whichever model created it (polymorphic
`personal_access_tokens.tokenable`), independent of the `config/auth.php`
guard/provider wiring used for session auth.

**A real config bug caught by testing, not by reading**: `config/auth.php`
defined the `doctor` guard with `'provider' => 'doctors'`, but the
`providers.doctors` entry itself was never added — so any code path that
actually resolved the `doctor` guard (as opposed to Sanctum, which doesn't
use this config at all) threw
`SessionGuard::__construct(): Argument #2 ($provider) must be of type
UserProvider, null given`. This went unnoticed through the whole
API-only phase of this build, because Sanctum guards don't touch
`config/auth.php` guards/providers — it only surfaced once the doctor web
login (below) started actually exercising the `doctor` session guard.
Fixed by adding the missing `providers.doctors` entry
(`driver: eloquent, model: Doctor::class`).

## Task progress: full matrix ported to Flutter, three shared services extracted (2026-08-23)

Flutter's "تقدم المهام (NFC)" screen was a small, deliberately scoped
standalone feature (scan a tag → resolve a doctor → offer a single
unambiguous pending task). The user asked for it to go back to full
parity with this web page's own day → education type/stage → group →
department (tabs) → doctor (expandable) → per-slot task-card matrix,
with NFC folded in as the doctor search box's alternate input (tap to
scan instead of typing) rather than a separate screen — the same
supporting role this page's own QR-scan modal already plays here.

No API existed for any of this — `Api\TaskProgressController` had only
`nfcScan()`/`start()`. Rather than write a second copy of `index()`'s
filter-building query and `group()`'s department/doctor/task-card
matrix (the more error-prone path, and the reason this project keeps
finding decimal-cast and other drift bugs between duplicated logic),
extracted three services this controller and the new API endpoints both
call: `App\Services\TaskProgressFilters` (the day/education-type/stage/
group query), `TaskProgressGroupSummary` (the department-tabbed
doctor/task-card matrix), and `TaskInstanceGrader` (+ `TaskGradeException`,
mirroring `TaskStarter`/`TaskStartException`'s shape — the shared
"a grade can't exceed the task's own grade" rule `complete()`/
`updateInstance()` both enforce). This controller's four methods are now
thin wrappers around those services; behavior is unchanged, and the web
page was regression-tested end-to-end after the refactor (curled
`/task-progress/groups/{id}` and loaded `/task-progress` directly) to
confirm that.

`Api\TaskProgressController` gained `filters()`/`group()`/`complete()`/
`updateInstance()`, all thin delegations to the same services, gated by
the same `permission:task_progress,{view,finish}` rules as their web
counterparts. Full Flutter-side detail in `flutter_app/README.md`.

The user asked that education types, stages, departments, tasks, and
task progress all gate view/create/edit/delete by granted permissions,
"as in dentalclinic". Researched via two Explore agents (the original's
`PermissionManager`/`user_permissions` system, and this rebuild's
`PermissionMatrix`/`EnsureUserHasPermission`) before touching anything —
**four of the five turned out to already be done**: `stages`,
`departments`, `tasks`, and `task_progress` are already in
`PermissionMatrix::modules()` with `permission:{module},{action}`
middleware layered on every route action, verified directly by reading
the current `routes/web.php` rather than assumed from an earlier
session's memory.

Only `education-types` was missing — and confirmed via the original
app's own `get_user_permissions.php` that this isn't a restorable gap:
the original never gave education types its own permission module
either (its page only checks `stages`/`view`; its own create/edit/
delete AJAX has no permission check at all beyond being logged in).
Asked the user how to handle that specific inconsistency rather than
silently picking one interpretation — confirmed: give it a real module
(view/create/edit/delete) matching how `stages`/`departments` already
exceed the original's actual enforcement in this rebuild, rather than
replicate the original's own unguarded create/edit/delete.

Added one entry to `PermissionMatrix::modules()` (`education_types` —
underscore, matching the existing `task_progress` module-key vs.
`task-progress` URL-slug split) and wired the same
`->middlewareFor('index'|'store'|'update'|'destroy', 'permission:education_types,...')`
chain already used by `stages`/`departments` onto the `education-types`
resource route. No migration, no `UserPermissionController`/
`Permissions/Edit.vue` change needed — `user_permissions` has no fixed
module list to extend, and the Permissions screen already renders
whatever `PermissionMatrix::forUi()` returns dynamically (confirmed
live: a test `admin`-role user with no `education_types` grants got a
403 on `GET /education-types` that previously succeeded; granting all
four permissions via `UserPermission::updateOrCreate` — the same rows
the real Permissions screen writes — then let every action through;
`PermissionMatrix::forUi()` was confirmed to already include the new
module's Arabic labels with zero Vue changes). Test user and grants
deleted afterward.

## Tasks: education-type cascade in the form, filter carry-over, and an أساسية/اختيارية flag (2026-08-23)

Three related requests about the Tasks module, ported to both the web app
and `flutter_app/README.md` (see that file's matching entry for the
Flutter side).

- **New column**: `tasks.is_required` (boolean, default `true`) — نوع
  المهمة, أساسية (mandatory) or اختيارية (optional). Didn't exist in any
  form before (confirmed via grep; `required_per_doctor`/`required_count`
  are unrelated completion counts). Defaults `true` so every existing
  task — implicitly mandatory today, there being no other option —
  keeps its current effective meaning with no data migration needed.
- **Education-type dropdown added to `Tasks/Create.vue`/`Edit.vue`** —
  neither had one before; only an unfiltered stage select. Mirrors the
  cascade `Tasks/Index.vue` already had (education type narrows which
  stages are selectable) — this is UI-only, exactly like `Index.vue`'s:
  `tasks` has no `education_type_id` column and never will, so it's
  never sent to the server. `Edit.vue` derives the initial education type
  from the task's existing stage (a task doesn't store one directly),
  the same trick `Index.vue` already used for surviving a page reload.
- **"Add Task" now carries the list's active filter over** — if a stage
  (and education type) is selected on `Tasks/Index.vue` when "Add Task"
  is clicked, the create form opens with both pre-selected; with no
  filter active, both start empty and are picked manually, exactly as
  before this existed.
- **A real bug found during verification**: `Api\TaskController::store()`
  returned `is_required: false` in its immediate JSON response when the
  field was omitted from the request — even though the column's DB
  default is `true`, and a fresh `GET` of the same task correctly showed
  `true`. Cause: `Task::create()`'s returned in-memory model never learns
  about a column's DB-level default when that column wasn't in the
  attributes passed to `create()` — accessing it then returns `null`,
  and `TaskResource`'s `(bool) $this->is_required` turned that `null`
  into `false`. Fixed with `$task->refresh()` right after `create()`,
  which re-reads the row the insert just wrote, closing the gap for
  every column with a DB-level default, not just this one. Confirmed via
  curl before and after: `POST /api/v1/tasks` without `is_required` now
  correctly returns `true` immediately, matching the fresh-fetch result
  it already matched before the fix.

## Case-sheet printing (2026-08-19)

Port of the original's `doctor/*_print_html.php` family — nine standalone
print pages (34–150 KB each) reached from a "Print" button that each case
sheet shows only once a record exists (`<?php if ($existing_chart): ?>`),
opened with `window.open(..., '_blank')` and carrying either
`task_instances_id` or the record id.

**What the original's design actually is**, read off its own `<style>`
blocks rather than eyeballed: `@page { size: A4 }` with a 5–10mm margin,
`"DejaVu Sans"` at ~9pt, `#000` hairline borders on every table cell, grey
(`#f0f0f0`) `.section-title` bars with a 1px border, a letterhead carrying
the clinic logo top-left and the university logo top-right with
university/college names centred between them, a department line beneath it,
a two-column strip of `Label: value` cells, bordered boxes for narratives, a
signature footer, and a floated QR captioned "Scan the QR code to reopen this
case sheet." A sticky on-screen `.print-controls` bar (طباعة / رجوع) is
hidden by `@media print`, and its `goBack()` closes the tab when it was
opened via `window.open`, else navigates back to the sheet.

**One document, not nine.** The nine originals restate that design
independently, which is exactly why they drifted: margins of 5/8/10mm, body
text of 9/9.5/10pt, and **two of the nine (oral medicine, prosthodontics)
have no QR block at all**. Here the design lives once in
`resources/views/print/case-sheet.blade.php` and the content is generated
from the same `App\Support\*Form::sections()` definitions the on-screen
sheets already render from, via `App\Support\CaseSheetPrintRenderer`. A
field added to a sheet now appears on its printout automatically; in the
original that needed a second, separately-maintained file that could
silently disagree with the form.

`App\Support\CaseSheetPrint` is the registry — model, layout class, `<title>`
and department line per sheet, all copied verbatim from the corresponding
`*_print_html.php`:

| Resource | Title | Department line |
| --- | --- | --- |
| `dental-charts` | Operative Case Sheet | Department of Conservative |
| `prosthodontics-records` | Partial Denture Case Sheet | PROSTHODONTIC |
| `complete-denture-records` | Complete Denture Case Sheet | PROSTHODONTIC |
| `surgeries` | Surgical Case Sheet | Department of Oral & Maxillofacial Surgery |
| `periodontal-charts` | Periodontal Chart | Department of Periodontics |
| `orthodontics-records` | Orthodontics Case Sheet | Dentistry Department (Orthodontics) |
| `prevention-records` | Prevention Case Sheet | Department of Preventive Dentistry |
| `oral-medicine-charts` | Facial Pain and TMJ Disorders Case Sheet | *(in the letterhead: Dept. of Oral Diagnosis/Oral Medicine Clinic)* |

Oral medicine is the one sheet that prints its department inside the
letterhead block instead of as a separate sub-header
(`oral_medicine_print_html.php:499`), so the registry carries that as a
distinct `headerDepartment` key rather than flattening the difference away.

**Formatting rules** were taken from what the originals emit, not invented:
booleans print `Yes`/`No`; selects print the option **label**, never the
stored value (`Female`, not `female`); dates are trimmed out of the ISO
datetimes Eloquent serialises; tooth pickers print their comma list
normalised and upper-cased; `textarea` fields print inside a bordered box on
their own row while short fields pack two per row; `file` fields are skipped
(a stored upload path on paper is meaningless, and the originals never print
them). **Empty fields still print their label** — a printed case sheet is a
form a supervisor writes on, so dropping blank rows would be wrong.

**The periodontal tooth grids are rendered server-side, deliberately
diverging from the original.** `periodontal_chart_print_html.php` builds its
BOP/PPD/CAL tables in JavaScript at print time from the `chart_data` JSON —
its server-side `renderDentalChart()` is a stub that `return ''`s
(line 373-376). A printout whose content depends on a script having already
run is the one thing that shouldn't be left to chance, since Ctrl+P can fire
first. `CaseSheetPrintRenderer::charts()` emits the same grid (16 upper +
16 lower teeth in FDI order, 3 buccal + 3 palatal/lingual sites per tooth,
the exact shape `PerioChart.vue` stores) as static HTML.

**Access control** matches the original's own check at the top of every
print page (`if (!isset($_SESSION['doctor_id']) && !isset($_SESSION['user_id']))`
plus a per-record owner test): a doctor may print only their own sheet;
staff need `task_progress.open_case_sheet` — the same permission that gates
*opening* a sheet, so printing can't be a way around it. Verified for all
four principals: owning doctor → allowed, other doctor → 403, super_admin →
allowed, staff without the permission → 403; unknown sheet key → 404.

`/api/v1/case-sheet-prints/{resource}/{record}` returns the same document as
JSON — letterhead, sections already resolved to label/value pairs, tooth
grids, stage rows — so the Flutter client lays out the identical document
without reimplementing the formatting rules.

## The same mobile-scroll bug in a second, older component (2026-08-21)

Reported with a screenshot: the "قوائم سريعة" chip pickers (the plain
tooth-number grid used for `non_vital_teeth`/`missing_teeth`/
`crown_bridge_teeth`) were cramped and sliced off at the edge on a phone,
with no way to scroll to the missing columns.

This is `Components/QuadrantTeeth.vue`, not `ToothOdontogram.vue` — a
different, older component the odontogram fix earlier in this session never
touched. Same root cause, verified before fixing rather than assumed from
the resemblance: its outer wrapper had **no** `overflow-x-auto` at all (not
broken, just absent), and its flex rows had no explicit width, so a narrow
screen compressed the sixteen number buttons per quadrant-pair instead of
letting them overflow. Fixed the same way — `w-max` on the row, `shrink-0`
on every button, `overflow-x-auto` plus `-webkit-overflow-scrolling: touch`
on the wrapper.

`QuadrantTeeth.vue` is shared by six sheets (`type: 'teeth'` fields in
`OperativeForm`, `CompleteDentureForm`, `OralMedicineForm`,
`OrthodonticsForm`, `ProsthodonticsForm`, `SurgeryForm` — confirmed by
grep), so this one fix corrects every one of them on mobile, not only the
operative sheet the screenshot was taken from. `PerioChart.vue` was checked
too and already had the correct `overflow-x-auto` + `min-w-max` pairing —
no fix needed there.

## Odontogram fixes, and the missing Endodontics section (2026-08-21, follow-up)

Three concrete reports against the odontogram just added: no tooth box in
the editing modal, no "iOS-style" Endodontics section, and the tooth grid
not scrollable horizontally on mobile.

**Horizontal scroll.** `overflow-x-auto` on the container was already
there, but a flex row with no explicit width doesn't overflow — it shrinks
its children to fit, which is exactly what was happening: 16 teeth per arch
squeezed down to fit a phone screen instead of overflowing it. Fixed with
`w-max` on the row (its natural, un-shrunk width) plus `shrink-0` on every
tooth button (stops the browser's default flex-shrink squeezing them
individually) — the row now genuinely overflows and the container scrolls
it, with `-webkit-overflow-scrolling: touch` for momentum scroll on iOS.

**The tooth box.** The original's editing modal shows a large live SVG of
the tooth being edited (`#modalToothSvg`) — clicking a surface *on that
box* is how the original selects which surface to set a status for. The
first version of the modal only had the text/button surface list below,
with no visual box at all. Added: a 140×140 rendering of the same
target-pattern SVG the main grid uses, live-coloured from the tooth's
current data, with its polygons clickable — clicking one scrolls the
matching surface row into view below rather than requiring the doctor to
find it in the list.

**Endodontics — a whole section that didn't exist yet.** Not a styling
gap: `App\Support\OperativeForm` had zero fields for `endodontics_data`,
confirmed before writing anything. The original's "Endodontics Treatment
Record" card (operative.php) is substantial — tooth no., canal count,
diagnosis, three visits (access opening/pulp extirpation/10-canal working-length
table; instrumentation/10-canal WL-size-RP table/technique; obturation
master-cone and final-fill checks), gated behind an iOS-style toggle
(`.ios-toggle`, exact 51×31px track / 27×27px knob / `#34c759` on-colour,
copied from the original's own CSS, not approximated).

Rebuilt as three components: `IosToggle.vue` (the switch itself),
`EndodonticsCanalTable.vue` (the 10-canal table, shared by both visits that
use it — same canal ids/labels as the original's own `$canals` array,
different columns per visit), and `EndodonticsSection.vue` (the full card).
Wired into `OperativeForm` as a new `endodontics` field type bound to
`endodontics_data`, which — like `tooth_data` — carries a real Eloquent
`'array'` cast, so it round-trips as a plain object with no manual
(de)serialisation (same reasoning as the odontogram's own cast handling,
applied consistently here rather than re-copying the text-column pattern by
mistake a second time).

**Deliberately not ported, and said so rather than left silently
missing**: the per-visit image upload galleries (`endodontics_images`, three
separate multi-file widgets with their own gallery UI) and the canvas-based
signature pad. Both are substantial features of their own — a real
file-upload/delete/gallery flow, and a signature-capture widget — out of
scope for this pass. The signature is a plain text field here instead of a
drawn one; there's nowhere yet to attach an image.

Verified end-to-end: real endodontics data (tooth no., canal count,
multi-value diagnosis/technique lists, both canal tables, third-visit
notes) saved and read back through the real controller with no
double-encoding, same check the odontogram itself needed; the odontogram
itself re-tested after the modal/scroll changes to confirm no regression.
No test data left in the database.

## The real odontogram, and the doctor's missing print/QR buttons (2026-08-21)

Reported from a doctor account: "the forms differ completely from
dentalclinic, and the dental charts differ from it too" — followed by "no
print button, no QR in the forms". Both traced to real, verified gaps.

### The dental chart was never actually built

`dental_charts.tooth_data` — the column behind the operative sheet's real
odontogram — existed and was imported with real data (see the legacy data
import above), but **nothing in this app read or wrote it**.
`App\Support\OperativeForm` had no field for it at all. What stood in for
"the tooth chart" on screen was `QuadrantTeeth.vue`, the simple chip-picker
used for narrower fields elsewhere (`non_vital_teeth`, `missing_teeth`,
`crown_bridge_teeth` — comma lists of tooth numbers) — a fundamentally
different, much smaller feature than a real per-surface odontogram. This is
what "the dental charts differ completely" meant: the centerpiece feature of
the operative sheet was simply missing, not styled differently.

Read directly out of the original's own `operative.php` (its `<style>`
block and `updateToothVisualStatus()`/`surfaceStatusOptions`/
`rootStatusOptions`, not guessed) and verified against real imported
`tooth_data` rows for the exact JSON shape:

- 32 teeth, each with five clickable surfaces in the original's "flower"
  target layout (a 30×30 polygon set: top/left/bottom/right/center), or
  three root surfaces (root-1/2/3) once marked non-vital.
- Six tooth-level statuses (present, non_vital, missing, extracted,
  retained_root, crown), five surface statuses (healthy, cavity, filling,
  crown, bridge), four root statuses (healthy, root_canal, infected,
  treated) — same vocabulary and same colours as the original's CSS
  (`.cavity{fill:#ffc107}`, `.root-canal{fill:#dc3545}`, etc.).
- Data shape: an array of `{number, position, notes, status, toothStatus,
  polygons}`, only touched teeth present — confirmed against real rows
  rather than assumed.

Rebuilt as `Components/ToothOdontogram.vue` — a genuine interactive
odontogram (not the chip picker), wired into `OperativeForm` as a new
`dental_chart` field type, with its own status-editing modal per tooth. The
three original chip-picker fields were kept alongside it (`قوائم سريعة`) —
real columns, already correctly working, not worth removing.

**A double-encoding bug caught before it shipped.** `DentalChart::tooth_data`
carries a real Eloquent `'array'` cast (unlike the periodontal sheet's
`chart_data`, a plain text column with no cast). The first version of this
work copied the periodontal pattern — manually `JSON.stringify()` the value
before posting — which is exactly wrong for a cast column: Eloquent
`json_encode()`s whatever's assigned, so a pre-stringified value gets
encoded *again*, storing an escaped string instead of the array. Caught by
an actual round-trip test (save through the real controller, read the raw
column back) rather than assumed correct from the code alone; fixed by
posting the plain array and letting the cast do its job, both client-side
and in the controller's validation (`'array'`, not `'string'`, for this
field type).

**Printing extended to match.** `CaseSheetPrintRenderer::dentalChart()`
prints a compact table of the marked teeth (number, status, surface
details, notes) — the original's print page builds the same `teethDetails`
summary and renders a small static chart from it; a text table carries the
same information without a second SVG renderer duplicated in Blade.

### The QR button didn't exist; the original's own version doesn't work

The print button did already exist (added in earlier work) but only
appears once a sheet has been saved — same condition the original uses
(`<?php if ($existing_chart): ?>`). The doctor account first handed over
for testing happened to have **zero** saved case sheets among its task
instances (confirmed against the source data: most of its "completed" task
instances have no linked case-sheet row at all — genuine source data
quality, not an import gap), so it never had anything to show a print
button for.

The QR button was a real, total gap: it never existed anywhere in this
app. Rebuilt as a themed modal (same pattern as the doctor's existing
"رموز المهام المعلقة" page) reachable via a new
`case-sheets.instance-qr` route under `auth:web,doctor` +
the `case-sheet` ownership middleware, reusing `TaskInstanceController::qr()`
— gated on the same condition as Print, matching the original's own
nesting (`surgery.php:1123-1131`: the QR button is *inside* the `Print`
button's `if`, not a separate check).

Worth recording precisely because it very nearly became "faithfully port a
broken button": the original's own `showTaskQrCode()` onclick handler is
**only ever defined in `required_tasks.php`'s own `<script>` block**.
`surgery.php` (and every other case sheet) includes `doctor_navbar.php`,
never `required_tasks.php` — so clicking "رمز QR" on any case sheet in the
original itself throws `showTaskQrCode is not defined` in the browser
console. Confirmed by grep, not assumed. Rebuilt here as an actually-working
button against a route that resolves, rather than reproducing the original's
dead handler faithfully.

Verified end-to-end: real odontogram data saved and read back correctly
through both `store()` and `update()` (byte-identical round trip, no
double-encoding); the print table renders real marked teeth with correct
Arabic status labels and hides itself entirely for a sheet with nothing
marked; the QR endpoint returns a valid PNG for the owning doctor and 403s
for another doctor, matching `EnforceCaseSheetAccess`'s existing rule; other
case-sheet types' printing (surgeries, tested directly) is unaffected. No
test data left in the database.

The doctor account handed over for testing has been switched to one with a
real saved sheet (`_aman__ohammed`, password reset to `Test@1234`) so
Print and QR are both visible immediately, rather than one that happens to
have nothing saved.

## Academic-session scope added to permissions (2026-08-21)

A fourth restriction dimension, alongside the original's three
(department/stage/education-type): which academic years a staff member's
own account is permitted to see at all. Not a port — the original has no
academic-session concept whatsoever (confirmed: no such table, nothing in
`includes/scope_helper.php`); academic sessions are a subsystem this
rebuild added from scratch (see "Doctors, groups and tasks tied to an
academic session" below).

**A pre-existing gap found while building this.** The three original scope
dimensions already had everything *except* a way to actually set them:
`ScopeHelper::setAllowedDepartments()`/`setAllowedStages()`/
`setAllowedEducationTypes()` existed (the equivalent of the original's
`admin/user_permissions_ajax/save_scope_permissions.php`) and `scopeX()`
correctly filtered every scoped listing — but a repo-wide search found **no
call site for any of the three setters**. There was no UI anywhere to
restrict a user's department/stage/education-type visibility; the
capability was fully wired on the read side and permanently unreachable on
the write side. Adding only an academic-session selector next to three
permanently-disabled siblings would have been a stranger, more confusing
half-measure than fixing the actual gap, so `Permissions/Edit.vue` gained a
"نطاق الوصول" (Access Scope) section covering all four dimensions together,
each a multi-select checkbox list with a clear "بلا قيد — يرى الكل"
(unrestricted) indicator when empty — matching `ScopeHelper`'s own "zero
rows = sees everything" rule, which the UI treats as a state to display
accurately rather than as "nothing selected yet".

`user_allowed_academic_sessions` (migration `2026_08_21_090000`) is shaped
to match its three siblings exactly — checked directly against their live
table definitions rather than assumed: composite primary key, no surrogate
`id`, no timestamps, **no foreign key constraints** (the siblings have
none either).

**One real difference from the other three, deliberate:**
`ScopeHelper::scopeAcademicSessions()` includes rows where the scoped
column is `NULL` even for a restricted user — the other three `scopeX()`
methods don't. `academic_session_id` is nullable throughout this app
specifically to mean "belongs to no particular year, visible under every
session" (every doctor imported from the legacy database is session-less,
for instance — see the import above). A department/stage restriction has
no equivalent "applies to no year" escape hatch to preserve, so this isn't
a pattern the other three dimensions need.

**Wired into the same call sites the other three dimensions already use** —
`DoctorController`, `DoctorPrintController`, `GroupController`,
`TaskProgressController`, and their `Api\*` mirrors for Flutter parity —
not into places that had no prior scoping (`TaskController` and
`GroupController::availableDoctors()` were never scoped by *any* of the
three original dimensions either, so adding only the fourth there alone
would have been asymmetric; left untouched, matching their existing
behaviour). This is a second, independent filter from the "which session
is currently being viewed" switcher already in the navbar — a permission
("can this account ever see 2024?") stacked on top of a viewport ("which
year's data is on screen right now"), not a replacement for it.

Verified end-to-end through the real controllers with real data, not a
unit test in isolation: created a doctor in session A, one in session B,
and one session-less; restricted a real staff account
(`hakam`, who already carries a genuine imported department restriction —
confirmed untouched by this test) to session A only via
`UserPermissionController::update()`; confirmed `DoctorController::index()`
then showed the session-A and session-less doctors but not the session-B
one; cleared the restriction and confirmed all three became visible again.
Repeated for `GroupController::index()`. No test data or restriction
survived — everything ran inside a rolled-back transaction.

## Login by username or email, plus "Sign in with Google" (2026-08-20)

Both login screens previously accepted exactly one identifier — staff by
email only, doctors by username only. Both now accept **either**, in the
same field, for both guards.

**How the two are told apart**, in both `App\Http\Requests\Auth\
LoginRequest` and `DoctorLoginRequest`: `filter_var($input, FILTER_VALIDATE_EMAIL)`
picks `'email'` or `'username'` as the column `Auth::attempt()` matches on.
Only one key is ever passed — never both — so this can't turn into an
unintended `email = ? OR username = ?` that widens which account a given
input could match. The single field is named `login` in both requests (was
`email` / `username`); the Vue forms updated their field id, label
("اسم المستخدم أو البريد الإلكتروني") and error key to match.

Verified against the real `Auth::attempt()` call both requests actually
make — not a mock — for all four combinations (staff × username, staff ×
email, doctor × username, doctor × email): all authenticate correctly.

### "Sign in with Google"

`laravel/socialite` + `App\Http\Controllers\Auth\GoogleAuthController`,
added to both login screens as a button beneath the password form.

**Sign-in only, never sign-up, by design.** A Google account is matched to
an *existing* row by email — `users` for staff, `doctors` for doctors — and
never used to create one. Neither audience has open self-registration in
this app (a doctor account is only ever created by an admin, via
`DoctorController::store()`); auto-provisioning an account for whoever
happens to sign in with a matching Gmail address would bypass that, not
extend it. No account → a clear Arabic error redirecting back to the login
form, not a silent new account.

**One Google Cloud app serves both login screens**, deliberately — Google
Cloud only needs one registered redirect URI
(`/auth/google/callback`), not one per guard. `redirect(string $as)`
stores which screen the click came from in the session before leaving for
Google (`'staff'` or `'doctor'`); `callback()` reads it back — once, then
discards it (`session()->pull`) — to decide which table to match against
and which guard to authenticate on.

**Hidden until configured, not half-broken.** `HandleInertiaRequests`
shares `googleSignInEnabled` (true only once both `GOOGLE_CLIENT_ID` and
`GOOGLE_CLIENT_SECRET` are set), and both Vue login pages skip rendering
the button entirely when it's false; `GoogleAuthController::redirect()`
also 404s server-side under the same condition, so a stray link can't reach
a half-configured flow either. Verified: with the env vars unset (the
state this ships in), `redirect('staff')` 404s and the shared prop is
`false`.

**To activate it** (not done here — needs credentials only the account
owner can create):
1. In [Google Cloud Console](https://console.cloud.google.com/), create an
   OAuth 2.0 Client ID (type: Web application).
2. Add this authorized redirect URI — must match `GOOGLE_REDIRECT_URI`
   exactly, including the `/dental_laravel/public` path segment this app
   runs under:
   `http://<your-domain-or-LAN-IP>/dental_laravel/public/auth/google/callback`
3. Set in `.env`:
   ```
   GOOGLE_CLIENT_ID=<from Google Cloud Console>
   GOOGLE_CLIENT_SECRET=<from Google Cloud Console>
   ```
   (`GOOGLE_REDIRECT_URI` is already derived from `APP_URL` in `.env`.)
4. `php artisan config:clear` — the button appears on both login pages
   immediately after, no rebuild needed (it's a server-shared prop, not a
   compiled value).

Doctors and staff sign in with whatever Google account's address matches
their existing `email` column — a doctor whose email is a personal Gmail
works with it directly; a university-issued address works the same way as
long as it's the address stored on their account and that address's mail
is actually served through Google (a Google Workspace domain), not merely
any address that happens to end in a domain someone owns.

## Real production data imported from clinic_system2 (2026-08-20)

`php artisan app:import-legacy-data` (`app/Console/Commands/ImportLegacyData.php`)
— a one-time import of the real data from the original app's database into
this one. Before this, `dental_laravel` held only what had been entered
through the Laravel UI during testing (1 doctor, 1 group, 1 task, the admin
account); the real 139 doctors, task history and case sheets lived only in
`clinic_system2`.

**Why this isn't a straight table copy.** Both databases live on the same
MySQL server, so the command reads via
`DB::table('clinic_system2.<table>')` directly — no second connection
needed. Column sets are structurally identical between the two schemas for
nearly every table (checked column-by-column before writing anything), but
**row ids are not**: this app seeded `departments` and `case_sheet_types`
independently while it was being built, so e.g. source department id 6
("operative") is id 16 here. Every foreign key is remapped through an id
map built by matching on a natural key (name / type_code) before any row is
inserted — copying ids verbatim would have silently pointed every imported
doctor, task and case sheet at the wrong department or case-sheet type.

**Data-quality issues found and fixed while writing the importer** (all
caught by a dry run inside a rolled-back transaction before anything was
committed for real):
- MySQL's old `'0000-00-00'` "no date" placeholder, still present in
  user-entered clinical date fields, which this app's strict-mode
  connection rejects outright. Sanitised to `NULL` wherever a dynamically
  copied row contains it.
- `dental_charts.chart_type` — `enum('primary','permanent') NOT NULL
  DEFAULT 'permanent'`, one source row held `''`. Falls back to the
  column's own stated default rather than guessing which of the two real
  values was meant.
- `tooth_treatments.treatment_type` — `enum(..., 'other') NOT NULL`, 30 of
  49 source rows held `''`. A full enum audit across every imported table
  found this was the only other case; falls back to the enum's own
  `'other'` member.

**What's deliberately not imported, and why** (all explained in full in the
command's own docblock):
- The source `admin` user — collides with this app's own live `admin`
  login. Historical activity-log rows originally attributed to it are kept,
  re-pointed at this app's real admin account rather than dropped.
- `mikrotik_settings` and `clinic_settings.mikrotik_*`/`jwt_secret_key` —
  the MikroTik backup feature is explicitly out of scope for this rebuild
  (see "Explicitly out of scope" below); importing real router credentials
  for a feature that doesn't exist here would serve no purpose.
- `roles`/`permissions`/`role_permissions`/`department_permissions`/
  `role_stage_department_permissions`/`user_stage_department_permissions`/
  `department_role_activity_log`/`department_role_assignments` — confirmed
  orphaned by `PermissionManager`'s own docblock; `user_permissions` is the
  table real access control reads.
- `doctor_tasks`/`task_assignments`/`task_progress`/`doctor_task_progress`
  — confirmed dead legacy tables (see "The task system" below).
- `register_days` and its related tables — back a booking feature never
  built in this app.
- `clinic_settings.clinic_logo`/`university_logo`/`base_url`/
  `enable_notifications`/`enable_sms`/`enable_email`/`mail_*`/`theme` — this
  app already has these configured for real (Gmail SMTP, a chosen theme);
  overwriting them with the source's stale values would have silently
  undone that configuration. Only descriptive identity fields (name,
  address, phone, working hours, university/college names) were merged in.
  The two logo files and the one doctor photo that exist on disk in the
  source app's `uploads/` folder were copied across by filename and
  verified present with `Storage::disk('public')->exists()` before their
  columns were set — never a path to a file that wasn't actually copied.

**A design detail confirmed while writing the activity-log import**:
`user_activity_log.user_id` is overloaded in both schemas — it isn't a
clean FK to `users` alone. `App\Services\ActivityLogger::actor()` already
writes a **doctor's** id into this same column with `user_role='doctor'`
when the acting principal is a doctor, faithfully mirroring what the
source does (13 log rows had `user_role='doctor'` with a `user_id` that
only resolves against `doctors`, e.g. id 705 → doctor "Zaman Mohammed",
not any row in `users`). The importer branches on `user_role` and remaps
through the doctor id map for those rows rather than dropping them.

**Verified before and after committing**: a dry run inside a rolled-back
transaction (surfacing every issue above without touching real data), then
FK-integrity checks against the committed data (zero orphaned foreign keys
across every remapped table), then a feature pass with the real data in
place — doctor login, the doctors/groups/tasks/patients/dental-charts/
surgeries/task-progress/academic-sessions/activity-log/dashboard pages,
`CaseSheetController::open()` routing a real task instance to its sheet,
the permission grants imported for the two real staff accounts working
through both `PermissionManager` and `ScopeHelper`, the `/api/v1/doctors`
endpoint, the doctor-roster print, and a real surgery case-sheet print
(with its QR code) — all against the actual imported data, not synthetic
test rows. The pre-existing admin login and the doctor/group/task the user
had already created by hand through the UI were confirmed untouched.

| Table | Rows |
| --- | --- |
| doctors | 139 imported (140 total with the pre-existing test doctor) |
| doctor_group_members | 138 |
| groups / group_slots | 3 / 4 |
| tasks / task_instances | 15 / 34 |
| surgeries / surgery_medications | 18 / 28 |
| dental_charts / tooth_treatments / endodontics_images / treatment_plans | 6 / 49 / 1 / 2 |
| periodontal_charts, prosthodontics_records, complete_denture_records, orthodontics_records, prevention_records, oral_medicine_charts | 1 each |
| patients / patients_simple | 1 / 36 |
| academic_sessions | 3 |
| case_sheet_types (new: `other`, `pediatric`) | 2 |
| users (admin skipped) | 3 |
| user_permissions | 22 |
| user_allowed_departments/stages/education_types | 1 each |
| user_activity_log | 349 |
| clinic_settings | merged (identity fields + 2 logo files) |

## UI redesign: themes, login screens, navigation (2026-08-20)

Modelled on a dental-unit control panel supplied as reference: a near-black
slate ground, raised cards with a large corner radius, line icons, and a
mint accent used **only** on the active element.

**Theme system.** `clinic_settings.theme` (migration
`2026_08_20_090000`) holds one of four palettes defined in
`App\Support\ThemePalette` — `unit-dark` (default, the reference panel),
`unit-blue`, `unit-violet`, `clinic-light`. Picked from
الإعدادات ← المظهر / الثيم, and validated with `Rule::in` so an unknown value
can't leave the app with no colour variables at all; `resolve()` also falls
back to the default defensively.

Applied as CSS custom properties written straight onto `<html>` by
`app.blade.php`. Deliberately **not** resolved in JavaScript: doing that
flashes the previous palette on every page load. Tailwind maps semantic
utilities onto the same variables (`bg-surface`, `text-content`,
`border-hairline`, `bg-accent`…), so switching theme is a settings change
rather than a rebuild — which is also why the variables hold
space-separated RGB channels rather than hex: it is what makes
`bg-accent/20` and friends work through Tailwind's `<alpha-value>`.

**Scope, stated plainly.** The theme drives the *chrome* — both login areas
and both navigation shells — while the page content region keeps its neutral
light background. About fifty page components style their own cards and text
with fixed Tailwind greys (`bg-white`, `text-gray-800`); repainting the
region behind them from a dark token would leave dark-on-dark text wherever
a page writes directly onto the page background. Theming every page body is
a separate pass, not a side effect of this one.

**Login screens.** `GuestLayout` became the panel: ambient accent wash, a
brand block, a segmented الموظفون/الأطباء switch styled like the unit's tool
tabs, and one raised card. Both logins gained a show/hide password toggle
and a spinner-on-submit state. The other seven `GuestLayout` pages (forgot,
reset, confirm, verify, register — staff and doctor) had to be rewritten
too: they used the app-wide `InputLabel`/`TextInput` pair, which is
`text-gray-700` and all but vanishes on a dark card. They now share a
`Components/AuthField.vue`. That component is intentionally separate from
`TextInput`, which stays untouched for the ~50 light-styled pages.

**Navigation.** Both shells are now a raised slab holding a
horizontally-scrolling strip of icon+label tiles, the active tile carrying
the accent gradient. In the staff shell the desktop strip and the mobile
menu are generated from **one list of links** — the previous duplication is
exactly how the mobile menu ended up missing half the app (documented under
"Navigation bug" below). The mobile account links no longer use
`ResponsiveNavLink`, whose fixed `text-gray-600` is unreadable on the dark
panel.

**`Components/BrandMark.vue`** is a real SVG molar — two crown lobes over
two roots, with a groove cut in the page colour so it reads at any size —
painted with the theme's accent gradient. SVG rather than an icon-font
glyph because this is the one mark that must scale freely and take a
gradient; `Icon.vue` (Material Symbols) remains the right tool for the
hundreds of single-colour UI glyphs. Its gradient id is derived from
`useId()`: two instances on one page (navbar + login card) sharing a fixed
id would let the first definition win and silently recolour the second.

### The icon font 404'd in every browser (2026-08-20)

Reported from a phone as Material Symbols showing their **ligature names as
text** — "mail", "lock", "visibility", "login" — instead of glyphs. Not a
mobile problem: it affected every browser, the phone is just where it was
noticed.

Cause: this app is served from a sub-directory (`/dental_laravel/public`),
not a domain root. Vite's default base makes `url()` references inside the
built CSS root-absolute, so the stylesheet asked for
`/build/assets/material-symbols-outlined-*.woff2` → `http://host/build/…`,
which **404s**; the real path is `/dental_laravel/public/build/assets/…`.
Confirmed by requesting both: 404 vs 200.

What made it easy to miss: the page still looked completely correct. The
stylesheet *itself* loads fine, because Laravel's `@vite` tag builds that
URL from the application path rather than from Vite's base — only the
`url()` references *inside* the CSS were wrong. And because the package sets
`font-display: block`, a font that never arrives shows the fallback font
after the block period, which for an icon-ligature font means the ligature
name rendered as plain text. The font never being fetched looked exactly
like the font being fetched and ignored.

Fixed with `base: './'` in `vite.config.js`, which emits URLs relative to
the stylesheet, so they resolve wherever the folder is deployed. Chosen over
setting `ASSET_URL`, the other documented fix, because that hard-codes this
particular sub-directory into the build output.

Verified afterwards by fetching **every** asset the login page references
over the LAN address (all 200), and by downloading the font and checking it
arrives byte-for-byte with a valid `wOF2` signature.

**Caching added at the same time.** The font is 3.78 MB and Apache sent no
`Cache-Control`, so every page load cost a revalidation round-trip (ETag
→ 304). `public/.htaccess` now sets `max-age=31536000, immutable` for
`/build/assets/` — safe because Vite content-hashes every filename, so a
changed file is a new URL and can never be served stale. It lives in
`public/.htaccess` rather than `public/build/.htaccess` because Vite empties
the build directory on each build. Pages themselves stay `no-cache, private`.

### A bug found while redesigning: doctor nav items rendered as raw markup

`DoctorLayout`'s `NAV` array stored each icon as a **string of component
markup** — `icon: '<Icon name="home" class="ml-1" />'` — rendered through
`{{ item.icon }}`, which Vue escapes. Every doctor nav item therefore
printed that tag as visible text instead of an icon, on desktop and mobile
both. Left over from the emoji→Material Symbols pass, which rewrote the
emoji inside that JS string as though it were template markup. `icon` now
holds the ligature name and the template renders `<Icon :name="item.icon" />`.
A repo-wide grep confirmed `DoctorLayout` was the only file with the
pattern.

## Case-sheet access rebuilt to the original's rules (2026-08-19)

Fixes the bug the printing work surfaced: **a doctor could not open their
own case sheet at all.** Verified rather than reasoned about — a doctor
authenticated on the `doctor` guard returns `false` from
`Auth::guard('web')->check()`, while every specialty sheet was registered
under `Route::middleware('auth')` → `EnsureUserHasRole:super_admin,admin,editor`,
i.e. the default `web` guard plus a staff-role check. So
`doctor.case-sheet` → `CaseSheetController::open` → redirect to
`{resource}.edit` bounced the doctor to the staff login, breaking the
"فتح النموذج" flow end to end.

**The port had the rule exactly inverted.** Read off the original rather
than assumed — `doctor/doctor_auth_check.php` plus the block every sheet
opens with (`surgery.php:16-26`, repeated in all nine):

```php
$is_admin                 = role in [admin, super_admin]
$is_user_with_permissions = user_id && !doctor_id && !$is_admin
$is_view_only             = $is_admin || $is_user_with_permissions
$can_save_case_sheet      = ($case_owner_id === $doctor_id)
if ($_SERVER['REQUEST_METHOD'] === 'POST' && !$is_view_only) { /* save */ }
```

and `doctor_auth_check.php`: *"Allow any logged-in user (doctor_id OR
user_id) — individual pages will check permissions"*. So the original's
rules are:

| | open | save | delete |
| --- | --- | --- | --- |
| Owning doctor | ✔ | ✔ | ✔ |
| Another doctor | ✘ (`AND doctor_id = ?` hides it) | ✘ | ✘ |
| Staff — **including admins** | ✔ | ✘ | ✘ |

Staff being view-only is the part the port had backwards: it let staff edit
freely and locked doctors out. Deleting requires a doctor session too —
`ajax/delete_surgery.php` 401s when `$doctor_id` is absent.

**Implementation.** `App\Services\CaseSheetAccess` holds the four original
variables as one testable unit; `App\Http\Middleware\EnforceCaseSheetAccess`
(alias `case-sheet`) applies them to all 13 sheet resources at once rather
than restating them in 13 controllers where they could drift. The resources
moved out of the staff-role group into
`Route::middleware(['auth:web,doctor', 'case-sheet'])`. Listings are scoped
with `CaseSheetAccess::scope()` (the original's `AND doctor_id = ?`) and the
form's existing `readonly` prop is now also true for staff, which already
disables every input and hides the save button; a "وضع العرض فقط" banner
explains it, matching the original's "View Only Mode" alert.

Ownership is checked against **every** bound model on the route, not just
`{record}` — the operative sheet binds as `{dentalChart}`, so keying off one
parameter name would have skipped it silently.

**A second hole found and closed while testing.** With doctors able to write
at last, a doctor could file a case sheet **under a colleague's name** by
posting `doctor_id`: the shared form carries a doctor selector, and nothing
overrode it. Reproduced (`posted doctor_id=DocB → stored owner DocB`), then
fixed by taking ownership from the session as the original does
(`$_SESSION['doctor_id']`, never from POST) — the middleware merges the
signed-in doctor's id into every write. Re-tested through the full
middleware→controller stack: the spoofed id is now overwritten. The selector
is also hidden from doctors, since it no longer decides anything.

**Layouts.** `AuthenticatedLayout.vue` dereferences
`$page.props.auth.user.role` unguarded, and `auth.user` is `null` for a
doctor — the page would have thrown on render. `Specialty/Index.vue` and
`Specialty/SectionedForm.vue` now pick `DoctorLayout` or
`AuthenticatedLayout` by principal (both expose the same `#header` slot).

Verified for every principal × verb combination in a rolled-back
transaction: owning doctor read/save/delete → allowed; other doctor
read/save → 403; staff read → allowed, save/delete/create → 403; two
doctors' listings show only their own records while staff see both; and the
whole `doctor.case-sheet` → sheet → save chain now completes for a doctor.
Route count unchanged at 360.

## Doctors, groups and tasks tied to an academic session (2026-08-19)

Requirement: when a new academic year starts (e.g. 2025), it gets its own
doctors, groups and tasks, and the previous year's records stay intact.

**What was actually there.** Verified against the real schema, not assumed:
`groups.academic_session_id` and `tasks.academic_session_id` already existed,
but `doctors` had **no session column at all** and `doctor_group_members`
had none either. So a doctor's academic year was only ever *implied* by
their group membership. Two consequences, both real:

1. A doctor with no group belongs to no year, so a new intake can't be
   listed or filtered until groups are formed.
2. **The multi-year data-loss bug.** `GroupController::addDoctors` enforced
   the original's "one group at a time" rule with an unscoped
   `DB::table('doctor_group_members')->whereIn('doctor_id', …)->delete()`.
   Adding a doctor to a 2025 group therefore **deleted their 2024
   membership** — the previous year's record was destroyed, not archived.
   The API mirror (`Api\GroupController::addDoctors`) had the identical
   unscoped delete, so the Flutter path destroyed history too.

**Migration** `2026_08_19_120000_add_academic_session_to_doctors.php` adds
`doctors.academic_session_id` and `doctor_group_members.academic_session_id`
— both nullable and indexed. Nullable is the deliberate convention already
used elsewhere in this codebase (scoping, session-less groups/tasks): **no
session = visible under every session**, so existing rows keep working
untouched. Existing memberships were backfilled from their group's session
(0 rows — none existed yet).

**The rule is now "one group per academic session", not "one group ever".**
`addDoctors` scopes its delete to the group's session (treating pre-column
`NULL` rows as belonging to the current one, so a doctor still can't end up
in two groups in the *same* year). Verified end-to-end in a rolled-back
transaction: one doctor enrolled in a 2024 group and then a 2025 group ends
with **two** membership rows, one per year — the exact regression this
fixes. `availableDoctors` correspondingly now means "not in a group *this
session*", otherwise a returning doctor could never be enrolled again.

**Session filtering**, everywhere using the original's own
`academic_session_id = ? OR IS NULL` idiom (copied from
`tasks_ajax/get_tasks.php`):

| Screen | Behaviour |
| --- | --- |
| Doctors list | filtered to the working session; banner naming it; "عرض جميع الفصول الدراسية" toggle (`?all_sessions=1`) and a session column that appears only when the filter is lifted |
| Doctor create / edit | create stamps the working session; edit exposes a session select (so a mistake is fixable and legacy session-less doctors can be assigned one) |
| Doctors print roster | repeats the list's session filter so "طباعة الفلتر" prints what's on screen — but *not* when explicit `ids` are passed, since "طباعة المحدد" must print exactly the ticked rows |
| Groups list | already filtered; now shows a banner naming the session it's creating into |
| Tasks list | **was not session-aware at all** — filtered now, same banner + toggle |
| Task create | **never set `academic_session_id`**, so every task created through Laravel was session-less; now stamped, matching `add_task.php` |
| Task detail | only offers doctors from the task's own year for assignment |
| Session stats page | counts a doctor via direct enrolment **or** group membership, since a new intake exists before groups do |

**Bugs found and fixed while doing this**, each verified rather than
assumed:

- **Ambiguous SQL introduced by the migration.** Adding
  `academic_session_id` to `doctor_group_members` made
  `Doctor::whereHas('groups', fn ($q) => $q->where('academic_session_id', …))`
  in `Api\AcademicSessionController::show` ambiguous — confirmed by
  reproducing `SQLSTATE[23000] … Column 'academic_session_id' in where
  clause is ambiguous`. Both the web and API versions now qualify it as
  `groups.academic_session_id`. Worth remembering: adding a column to a
  pivot can break existing unqualified relation queries.
- **`tasks.grade` was missing from the port.** The column exists and the
  original's add/edit task forms have a "الدرجة / العلامة" input
  (`0.00–100.00`), but the Laravel task forms and validation had no such
  field, so it could never be set. Added to both forms, web and API.
- **The API doctor search repeated the unnested-`orWhere` bug** fixed
  earlier on the web side: `->where('name', …)->orWhere('email', …)` without
  a nested closure escapes the preceding `ScopeHelper` filters, so a search
  could return doctors outside the caller's permitted scope. Now nested.
- **`DoctorResource` null-guard.** `whenLoaded('academicSession')` still
  runs its closure when the relation is loaded but empty, which would fatal
  for a session-less doctor; guarded explicitly.

**Note:** the database currently has **zero `academic_sessions` rows**, so
all of this is inert until a session is created under
"الفصول الدراسية" — until then `resolve()` returns `null` and every list
behaves exactly as before (no filtering, no banners). That nullable path is
deliberate and tested; it's the same fresh-install deadlock guarded against
when `AcademicSessionHelper::resolve()` was changed off `firstOrFail()`.

## Doctor printing, and Material Symbols replacing emoji (2026-08-19)

**Printing** — port of `admin/print_doctors.php` (a roster grouped by
stage, with per-stage counts, a summary box, signature lines and the clinic
logo as a watermark) and `admin/print_doctor_card.php` (a single doctor's
ID card). Written as **Blade views, not Inertia pages**, deliberately:
these are standalone print documents opened in a new tab with their own
university/college letterhead and `@media print` rules — rendering them
inside the app shell would print the navigation with them. One roster
endpoint serves both of the original's buttons: **طباعة الفلتر** passes the
current education-type/stage/search filters, **طباعة المحدد** passes the
ticked row ids. Each doctor row also links to their printable card.
Watermarks and table shading are kept in print with `print-color-adjust`,
which browsers otherwise strip. Gated on `doctors.export` — the closest
action the original's own matrix defines for taking data out.

**Icons** — the UI had been using emoji as icons. Replaced with **Material
Symbols** via a small `Components/Icon.vue` (46 occurrences across 14
files). Emoji were a genuine problem, not just a style preference: they
render as different glyphs on Windows/Android/iOS, some are simply missing
and show as tofu boxes, and they can't be recoloured or sized with the
surrounding text.

The font is **self-hosted from the npm package rather than the Google Fonts
CDN** — this app is used over a LAN where the internet may not be
reachable, and an icon font that silently fails to load would leave every
button unlabelled. Vite bundles the woff2 (verified present in
`public/build/assets/`). Icons are `aria-hidden` by default and take a
`label` prop for the icon-only cases, so screen readers don't read out
ligature names like "qr_code_2" as content.

Verified: the roster renders with its doctors, groups, summary and print
control; passing `ids` restricts it to exactly the selected doctors; the
card renders; and no emoji remain anywhere in `resources/js`.

## Task-progress QR scanner with torch (2026-08-19)

Comparing task progress against the original left one real gap: its
`task_progress_view.php` carries a **camera QR-scanner modal** (html5-qrcode,
with start/stop and camera switching) that this port had explicitly
deferred. Now built, plus the requested torch/flash.

**Decoding — chosen for device coverage, not convenience.**
`Components/QrScanner.vue` uses the browser's native `BarcodeDetector`
where it exists (Chrome/Edge, Android — hardware-accelerated), and falls
back to **jsQR** decoding canvas frames everywhere else (Safari/iOS,
Firefox, which have no `BarcodeDetector`). Both paths feed the same
callback, so behaviour doesn't change with the browser.

**Torch.** Exposed only when the active video track actually advertises the
`torch` capability, and the button is hidden (with an explanatory line)
where it doesn't — **iOS Safari does not expose torch control to web pages
at all**, so showing the button there would be showing a broken control.
The torch is explicitly switched off before the track is released, because
on some Android devices closing the modal otherwise leaves the LED on.

**Two failure modes surfaced rather than left silent**, both of which
would otherwise look like "the camera just doesn't work":
- **Camera needs a secure context.** `getUserMedia` is blocked on plain
  http except on `localhost` — which is exactly how this app is reached
  over the LAN IP for testing. The scanner detects that and says so,
  instead of failing with nothing on screen.
- **Permission denied** is reported distinctly from other errors, with what
  to do about it.

**Server side.** `TaskProgressController::scan` (`POST /task-progress/scan`,
gated `permission:task_progress,view`) resolves a scanned payload and
handles **both shapes this app issues**: a `task_instance` code returns the
case with a direct link to its case sheet, and a `pending_task` code (from
the doctor's "رموز المهام المعلقة" page — a doctor+task pair with no
instance yet) returns the pair so the modal can start the task right there.
Verified end-to-end: both shapes resolve correctly, and non-JSON input, an
unknown `type`, and a valid-shaped code pointing at a missing id are each
rejected with their own message (422/422/404) rather than crashing.

## The operative case sheet, and how case sheets are actually opened (2026-08-19)

Reported from the live original: the **operative (المخطط السني)** case
sheet was missing, with a request to compare the case sheets and *the way
they work* against the original. Comparing surfaced a bigger gap than the
one sheet.

**The mechanism the port had wrong.** In the original, case sheets are
never standalone lists. A task carries a `case_sheet_type_id`; opening a
task instance goes through `doctor/open_case_sheet.php`, which looks up
that type's `type_code` and **routes to the matching sheet carrying
`task_instances_id`**, so the sheet loads and saves the record belonging to
*that instance* (its `save_*.php` files look the row up by
`task_instances_id`). This port had built all the sheets but only as
independent CRUD screens — nothing tied a filled sheet back to the task it
was filled for. Ported as `App\Http\Controllers\CaseSheetController`:
- maps every `type_code` to this app's equivalent sheet, including the
  original's own quirk that **both `partial_denture` and `prosthodontics`
  route to the prosthodontics sheet**, and its fallback of defaulting to
  the operative sheet for an unknown/missing type;
- **reuses** the sheet already filled for that instance if one exists,
  otherwise opens a blank one pre-linked to it;
- access matches the original: a doctor may only open their own instance
  (403 otherwise), staff need `task_progress.open_case_sheet` — one of the
  actions restored to the permission matrix.
"فتح النموذج" buttons now appear on the doctor's required-tasks slots and
on the admin task-progress cards, as in the original.

**Operative sheet built.** `operative` maps to `dental_charts`, which
existed with a tooth picker but as a generic form, not a case sheet. Now a
sectioned sheet (`App\Support\OperativeForm`) with the original's groups —
patient info, chief complaint & history, clinical examination, tooth status
(non-vital / missing / crown-bridge as quadrant pickers), treatment plan and
approval. Note `dental_charts.patient_id` is a **varchar holding the
patient's name**, not an FK, which is why it is a text field here.

**Case-sheet types seeded.** The imported schema arrived with only the
`operative` row, so tasks could not be typed as anything else and the
dispatcher had nothing to route. `CaseSheetTypeSeeder` adds the nine types
the original ships with (operative, partial_denture, complete_denture,
surgery, periodontal, prosthodontics, orthodontics, prevention,
oral_medicine) — idempotent on `type_code`, so it never duplicates and
never overwrites a name an admin edited (the pre-existing `operative` row
kept its own).

**A bug this work exposed, introduced by the earlier permission fix.**
Correcting the matrix to the original's 11 modules removed
`appointments`, `dental-charts` and `payments` — but their routes were
still gated with `permission:appointments,view` and friends. Since those
modules no longer exist in the matrix they can never be granted, so **every
non-super_admin was permanently denied those screens** — exactly the class
of latent bug documented above for the original's own `task_progress.edit`.
Found by listing every module referenced by `permission:` middleware and
diffing it against the matrix. Fixed by dropping those stale gates (the
original has no permission modules for them either; they keep their `role:`
gating). Verified afterwards that **no route gates on a module absent from
the matrix**.

## Admin dashboard rebuilt to match the original (2026-08-19)

The staff dashboard was still a placeholder — a closure in `routes/web.php`
rendering two numbers (doctor and patient counts). Rebuilt as
`DashboardController` + `Dashboard.vue`, porting
`dental_clinics2/admin/dashboard.php`:

- **three headline counters** (عدد الأطباء / عدد المراجعين / عدد المهام);
- **المهام المنجزة مقابل غير المنجزة** — the original's own `tasks.done`
  flag, as a percentage bar — alongside a task-*instance* breakdown
  (completed / assigned / pending), which the original doesn't show but is
  the more useful number now that instances drive everything else;
- **quick-access cards**, filtered by the viewer's actual grants
  (`PermissionManager`) so the dashboard never offers a link the user's
  permissions would then reject;
- **أحدث الأطباء** and **أحدث المراجعين** (5 each);
- **المهام المطلوبة لكل قسم ومرحلة حسب نوع الدراسة** — the original's
  on-demand section (`ajax/dashboard_tasks_by_dept.php`), loaded when the
  education-type select changes, showing required/completed/remaining per
  task grouped by department and stage.

Session-scoped like the rest of the app (`academic_session_id = current OR
NULL`).

**Deliberately not ported from that page**, each for a reason already
established elsewhere in this document: the **الدخول كطبيب** impersonation
card (the feature is orphaned in the original — only linked from the
retired `admin_navbar.php`), the **النسخ الاحتياطي** card (MikroTik/backup,
out of scope by request), and the **تسجيل مريض جديد** card's target — the
original's counter sums `patients` + `patients_simple` + `patients_admin`,
three unrelated intake tables, whereas this rebuild deliberately uses only
`patients` (the one the rest of the schema's FKs actually reference), so
the counter counts that table and the card links to this app's real patient
form.

Verified end-to-end with seeded data: counters, done/not-done split,
instance breakdown, both "latest" lists, the permission-driven `can` flags,
and the per-education-type section (which correctly returned two
departments with their required/completed totals).

## Email settings, password reset, notifications & profiles (2026-08-19)

**First, what the original actually has** (checked before building, so the
distinction between "port" and "new" is honest): grepping the whole
`dental_clinics2` codebase for `mail(`/PHPMailer/SMTP returns **nothing but
its own settings getter** — the app has **no mail configuration, sends no
mail, and has no password reset of any kind** (no forgot/reset files
exist). Its `enable_email` / `enable_notifications` columns are flags
nothing ever reads. So the settings and profile screens below are ports;
SMTP config, password reset and email notifications are **new features**.

**SMTP settings** — seven new columns on the single `clinic_settings` row
(`mail_host/port/username/password/encryption/from_address/from_name`,
migration `2026_08_19_100000`), edited from the settings page rather than
by hand-editing `.env` on the server, matching how the rest of the clinic
configuration is stored. `MailSettingsServiceProvider` applies them over
the `.env` mail config at boot; with no host configured it leaves Laravel's
default in place — out of the box `MAIL_MAILER=log`, so reset links are
written to the log and everything is testable before SMTP exists. The
settings page says exactly that in a banner. The stored password is
`encrypted`-cast and `$hidden`, so it is never sent to the browser;
submitting the field blank keeps the stored value rather than clearing it
(verified: the raw column is unreadable, the model decrypts it, and it is
absent from the model's array form).

**Password reset** — Breeze ships this for staff only. Doctors are a
separate guard against a separate table, so they get their own broker
(`config/auth.php` `passwords.doctors`), routes
(`/doctor/forgot-password`, `/doctor/reset-password/{token}`, throttled
6/min), Vue pages, and an Arabic `DoctorResetPassword` notification. The
notification is needed rather than optional: Laravel's built-in one builds
its URL from the staff `password.reset` route, which would land a doctor on
the staff form and then fail against the wrong broker. A "نسيت كلمة
المرور؟" link was added to the doctor login page. The reset endpoint
reports the same neutral status whichever address is submitted, so it can't
be used to enumerate which addresses are registered doctors.

**Email notifications** — `App\Services\Notifier` is the single gate: it
sends only when **both** `enable_notifications` and `enable_email` are on,
skips notifiables with no address, and swallows+logs delivery failures so a
dead mail server can't fail the request that triggered it (assigning a task
must not depend on SMTP being up). Wired to task assignment
(`TaskAssigned`, sent after the transaction commits). This finally gives
the original's two decorative toggles real meaning. Verified: dispatched
when enabled, not dispatched with email disabled, not dispatched to a
doctor with no address.

**Profile pages** — both rebuilt to match `admin/admin_profile.php` and
`doctor/profile.php`, which are the same shape: **two separate forms**,
`update_profile` (name / email / phone / profile_image) and
`change_password` (old / new / confirm).
- The doctor page previously merged them into one form with an optional
  password field and **no current-password check** — anyone with a live
  session could change the password without knowing the old one. Now split,
  with the old password verified as the original does (verified: a wrong
  old password is rejected, the correct one changes it).
- The staff page was still the stock Breeze scaffold: name+email only —
  **no phone and no photo, though both are real `users` columns and both
  appear in the original** — plus a delete-account form the original has no
  counterpart for. Deleting staff belongs in user management, not
  self-service, so it was dropped rather than ported.
Both pages show an identity summary (photo, username, role / stage +
study type for doctors) and upload photos on the same
`Storage::disk('public')` convention as the rest of the app.

## Permission matrix corrected to the original's (2026-08-19)

Asked to verify user permissions match the original's settings and
features. They did **not** — checked against the original's authoritative
definition in `admin/user_permissions_ajax/get_user_permissions.php`, the
earlier port was wrong in three ways, now fixed
(`App\Support\PermissionMatrix`, copied verbatim from that file):

**1. Wrong module list.** The port had 7 modules
(`doctors, patients, tasks, departments, appointments, dental-charts, payments`).
The original has **11**, and three of the port's were invented —
`appointments`, `dental-charts` and `payments` are *not* permission modules
in the original at all. Missing entirely were `dashboard`, `users`,
`groups`, `stages`, `task_progress`, `reports` and `settings`.

**2. Uniform actions instead of per-module action sets.** The port rendered
a cartesian 7 × `view/create/edit/delete/export` grid. In the original each
module defines **its own** actions, so the port both offered grants that
never existed and hid ones that do:

| module | actions |
|---|---|
| `dashboard` | view, edit |
| `users` | view, create, edit, delete |
| `doctors` | view, create, edit, delete, export |
| `patients` | view, create, edit, delete, export |
| `tasks` | view, create, edit, delete, **assign** |
| `groups` | view, create, edit, delete |
| `stages` | view, create, edit, delete |
| `departments` | view, create, edit, delete |
| `task_progress` | view, **view_all**, export, **start**, **finish**, **open_case_sheet** |
| `reports` | view, export, **print** |
| `settings` | view, edit |

44 grant pairs in total. Module and permission *keys* are the original's
exactly, so `user_permissions` rows mean the same thing in both apps.

**3. Grants that enforced nothing.** Now that the real actions exist they
are wired to the routes that implement them: `task_progress` view/start/
finish on the admin task-progress screen (the original checks exactly these
in `get_group_doctors.php`, `assign_task_ajax.php` and
`mark_task_completed.php`), `groups` view/create/edit/delete (membership
changes count as `groups.edit`), `stages` CRUD, and `settings` view/edit on
the clinic-settings page (the original opens with
`requirePermission('settings','edit')`).

**A latent bug in the original, found while wiring this and deliberately
not reproduced**: four places check `task_progress.edit` — but
`task_progress` **has no `edit` action in the original's own matrix**, so it
can never be granted. Three of them read `finish || edit`, which therefore
collapses to `finish`; but `admin/ajax/update_task_status.php` checks
`edit` **alone**, meaning that endpoint denies every non-super_admin
permanently. This port gates the equivalent action on `finish`, matching
the effective behaviour of the working checks.

**UI**: `Permissions/Edit.vue` rebuilt as one card per module rendering only
that module's actions, with Arabic module names and action labels from the
original, per-module "select all", and global تحديد الكل / إلغاء الكل
(the original's `selectAllPermissions()`). The API mirror
(`Api\UserPermissionController`) is driven by the same matrix and now
returns the module definitions alongside the grants. Both surfaces validate
submitted pairs with `in:` against the matrix, so a client can't invent a
module/permission combination.

Verified end-to-end in a rolled-back transaction: an `admin` user was
denied `task_progress.start` / `groups.edit` / `settings.edit`; after
granting four pairs through the real controller it was allowed exactly
those (`task_progress.start`, `groups.edit`, `tasks.assign`,
`reports.print`) and still denied `settings.edit` and
`task_progress.finish`; 44 rows were written with 4 granted; submitting the
undefined pair `task_progress.edit` was rejected by validation; and
`super_admin` bypassed every check.

## Admin Doctors & Groups screens rebuilt to match the original (2026-08-19)

**إدارة الأطباء** (`Doctors/Index.vue`, port of `admin/manage_doctors.php`).
The previous port was a plain paginated table with one search box. Now it
carries the original's actual controls:
- header actions **رفع ملف Excel** / **إضافة طبيب**;
- the **filter row** — education type, a **stage select that cascades off
  it** (disabled until an education type is picked, exactly as the
  original's `#filter-stage` is), and a debounced search box. Search now
  also matches `username`, and — a real fix — the search clauses are
  wrapped in a nested `where(...)`: previously the `orWhere` chain sat
  beside the scope/filter constraints, so a search would have **broken out
  of the education-type/stage filter and the permission scope** (classic
  unparenthesised OR precedence bug);
- **row selection with a bulk bar** ("تم تحديد N صف" + حذف المحدد) backed by
  a new `DELETE /doctors-bulk` route (`destroyMany`, gated by the same
  `permission:doctors,delete`) — the original has this and the port didn't,
  so deleting many doctors meant one confirm per row;
- the original's columns (الاسم / البريد الإلكتروني / نوع الدراسة / المرحلة /
  العمليات) and an export-the-current-filter action.

**إدارة المجموعات** (`Groups/Index.vue`, port of `admin/manage_groups.php`
plus its `load_groups.php` card renderer):
- the same filter row (نوع الدراسة → المرحلة → **عرض المجموعات**), including
  the original's behaviour of **not listing anything until you ask** rather
  than dumping every group on load;
- the same **inline add-group form** with repeatable day/time slot rows
  (Sunday–Thursday, the original's own day list);
- the group card rebuilt to match `load_groups.php`: header with name +
  stage and تعديل/حذف, the slots list, then the doctors block with a
  **per-group search box**, **تحديد الكل**, a **حذف المحدد (N)** bulk
  removal, per-doctor remove, the doctor total line, and the
  **إضافة أطباء للمجموعة** modal (which lists only doctors in no group and
  notes that adding moves them, matching the one-group-at-a-time rule).

Verified end-to-end: the doctors page returned the right totals per filter,
`search=BB` correctly narrowed to one row, bulk delete removed the selected
doctor and flashed its count; the groups page returned `loaded:false` with
no groups before a filter was applied and the full card payload (slots,
doctors with emails) after.

## Doctor area rebuilt to match the original (2026-08-19)

Requested: make the doctor-facing screens the same interfaces and options
as the original. The previous version was a minimal placeholder (an English
"My Cases" bar with Dashboard/Profile/Log Out and a flat instance list).
Rebuilt against `dental_clinics2/doctor/`:

**Navbar** (`DoctorLayout.vue`, port of `doctor_navbar.php`) — RTL, the
original's gradient-purple bar, clinic logo + "لوحة الطبيب — {clinic}"
brand, and its **four nav items in the original's order and wording**:
الرئيسية · المهام المطلوبة حسب الأقسام · رموز المهام المعلقة · تقدم المهام
التفصيلي. Plus the academic-session switcher
(`SessionHelper::renderSwitcherWidget()` in the original, marking the
current session `[الحالي]`) and the avatar dropdown (الملف الشخصي /
تسجيل الخروج). The navbar's "admin viewing as doctor" branch is **not**
ported — the impersonation feature it belongs to is orphaned in the
original (see the audit note above).

**الرئيسية** (`Doctor/Dashboard.vue`, port of `doctor/index.php`) — study
type / stage / group with that group's weekly slot badges, four stat cards
(المهام المعروضة / المكتملة / المخصصة / المعلقة), a completion progress
bar, quick-access buttons, and the stage's task cards. Two real behaviours
of the original ported rather than simplified away:
- **the started-tasks filter** — once the doctor has any assigned or
  completed instance, tasks with neither a pending nor an assigned
  instance are hidden, and the original's explanatory notice ("تم إخفاء
  المهام المكتملة…") is shown;
- **the asymmetric counting** in its query — assigned/completed are counted
  *for this doctor*, while pending is counted globally, because a pending
  instance belongs to nobody yet. Stats are computed over the *displayed*
  tasks only, as the original does.

**المهام المطلوبة حسب الأقسام** (`Doctor/RequiredTasks.vue`, port of
`required_tasks.php`) — the stage's tasks grouped into collapsible
department panels, each task rendering one card per required slot with that
slot's status, using the same positional slot model as the admin
task-progress screen (`instances[$slot]`, with `unassigned` = "لم تبدأ بعد"
as a computed state, not a DB status).

**تقدم المهام التفصيلي** (`Doctor/Progress.vue`, port of `progress.php`) —
the doctor's own instances grouped by task with per-task and overall
completion bars and an instance table.

**رموز المهام المعلقة** (`Doctor/PendingTasksQr.vue`, port of
`doctor_pending_tasks_qr.php`) — note "pending" here means a stage task the
doctor has **no instance of at all** (`t.id NOT IN (SELECT task_id FROM
task_instances WHERE doctor_id = ?)`), a *different* sense from
`status='pending'`; the QR encodes the doctor+task pair so a supervisor can
scan it to start the task. Served as a PNG from the same `endroid/qr-code`
setup as the admin QR route.

All four are session-scoped (`academic_session_id = current OR NULL`) like
the rest of this rebuild. Verified end-to-end with a seeded doctor, group
with a slot, and two tasks: the dashboard reported the right group/slots
and stats, correctly hid the un-started "Task B" under the started-tasks
filter, required-tasks rendered 2 slots for the 2-required task,
progress reported `{total:2, completed:1, assigned:1}`, and pending-QR
listed exactly "Task B".

## Doctor web area

Doctors previously only had API access. Now they have a small, separate web
UI on the `doctor` guard — deliberately not reusing `AuthenticatedLayout`
(that's built around `$page.props.auth.user`, the `web` guard) — a new
`DoctorLayout.vue` and `$page.props.auth.doctor` instead
(`HandleInertiaRequests` now shares both `auth.user` and `auth.doctor`;
whichever guard didn't authenticate is `null`).

| Route | Purpose |
|---|---|
| `GET`/`POST` `/doctor/login` | login form / submit (username + password, `doctor` guard) |
| `POST` `/doctor/logout` | |
| `GET` `/doctor/dashboard` | the doctor's own `task_instances`, with pending/assigned/completed counts and status filter |
| `GET`/`PUT` `/doctor/profile` | view/edit own name, email, phone, password |
| `PUT` `/doctor/task-instances/{id}` | mark own case complete (403 if it's not theirs) |

Not wrapped in a `guest:doctor` middleware on the login route: Laravel's
default `RedirectIfAuthenticated` redirects to the named route `dashboard`
**regardless of which guard triggered the check** — so an already-logged-in
doctor hitting `/doctor/login` would've been bounced to the *staff*
dashboard (a route their guard can't pass), landing them back at the staff
`/login` in a confusing loop. Simplest correct fix: the doctor login page
just has no guest-only gate — visiting it while already logged in just
re-shows the form, which is harmless.

Verified end-to-end (2026-08-18): logged in as a doctor, saw their real
assigned task on the dashboard, marked it complete (`completion_date`
auto-stamped), confirmed the activity log correctly attributed the action
to the doctor (see `ActivityLogger::currentActor()` — now checks the
`web`, `doctor`, and `sanctum` guards explicitly rather than relying on
`auth()->user()`'s default-guard resolution, after that resolution turned
out to behave in a way that worked for this case but wasn't something to
depend on going forward).

## Role-gated web routes

`app/Http/Middleware/EnsureUserHasRole.php` (alias `role:...`) is applied in
`routes/web.php`:

| Roles allowed | Routes |
|---|---|
| any authenticated user | `/dashboard`, `/profile` |
| `super_admin`, `admin`, `editor` | `doctors.*`, `patients.*`, `tasks.*`, task-instance actions |
| `super_admin`, `admin` | `education-types.*`, `stages.*`, `departments.*`, `activity-logs.*`, `permissions.*`, `department-roles.*` |

This is the coarse gate (which pages a role can reach). See "Granular
permissions" below for the finer-grained layer on top (which *actions* a
specific user can take within a page they can already reach).

## Granular permissions

The imported schema has a confusing amount of permission-table surface
area: `roles`, `permissions`, `role_permissions`, `user_permissions`,
`department_permissions`, `department_role_assignments`,
`department_role_activity_log`, `role_stage_department_permissions`,
`user_stage_department_permissions`, `user_allowed_departments`,
`user_allowed_stages`, `user_allowed_education_types`. Rather than guess
which of these matter, a research pass grepped the entire original
codebase for actual reads/writes against each one. Verdict:

| Table | Status | Ported? |
|---|---|---|
| `user_permissions` | **Live** — the real per-user module/action grant store, read by `includes/PermissionManager.php` + `permission_helper.php`, checked in 14+ real pages (navbar, admin header, several ajax CRUD endpoints) | ✅ `UserPermission` model + `App\Services\PermissionManager` |
| `department_role_assignments` | **Live**, has real data — senior/HR role per department+stage, written by `admin/department_roles_ajax/*`, read for dashboard filtering and senior-presence badges | ✅ `DepartmentRoleAssignment` model |
| `department_role_activity_log` | **Live** (audit trail) — written on assign/toggle, never read back by any original page | ✅ `DepartmentRoleActivityLog` model, logged on assign/toggle here too |
| `user_allowed_departments` / `_stages` / `_education_types` | **Live** — read by `includes/scope_helper.php` to filter what a non-admin user can see, written by `admin/user_permissions_ajax/save_scope_permissions.php` | ✅ `App\Services\ScopeHelper` (query-builder helper, not models — these are pure composite-key pivot tables with no `id` column) |
| `roles`, `permissions`, `role_permissions` | **Orphaned parallel system** — only used inside a self-contained `admin/role_ajax/*.php` CRUD screen; **nothing in real access control ever reads them**. Actual role gating uses the `users.role` enum + session checks, not this table | ❌ not ported — porting it would mean building a second, unused permission system, same mistake the original made |
| `department_permissions` | **Dead** — 0 data rows, only referenced by a one-off table-creation script (`admin/setup_department_roles.php`) | ❌ not ported |
| `role_stage_department_permissions` | **Dead** — zero PHP references anywhere, zero data rows | ❌ not ported |
| `user_stage_department_permissions` | **Dead for access control** — has data rows but zero PHP file reads/writes it; orphaned the same way `tv_queue` turned out to be (see "TV waiting-room board" above) | ❌ not ported |

**A real bug in the original, fixed here**: `department_role_assignments`
has two redundant status columns, `is_active` (tinyint) and `status`
(enum). The original's admin UI (`save_role_assignment.php`) only ever
writes `status`; three of its own read paths (`dashboard.php`,
`get_department_tasks.php`, `get_senior_presence.php`) filter on
`is_active`, while `PermissionManager`'s own `hasDepartmentRole()` filters
on `status`. Net effect: deactivating a role via the admin UI does not
actually revoke it wherever `is_active` is what's checked. `DepartmentRoleAssignment`
here treats `status` as the single source of truth and keeps `is_active` in
sync on every save (`static::saving()` hook) — both columns always agree
now, without a schema migration.

**Important semantic carried over correctly** (easy to get backwards):
a user with **zero** rows in `user_allowed_departments` (etc.) is
**unrestricted** — sees everything — not locked out. Restriction only
starts once at least one row exists for that user. `ScopeHelper` implements
this the same way the original does. Only `super_admin` is unconditionally
unrestricted (see "Academic stages" section below — an earlier version of
this port also exempted `admin`, which was a real deviation from the
original and has been fixed).

**What's wired up**: `permission:module,action` middleware
(`EnsureUserHasPermission`), layered *on top of* (not instead of) the
`role:` middleware. Initially applied to `destroy` only, on the 6 resources
above (`delete` chosen first as the highest-value/irreversible action).
**Extended (2026-08-19) to every action on every module in
`UserPermissionController::MODULES`** — `view` (index/show), `create`
(create/store), `edit` (edit/update), `delete` (destroy), plus `export` on
`doctors-export` — using `Route::resource(...)->middlewareFor($methods,
$middleware)` (Laravel 11+), one call per action group, both in
`routes/web.php` and mirrored in `routes/api.php` (the API previously had
**zero** `permission:` gating at all — a Flutter client could bypass every
grant a web session was blocked by; now identical to the web routes).
Also fixed a real gap found while doing this: **`departments` has been in
`MODULES` since the permission matrix was built, but no route ever actually
checked it** — the matrix UI could grant/revoke a `departments` permission
that enforced nothing. Now gated the same as the other six.

Because `PermissionManager::can()` only bypasses for `super_admin` (not
`admin` — see its docblock), this is a real behavior change for any
non-`super_admin` `admin` user: they now need an explicit grant for
`view`/`create`/`edit` on these modules too, not just `delete`. Consistent
with how `delete` already worked (verified in this same section below), not
a new inconsistency — but worth knowing before deploying with real `admin`
accounts that have never been granted anything.

**A crash bug found and fixed while wiring this**: `EnsureUserHasPermission`
built `new PermissionManager($user)`, and `PermissionManager`'s constructor
requires a `User` — fine on the web routes (always the `web` guard, always
a `User`), but the API's Sanctum guard is shared with `Doctor` tokens (see
"Auth model" above). A doctor's own token hitting a newly-gated API route
would have `TypeError`'d instead of cleanly 403ing. Fixed by checking
`$user instanceof User` first and denying otherwise — `role`/
`user_permissions` are a staff-only concept, matching how `ScopeHelper`
already treats the same dual-guard situation.

**Another latent bug found in the same pass**: `Route::resource('appointments',
AppointmentController::class)->except('destroy')` registered a `show` route,
but `AppointmentController` has no `show()` method — `Route::resource()`
doesn't validate this at registration time, so `GET /appointments/{id}`
would have thrown `BadMethodCallException` if anything had ever hit it.
Never triggered (no `Show.vue`, nothing calls `route('appointments.show')`),
but real. Fixed by excluding `show` from that resource too (the API
`Api\AppointmentController` **does** implement `show()`, so its route was
left alone).

**Web UI**: `/permissions` lists staff users → `/permissions/{user}` is a
module × action checkbox matrix (`doctors`/`patients`/`tasks`/
`departments`/`appointments`/`dental-charts`/`payments` × `view`/`create`/
`edit`/`delete`/`export`) saved in one batch. `/department-roles` assigns/
deactivates/removes senior-or-HR-per-department-and-stage. Both
`super_admin`/`admin` only. API: `GET`/`PUT /api/v1/permissions/{user}`
(same shape).

Verified end-to-end (2026-08-18): an `editor` user without any grant got
`403` deleting a doctor; an admin granted `doctors.delete` via the matrix
UI; the same editor immediately succeeded (grant cache correctly
invalidated via `PermissionManager::forget()`) and the doctor was actually
deleted, with the redirect correctly landing on `/doctors` (not
`/api/v1/doctors` — the route-name-collision fix holds here too). Repeated
for `patients.delete` after extending the middleware to the other five
resources: blocked without the grant, succeeded and redirected correctly
after granting it. Separately verified: assigning a department role writes
a correctly-`is_active`-synced row and a real activity-log entry; toggling
it to inactive flips both status columns together.

**A second table-name bug found via this same testing**: `DepartmentRoleActivityLog`
initially had no explicit `$table`, so Eloquent guessed the plural
`department_role_activity_logs` — the real table (confirmed against the
imported schema) is singular, `department_role_activity_log`. First
department-role assignment attempt threw `Base table or view not found`;
fixed by setting `protected $table` explicitly. Listed here because it's
the same class of mistake as the heredoc-interpolation and route-name-collision
bugs above: assuming a Laravel default instead of checking the real schema.

## Academic stages (education types / stages / departments) — audit and fixes (2026-08-18)

Requested review of "الفصول الدراسية" (academic stages) — `stages`,
`education_types`, and their cascade into `departments`/`doctors`/`tasks`/
`patients`. Verified against both the imported schema and the original
app's real controllers (`admin/manage_doctors.php`, `admin/manage_tasks.php`,
`admin/ajax/{doctors,departments,education_types}_crud.php`,
`admin/ajax/get_stages_list.php`, `includes/scope_helper.php`), not assumed.
Found and fixed four real gaps:

1. **Doctor form's stage dropdown wasn't filtered by education type.** The
   original AJAX-filters it (5 near-duplicate `get_stages_by_edu.php`
   variants across the app, all doing the same thing — a deliberate,
   pervasive pattern, not a one-off). `Doctors/Create.vue` and `Edit.vue`
   were showing every stage regardless of the selected education type,
   so a doctor could be saved with a stage/education-type combination that
   doesn't exist together. Fixed client-side (no extra request needed —
   the full `stages` list is already in props): a `filteredStages` computed
   narrows the options to `stage.education_type_id === form.education_type_id`,
   and a watcher clears `stage_id` if it becomes invalid after changing
   education type. The stage `<select>` is disabled until an education type
   is chosen. *(`Patients/Create.vue` and `Tasks/Create.vue` do **not** need
   this — verified against `database/schema_import.sql`: neither `patients`
   nor `tasks` has an `education_type_id` column at all, so there was
   nothing to filter by for those two forms — an initial broader claim from
   research turned out to be wrong on inspection of the actual schema.)*

2. **Task form's department dropdown wasn't filtered by stage.** The
   original's task browser (`admin/manage_tasks.php`) cascades
   education type → stage → department (`get_departments_by_stage.php`).
   `tasks` has no `education_type_id` column, but `departments.stage_id`
   is real, so `Tasks/Create.vue`/`Edit.vue` now filter the department list
   by the selected stage the same way (`filteredDepartments`, department
   field reordered after stage to match the cascade), keeping departments
   with a `null` `stage_id` always selectable since that column is nullable.

3. **`ScopeHelper::allowedDepartmentIds/allowedStageIds/allowedEducationTypeIds`
   exempted both `super_admin` and `admin` from scoping — the original
   (`includes/scope_helper.php`) only ever exempts `super_admin`.** This was
   a genuine behavioral deviation, not a stylistic one: an `admin`-role user
   with rows in `user_allowed_stages`/`_education_types`/`_departments`
   should have been restricted and wasn't. Fixed by checking `role ===
   'super_admin'` only, matching the original exactly.

4. **The scoping was built (`ScopeHelper`) but never actually applied
   anywhere** — `scopeDepartments`/`scopeStages` had zero call sites in the
   whole app; the entire access-scoping feature was inert. Wired it into
   the four places the original actually scopes reads (verified via a full
   grep of the original for every `user_allowed_*`/`getUserAllowed*`
   call site — `patients`/`tasks` listings are confirmed **not** scoped in
   the original either, so left alone): `EducationTypeController::index`,
   `StageController::index` (stage-id restriction takes priority, falls
   back to education-type restriction if the user has none — mirrors
   `admin/ajax/get_stages_list.php`'s branching exactly), `DepartmentController::index`
   (department id + education type + stage, all AND'd, per
   `getDepartmentScopeFilter()`), and `DoctorController::index`
   (education type + stage, per `doctors_crud.php`). Added a missing
   `ScopeHelper::scopeEducationTypes()` (only `scopeDepartments`/`scopeStages`
   existed before). Mirrored on the API side too (`Api\DoctorController::index`,
   `Api\LookupController`'s three lookup endpoints) so a Flutter session
   can't see more than the equivalent web session — required a small
   change to `ScopeHelper`'s `scope*` methods to accept any `Authenticatable`
   and no-op for a `Doctor` principal (not just `User`), since `/api/v1` is
   a shared Sanctum guard between staff and doctor tokens and `role`-based
   scoping is a staff-only concept in the original (doctors never had a
   `$_SESSION['role']`).

   Verified end-to-end via `tinker` against real data (not mocked): created
   a temporary `admin`-role user restricted to one education type via
   `ScopeHelper::setAllowedEducationTypes()`; confirmed they saw only that
   education type (1 of 2), only the one stage under it (1 of 4, via the
   fallback branch — the user had no direct stage restriction), zero of
   nine departments (correct — all nine real seeded departments belong to
   the *other* education type), and — after creating two temporary test
   doctors, one in each education type — exactly the one in their allowed
   education type. Confirmed `super_admin` stays fully unrestricted. Confirmed
   a `Doctor` principal doesn't crash `ScopeHelper::scopeDepartments()` (the
   dual-guard API safety fix). All temporary test rows deleted afterward.

## Academic sessions, groups, and required/done/remaining task tracking (2026-08-18)

Built from scratch — the `academic_sessions` table existed in the imported
schema with zero Laravel representation (no model, controller, routes, or
UI) despite being live-used in the original for a whole subsystem (47 real
PHP files touch `user_allowed_*`/session tables, per a dedicated research
pass over `includes/SessionHelper.php`, `admin/manage_sessions.php`,
`admin/manage_groups.php` and its ~15-file ajax family, and the several
required/done/remaining task-progress screens). Ported the modern, real
paths; deliberately skipped confirmed-superseded duplicates (see below).

**`academic_sessions`** (`id, name, start_date, end_date, is_active,
is_current`) — three distinct, easy-to-conflate concepts carried over
exactly from `SessionHelper.php`: `is_active` (soft-enable), `is_current`
(exactly one system-wide default), and a per-browser-session *"selected"*
session (which admin session you're currently viewing, independent of
`is_current`) — the original stores this in `$_SESSION['academic_session_id']`
with a 3-level fallback (selected → current → latest active); ported as
`App\Services\AcademicSessionHelper::resolve()`, same fallback order, using
Laravel's session instead. `AcademicSessionController`: full CRUD +
`setCurrent` (clears the flag elsewhere first) + `select` (sets the viewing
session without touching `is_current`) + `show` (per-session stats page).
**Delete guard ported exactly**: refuses to delete a session with any
linked `groups` or `tasks` (suggests deactivating instead), and the current
session can't be deleted at all — verified via `tasks()`/`groups()` counts
in a rolled-back test transaction.

**Groups** (`groups`, `group_slots`, `doctor_group_members`) — a group
belongs to one `stage_id` (required) and optionally one `academic_session_id`
(nullable — legacy/global groups with no session show up under every
session, ported via `where(academic_session_id = ? OR NULL)`, matching
`load_groups.php` exactly). **Business rule ported exactly**: a doctor
belongs to only one group at a time, enforced at the application layer
(delete-then-insert on `doctor_group_members`, not a DB constraint) in both
`GroupController::addDoctors` and its API mirror — matches
`add_multiple_doctors_to_group.php`. ⚠️ **This rule was later narrowed to
"one group *per academic session*"** — as originally ported it destroyed
previous years' membership history. See
"[Doctors, groups and tasks tied to an academic session](#doctors-groups-and-tasks-tied-to-an-academic-session-2026-08-19)"
below. Only the modern multi-select
doctor-management flow was ported; the original also has an older
single-add form (`load_group_doctors.php` / `get_doctors_by_group.php`)
explicitly superseded by the multi-select modal — not ported, per the
same "build the evidently-intended correct version, not every legacy
duplicate" approach used for the specialty forms and permission tables
elsewhere in this doc. `admin/groups.php` (day-of-week doctor rostering,
`doctor_groups` table) is a **separate, unrelated legacy feature** — not
this module, not ported.

**Required / done / remaining task computation** — `tasks.required_count`
is the target; `task_instances` rows are the actual slots, bucketed by
`status` (`pending`/`assigned`/`completed`). Ported the aggregate form used
by `task_progress_view.php`'s SQL (`COUNT`/`SUM(CASE …)` per task, grouped),
extended one level further to a **session-wide** total for the
`AcademicSessions/Show` stats page: `required = Σ required_count`,
`done = Σ completed instances`, `remaining = Σ max(0, required_count −
completed)`, computed only over tasks explicitly tied to that session's id
(not the `OR NULL` leak used for listing/assignment screens — a NULL-session
task showing up on *every* session's stats page would make the page
meaningless, so this is a deliberate scoping choice for the stats view
specifically, documented here rather than guessed). Verified end-to-end in
a rolled-back test transaction: a session with 1 group (2 doctors), 1 task
(`required_count=3`) with one `completed` and one `assigned` instance
correctly computed `doctors=2, groups=1, required=3, done=1, remaining=2`.

**A real inconsistency in the original, not replicated**: session-scoping
of task-progress queries is inconsistent across the original's own files —
some (`doctor/required_tasks.php`, `admin/doctor_task_progress.php`,
`tasks_ajax/get_tasks.php`) filter by the active session, others
(`admin/ajax/get_group_doctors.php`, `task_progress_view.php`,
`doctor/progress.php`) don't, evidently because session support was
retrofitted onto some screens and not others. This port always scopes by
session where a session concept applies, rather than reproducing the gap.

**A real bug caught by testing empty-state, not just happy-path**:
`AcademicSessionHelper::resolve()` originally used `firstOrFail()` on "no
selected/current session found" — correct once at least one session
exists, but on a **fresh install with zero `academic_sessions` rows**
(true of this app until an admin creates the first one) it threw
`ModelNotFoundException`, 500-ing both `AcademicSessions/Index` and
`Groups/Index` before a single session could ever be created — a bootstrap
deadlock. Caught by directly invoking the controllers against the actual
(empty) dev database rather than only testing after seeding data. Fixed by
making `resolve()`/`resolveId()` nullable and having callers treat "no
session yet" as a valid state (`GroupController::index` simply skips the
session filter; the sessions page shows `selectedSessionId: null`).

**API**: `Api\AcademicSessionController` and `Api\GroupController` mirror
the web controllers. Because Sanctum tokens are stateless, there's no
"selected session" to persist for the Flutter client — `show()` always
reflects the session id in the URL, and `POST /groups` accepts an optional
`academic_session_id` (falls back to whichever session has `is_current=true`
if omitted) instead of reading a browser session. Documented here as a
deliberate adaptation for a stateless client, not a guess.

**Nav**: added as two more tabs on the existing `StructureTabs` component
(alongside Education Types / Stages / Departments) — `/academic-sessions`
and `/groups`, both `role:super_admin,admin`, consistent with how the other
structural-data screens are gated.

## Flash error messages were silently dropped (2026-08-19)

`HandleInertiaRequests::share()` only ever shared `flash.success` — the
Academic Sessions delete-guard (`AcademicSessionController::destroy()`,
`->with('error', ...)` on both the "current session" and "linked
groups/tasks" rejection paths) set a real session flash message that never
reached the page, so a blocked delete just silently did nothing with no
explanation. Fixed by sharing `flash.error` too. Verified end-to-end in a
rolled-back transaction: triggered the "can't delete the current session"
guard, confirmed the middleware's `share()` now surfaces the exact message.

## Clinic settings (2026-08-19)

Ported `admin/clinic_settings.php` — a single-row `clinic_settings` table
(`ClinicSetting` model, always `id=1`, `ClinicSetting::current()` does
`firstOrCreate` with the same defaults as the original's own bootstrap
logic). **MikroTik fields (`mikrotik_ip/user/pass/ssh_port`) and
`jwt_secret_key` exist on the real imported table but are deliberately
excluded from `$fillable` and every form** — out of scope by explicit
request, same exclusion as the MikroTik backup feature elsewhere in this
rebuild; `jwt_secret_key` is an internal secret column nothing in this
Sanctum-based rebuild reads. Everything else ported: clinic name/description/
logo/address/phone/email/website/working-hours/currency/timezone,
university+college name (used in case-sheet print headers per the
original's own field labels) with their own logo upload, and the three
notification toggles. Logo uploads use this rebuild's established
`Storage::disk('public')` convention (matching doctor profile photos),
not the original's `uploads/` folder.

**A real bug caught by testing, not assumed**: `ClinicSetting::$fillable`
initially omitted `id` — harmless for every other model in this rebuild
(auto-increment columns don't need `id` mass-assignable), but
`clinic_settings.id` is `NOT NULL` with **no** auto-increment or default
(the original always explicitly `INSERT`s `id=1`) — so the very first
`firstOrCreate()` call threw `Field 'id' doesn't have a default value`
instead of creating the row. Fixed by adding `id` to `$fillable`.

**A second bug caught in the same pass**: `clinic_logo`'s real column
default is the literal string `'default-logo.png'` — a filename that
existed in the *original* PHP app's `uploads/` folder, not anywhere in
this Laravel app's storage. A freshly-created settings row (before anyone
uploads a logo) would carry that stale filename, and naively building a
`Storage::url()` from it produces a URL to a file that was never actually
written here — a broken image, both in the settings form and in the nav
logo added below. Fixed by having `logoUrl()`/`universityLogoUrl()` check
`Storage::disk('public')->exists()` first and return `null` otherwise
(falls back to the static SVG logo in the nav). Verified directly: a model
instance holding `clinic_logo = 'default-logo.png'` with no such file on
disk correctly returns `null`.

**Shared app-wide via Inertia** (`HandleInertiaRequests::share()`,
`clinicSettings: { name, logo_url }`, wrapped in `once()` so pages that
never touch the nav don't pay the query) — mirrors the original's
`ClinicSettings` helper being read on every `navbar.php` render. The nav
logo (`AuthenticatedLayout.vue`) now shows the uploaded logo + clinic name
next to it when set, falling back to the static `ApplicationLogo` SVG
otherwise (never broken, per the bug above).

**Access**: `role:super_admin,admin`, no separate `permission:` gate —
`'settings'` was never added to `UserPermissionController::MODULES` (the
original requires a `settings.edit` permission via a different,
non-`user_permissions`-backed `$perm` object not covered by this rebuild's
permission-table research). Reachable from the profile dropdown (desktop)
and the mobile menu, labeled "الإعدادات" matching the original. API:
`GET`/`PUT /api/v1/clinic-settings` (branding info for a Flutter
about/splash screen).

**Deliberately not ported** (flagged for a decision, not silently built or
skipped): `admin/register_settings.php` (register-day/service settings —
real and read by `patient_register.php`, but that whole flow is itself
flagged below) and `admin/patient_register.php` (writes to a *different*
table, `patients_admin` — a parallel lightweight intake/waitlist form, not
the same feature as this rebuild's real `patients` CRUD; building it would
create two disconnected patient lists, so it needs a product decision, not
an assumption).

## Case sheet types management (2026-08-19)

Audited the remaining unported `admin/*.php` pages (a research pass read
each candidate file directly and checked `includes/navbar.php` for whether
it's actually linked, rather than assuming from the filename) to find what
else is genuinely live and missing. Findings, so this isn't re-litigated
later: `view_reports.php`, `login_as_doctor.php`/`logout_from_doctor.php`,
and `assign_tasks.php` are only linked from `admin/admin_navbar.php`, a
retired navbar file superseded and no longer `require`d anywhere per the
codebase's own `NAVBAR_UNIFICATION_SUMMARY.md` — orphaned, not ported.
`print_doctor_card.php`/`print_doctors.php` are real contextual print
views (doctor ID card, filtered roster) triggered from buttons, not nav
links — lower priority, not built yet. `clinic_settings.php` /
`register_settings.php` are real and read app-wide (logo/name in every
navbar render, register-day options feeding `patient_register.php`) but
`clinic_settings` mixes in MikroTik connection fields, which are
out-of-scope by explicit request — porting it needs those fields excluded,
not done yet. `patient_register.php` writes to `patients_admin`, a
*different* table from the `patients` table this rebuild already uses (see
"Patients" module note on why `patients_admin`/`patients_simple` were
deliberately not chosen) — a parallel lightweight intake/waitlist flow, not
a duplicate of the same feature; building it would mean two disconnected
patient lists, so it's flagged rather than silently built or skipped.

**`case_sheet_manager.php` was live, real, and missing** — `CaseSheetType`
already had a model (used only as a read-only dropdown in task creation),
but no actual CRUD screen existed. Ported `admin/ajax/case_sheet_types_crud.php`'s
real logic: `type_code` immutable after creation (validated
`^[a-z0-9_]+$`, unique, only settable on create), `display_order` auto-set
to `max+1` on create, delete blocked with an exact count message if any
`tasks` row references the type (`Can't delete this type — it's used by N
task(s).`) — verified in a rolled-back test transaction (blocked while a
task referenced it, succeeded immediately after removing that task). The
original's AJAX backend also implements a bulk `update_order` reorder
action, but its own front-end has no drag-handle UI wired to it (confirmed
via the research pass) — not ported, same "build what's actually reachable
today, not every latent API capability" approach used for the specialty
forms and permission tables elsewhere in this doc.

Added as a sixth item in the "إدارة البيانات الأساسية" nav dropdown (both
desktop and the mobile menu) — `أنواع النماذج السريرية`. Gated
`role:super_admin,admin` matching the original AJAX backend's own check
exactly (not `editor` — the navbar's `canView('tasks', ...)` permission
check is link-visibility only, the backend never actually enforced it, so
the port matches what the backend enforces, not the more decorative navbar
gate). API: standard REST at `/api/v1/case-sheet-types`.

## Admin task progress ("إدارة تقدم المهام") (2026-08-19)

The original has **two different** task-progress screens, and only the
per-doctor one had been ported (see the section below). This is the other:
`admin/task_progress_view.php` + `admin/ajax/get_group_doctors.php` — a
browse-and-act screen, not a report.

**The flow, ported exactly**: filter by day → education type → stage;
the day filter lists only days that some `group_slots` row actually uses,
in the original's explicit week order (`FIELD(day, 'الأحد', …)`, not
alphabetical); groups shown are those with a slot on that day. Picking a
group loads a **department-tabbed matrix**: one tab per department of that
group's stage, each showing every doctor in the group as a row with
`المطلوب / مكتملة / قيد التنفيذ / معلقة / غير مخصص` counts. Expanding a
doctor row reveals one **task card per required slot**.

**The slot model is the subtle part** and is ported as-is: a task with
`required_count = N` renders N cards per doctor, and the doctor's own
instances for that task fill slots by *position* (`instances[$slot]`) —
there is no per-slot FK in the schema, it's purely positional, exactly as
the original does it. A slot with no instance shows as `لم تبدأ بعد`
(`'unassigned'` — **a computed state, not a DB status**, since
`task_instances.status` only has `pending`/`assigned`/`completed`), and
`غير مخصص = Σ max(0, required_count − existing instances)`.

**Actions ported with their real server-side guards** (from
`assign_task_ajax.php` / `mark_task_completed.php` /
`update_task_instance.php`), not just the happy path:
- **بدء المهمة** — `required_per_doctor` falls back to `required_count`
  when unset; refuses once the doctor has already *completed* their
  required number; when the global `pending` pool is empty it lazily
  creates **one** instance rather than pre-creating all N (the original
  comments this as deliberate, to avoid overproduction).
- **تأشير كمكتملة** — a grade may only be set when the task itself defines
  one (`tasks.grade`), and may never exceed it; a task with no grade can
  still be completed, just without a grade. The grade field disables
  itself in that case, matching the original's own UI.
- **تعديل** — notes + grade on an existing instance, same grade rules.

Also ported: the doctor search box (name or username, filtering within the
active department tab) and the four status filter buttons
(`الكل / غير منجزة / قيد التنفيذ / مكتملة`), where `pending` and
`unassigned` both bucket into "not started" as in the original.

**Not ported**: the QR-scanner modal on this page (camera scanning is
deferred to the Flutter client — see "Not yet built"), and the print views
(`task_progress_print.php`), which are a separate feature.

The group matrix is fetched as JSON (`GET /task-progress/groups/{group}`)
and re-fetched after every start/complete/edit, mirroring how the original
reloads `get_group_doctors.php` after each action — expanded rows and the
active tab are preserved across the refresh.

Verified end-to-end with real seeded data in a rolled-back transaction: a
2-doctor group with one task (`required_count=2`, `grade=20`) and one
completed instance produced exactly `TP Doc One: req=2 done=1 unassigned=1`
with slot 1 `completed` (grade 18) and slot 2 `unassigned`, and
`TP Doc Two: req=2 unassigned=2`; starting a task for the second doctor
created and assigned one instance; completing it with `grade=50` was
correctly **blocked** ("can't exceed the task's grade (20.00)") with the
status left untouched; completing with `grade=15` succeeded and persisted
the grade and notes.

## Doctor task progress ("تقدم مهام الطبيب") (2026-08-19)

Reported missing ("تقدم المهام غير موجود") — correct: the session-wide
aggregate stats above existed, but the actual per-doctor **browsable**
progress screen (`admin/doctor_task_progress.php`) was never ported. Built
`DoctorTaskProgressController@show` (`GET /doctors/{doctor}/progress`,
named `doctors.progress`) matching the original's real query and grouping
logic exactly: all of a doctor's `task_instances`, session-scoped
(`t.academic_session_id = activeSessionId OR NULL`, same pattern as
elsewhere), grouped by `task_id`, each group carrying `required_count` from
the task and `completed`/`remaining = max(0, required_count − completed)`
computed the same way as the session stats page. Doctor info card includes
their current group (via `Doctor::groups()`, session-scoped the same way).
Stats cards (total/completed/in-progress/pending) plus an overall progress
bar, then one card per task with its own progress bar and an instance table
with Mark Complete / Undo Complete actions — reuses the existing
`TaskInstanceController::update` route rather than porting the original's
separate `ajax/toggle_task_instance.php` endpoint (no need for a second
endpoint that does the same `status` update).

**A real bug fixed while porting this**: the original's "uncomplete" action
(`toggle_task_instance.php`) clears `completion_date` back to `NULL` when
reverting a `completed` instance to `assigned`; `TaskInstanceController::update`
(both web and API) only ever *set* `completion_date` on the way to
`completed` and never cleared it on the way back out, so un-completing a
task left a stale completion timestamp on an instance that was, by its
`status`, no longer complete. Fixed in both controllers; verified with a
real instance in a rolled-back test transaction (`completed` →
`update(status: assigned)` → confirmed `completion_date` is `NULL`).

**Access**: matches the original's own check exactly
(`in_array($_SESSION['role'], ['admin', 'super_admin'])`) — `role:super_admin,admin`
only, *not* `editor`, unlike the rest of the `doctors.*` routes. Reachable
from a "Progress" link on `Doctors/Index.vue` (hidden for `editor`, since
their role can't pass the route's own gate) and from each doctor listed in
`Groups/Index.vue`. **API**: `GET /api/v1/doctors/{doctor}/progress`,
gated `permission:doctors,view`, optional `?academic_session_id=` (falls
back to `is_current`, same stateless-API pattern as the rest of the
Academic Sessions work).

Verified end-to-end with real data in a rolled-back transaction: a doctor
with 2 tasks (required_count 3 and 1) and 3 instances (1 completed, 1
assigned, 1 pending) correctly produced `stats: {total:3, completed:1,
assigned:1, pending:1}` and per-task `remaining: 2` / `remaining: 1`.

## Navigation bug: the mobile menu was missing most admin modules (2026-08-19)

Reported as "education types / stages / departments management doesn't
appear in Laravel." Backend was verified fully correct first (controllers
invoked directly with no errors, `GET /education-types` etc. correctly
302-redirect to `/login` when unauthenticated, both on `localhost` and over
the LAN IP) — so the report wasn't a server bug. Asked the user to clarify;
they were on a **phone**, and a screenshot of the mobile hamburger menu
confirmed the real issue: it only ever listed Dashboard/Doctors/Patients/
Tasks/Dental Charts/Appointments/Payments — **Clinical Records, the
Education Types/Stages/Departments/Academic Sessions/Groups group, Activity
Log, and Permissions were never in the mobile menu at all**. Every module
added over the course of this rebuild got a desktop `NavLink`
(`AuthenticatedLayout.vue`'s `sm:flex` row) but nobody ever added the
matching `ResponsiveNavLink` in the `sm:hidden` mobile panel below it — so
a phone user (below the `sm:` breakpoint, i.e. every phone) had no way to
reach roughly half the app. Desktop testing throughout this rebuild never
would have caught this, since the two menus are separate markup blocks with
no shared source of truth.

Fixed by adding all four missing entries to the mobile menu, plus — since
the user was already asking specifically for the education-types/stages/
departments group — renamed the desktop "Structure" link to match the
original app's actual nav label. `includes/navbar.php` calls this dropdown
"إدارة البيانات الأساسية" containing "أنواع التعليم / المراحل / الأقسام";
the port had it as a single English "Structure" link, which is presumably
why the report happened even before the mobile-menu gap was found — a user
who knows the original by its real name wouldn't necessarily connect
"Structure" to it. The desktop version is now a real dropdown
(`Components/Dropdown.vue` + `DropdownLink.vue`, reused from the existing
profile-menu pattern) with the original's Arabic labels, extended with
Academic Sessions ("الأعوام الدراسية") and Groups ("المجموعات") since they
belong to the same admin data-management group. The mobile version
flattens the same five links under an "إدارة البيانات الأساسية" heading
(a nested dropdown-in-a-dropdown reads badly on mobile), plus the
previously-missing Clinical Records/Activity Log/Permissions links,
all still gated by the same `role` checks as their desktop counterparts.

## Web app (Inertia) — modules built so far

| Module | Controller | Pages | Notes |
|---|---|---|---|
| Doctors | `DoctorController` | `Doctors/{Index,Create,Edit}.vue` | full CRUD; profile photo upload (see "File uploads") |
| Doctor import/export | `DoctorImportExportController` | `Doctors/Import.vue` | Excel bulk import + export (see "Doctor Excel import/export") |
| Patients | `PatientController` | `Patients/{Index,Create,Edit}.vue` | full CRUD, against the `patients` table (the one actually referenced by `appointments`/`surgeries` FKs — not `patients_admin` or `patients_simple`, which are separate/simpler tables in the same schema) |
| Education Types | `EducationTypeController` | `EducationTypes/Index.vue` | inline create + modal edit |
| Stages | `StageController` | `Stages/Index.vue` | inline create + modal edit |
| Departments | `DepartmentController` | `Departments/Index.vue` | inline create + modal edit |
| Tasks | `TaskController` | `Tasks/{Index,Create,Edit,Show}.vue` | task **definitions** (department + case-sheet-type + stage + title + required counts) |
| Task assignment | `TaskInstanceController` | (inline on `Tasks/Show.vue`) | assign a task to a doctor, mark complete + grade, remove |
| Dental Charts | `DentalChartController` | `DentalCharts/{Index,Form,Show}.vue` | full CRUD against `dental_charts`; interactive FDI-notation tooth picker (`Components/ToothSelector.vue`) writing to the real `tooth_data` JSON column |
| Appointments | `AppointmentController` | `Appointments/{Index,Form}.vue` | full CRUD + pin/unpin toggle; see "Appointments" below for a schema/code contradiction this surfaced |
| Payments | `PaymentController` | `Payments/{Index,Create}.vue` | create/list/delete against one appointment at a time |
| Activity Log | `ActivityLogController` | `ActivityLogs/Index.vue` | read-only, filterable by module/action/search; see "Activity logging" below |
| TV board (public) | closure in `routes/web.php` | `TvBoard.vue` | no auth; polls `GET /api/v1/tv-board` client-side every 20s |
| Doctor area (`doctor` guard) | `Doctor\{DashboardController,ProfileController,TaskInstanceController}` + `Auth\DoctorAuthenticatedSessionController` | `Auth/DoctorLogin.vue`, `Doctor/{Dashboard,Profile}.vue`, `Layouts/DoctorLayout.vue` | doctors' first web UI (previously API-only); see "Doctor web area" below |
| Clinical specialty records (×12) | one controller per table (e.g. `PeriodontalChartController`) | `ClinicalRecords/Index.vue` (hub) + shared `Specialty/{Index,Form,Show}.vue` | generic field-driven forms, not 12 bespoke ones — see "Clinical specialty records" below |
| User Permissions | `UserPermissionController` | `Permissions/{Index,Edit}.vue` | module × action grant matrix; see "Granular permissions" below |
| Department Roles | `DepartmentRoleAssignmentController` | `DepartmentRoles/Index.vue` | senior/HR-per-department-and-stage; see "Granular permissions" below |
| Academic Sessions | `AcademicSessionController` | `AcademicSessions/{Index,Show}.vue` | CRUD + set-current + per-session stats (students/groups/required-done-remaining tasks); see "Academic sessions" below |
| Groups | `GroupController` | `Groups/Index.vue` | groups + weekly slots + doctor membership management; see "Academic sessions" below |

⚠️ Deleting an **Education Type** cascades — the original schema has
`ON DELETE CASCADE` foreign keys from `departments.education_type_id` and
`doctors.education_type_id` to `education_types.id`. Deleting an education
type deletes its departments and doctors too. This is inherited schema
behavior, not something added here; the delete confirmation in
`EducationTypes/Index.vue` says so.

## The task system — which tables are actually used

The schema has **five** task-related tables inherited from the original app:
`tasks`, `task_instances`, `task_assignments`, `task_progress`,
`doctor_tasks`, `doctor_task_progress`. Rather than guess which to build
against, the original PHP codebase (`dental_clinics2/`) was grepped for
actual usage:

- **`tasks`** + **`task_instances`** are used pervasively — doctor pages
  (`required_tasks.php`, printing pages, `progress.php`), and admin pages
  (`task_progress_view.php`, `assign_task_ajax/*`, `get_task_instance_data.php`,
  etc.). `task_instances.status` (`pending`/`assigned`/`completed`) plus
  `grade` is the real workflow state.
- **`doctor_tasks`** is used by exactly one file
  (`admin/assign_task_ajax/assign_task_process.php`) as a simpler
  doctor↔task target-tracking table, seemingly a parallel/older mechanism.
- **`task_assignments`**, **`task_progress`**, **`doctor_task_progress`**
  had no `SELECT`/`INSERT`/`UPDATE` hits against them in the codebase search.

**Decision**: this rebuild's Task module (`Task`, `TaskInstance` models and
their controllers) is built against `tasks` + `task_instances` only, since
that's the pair with verified, pervasive real usage. The other four tables
are imported (schema fidelity) but have no models/controllers here yet.

`case_sheet_types` (department's list of clinical record types — Operative,
Periodontal, Orthodontics, etc., each with a `page_url`) is also modeled
(`CaseSheetType`) since `tasks.case_sheet_type_id` requires it. Real values
were pulled from the live `clinic_system2` database (not guessed):
`operative`, `partial_denture`, `complete_denture`, `surgery`, `periodontal`,
`prosthodontics`, `orthodontics`, `pediatric`, `prevention`, `oral_medicine`,
`other`.

## Appointments — a real schema/code contradiction, resolved deliberately

`appointments.doctor_id` looked ambiguous: the source dump's own FK
constraint says `REFERENCES users (id)`, but the original app's
`tv_patients.php` display query does `LEFT JOIN doctors d ON a.doctor_id =
d.id`. These can't both be right. Traced to the actual write path
(`admin/ajax/pin_appointments.php`): it populates `doctor_id` from
`SELECT id FROM users WHERE role = 'doctor'` — i.e. the FK constraint is
correct, and `tv_patients.php`'s join is a **pre-existing display bug** in
the original app (it happens to not error because `doctors` and `users` are
both auto-increment int tables with overlapping IDs, so the join silently
returns *some* row, just usually the wrong one).

This rebuild's `Appointment::doctor()` relation points at `User`, matching
the verified write path, and the API's `TvBoardController` joins pinned
appointments against `users` too — deliberately **not** reproducing the
original bug. See `App\Models\Appointment` and
`App\Http\Controllers\Api\TvBoardController` docblocks for the same note
in code.

One consequence: `users` (staff/admin table) has no `education_type_id` or
`stage_id` column, so the original app's per-education-type filter on
pinned appointments couldn't have been filtering by the right thing either
— that filter is not carried over here (see the controller for detail).

## TV waiting-room board — API only, and a dead table

Public (no auth), read-only: `GET /api/v1/tv-board`
(`?education_type=<id>&stage=<id>`), mirrors `tv_patients.php`: doctors'
scheduled patients (`patients` → `groups` → `group_slots`) plus pinned
same-day `appointments`.

`tv_queue` — a table that looks purpose-built for exactly this ("waiting /
called / finished" status per patient/doctor) — is in the imported schema
but **grepping the entire original codebase found zero references to it**
in any `.php` file, only in SQL backup dumps. It's dead. No model/routes
were built for it here, to avoid presenting an unused table as a real
feature. The actual live-queue-equivalent is the `tv-board` endpoint above.

Update (2026-08-18): the public `TvBoard.vue` page **is** now built —
`routes/web.php`'s `/tv` route renders it, client-side-polling the
`tv-board` API every 20s with education-type/stage filters. The paragraph
above is kept as a record of the original gap; it's closed now.

## Activity logging

`user_activity_log` (imported schema) is written to via `App\Services\
ActivityLogger::log()`, modeled after the original app's own
`ActivityLogger` class/`ACTIVITY_LOGGING_GUIDE.md` for continuity — same
idea (who did what, when, from where), different mechanism: instead of an
explicit `ActivityLogger::logCreate(...)` call added to every controller
action (the original's approach), this rebuild uses a model trait
(`App\Traits\LogsActivity`) hooked into Eloquent's `created`/`updated`/
`deleted` events, so logging happens automatically for any model that uses
the trait — no risk of a controller forgetting to call it.

Applied to: `Doctor`, `Patient`, `Task`, `TaskInstance`, `DentalChart`,
`Appointment`, `Payment` — the models judged to matter for an audit trail.
**Not** applied to lookup tables (`EducationType`, `Stage`, `Department`,
`CaseSheetType`) or the 12 API-only clinical specialty models, to keep the
log's signal-to-noise reasonable; this is a scope choice, not a limitation
of the mechanism — adding the trait to any other model is a one-line change.

The actor (who) is resolved from whichever guard authenticated the request
— web session or Sanctum token, `User` or `Doctor` — via
`ActivityLogger::currentActor()`. `user_activity_log.user_id` is `NOT NULL`
with no FK constraint (verified against `information_schema` — same
"denormalized, no enforced FK" pattern seen elsewhere in this schema), so a
`Doctor`'s id and a `User`'s id can both legally end up in that column;
`username`/`user_role` are stored alongside specifically to disambiguate,
matching the original schema's own design for this.

Verified end-to-end (2026-08-18): created/updated/deleted a `Doctor` via
the API — create and delete both produced a log row with the correct
actor, action, and description; a request that failed validation (before
reaching the model) correctly produced **no** log row.

Web: `/activity-logs` (admin/super_admin only), filterable by module,
action, search. API: `GET /api/v1/activity-logs` (`?module=&action=`,
staff-only — 403 for a `Doctor` token), read-only.

## File uploads

`php artisan storage:link` has been run — `public/storage` → `storage/app/public`
is live. Two real (not stubbed) upload flows built on it:

- **Doctor profile photo** — `doctors.profile_image`. Web (`Doctors/Create.vue`
  `Edit.vue`, plain `<input type="file">`) and API (`POST`/`PUT`
  `/api/v1/doctors`, multipart) both accept an `image` upload (max 2MB),
  stored under `storage/doctors/`. `DoctorResource` returns a full
  `profile_image_url`, not just the raw stored path. Updating/deleting a
  doctor deletes the old file from disk.
- **Surgery images** — `POST /api/v1/surgery-images` now takes a real
  `image` file upload (max 5MB, multipart) instead of a pre-existing path
  string, stores it under `storage/surgeries/{surgery_id}/`, and returns
  `image_url`. This changed the endpoint's contract from what the
  batch-generated version originally had (`image_path` as a plain string
  field) — see `App\Http\Controllers\Api\SurgeryImageController` for the
  real handler.

Verified end-to-end (2026-08-18): multipart doctor creation with a photo,
and multipart surgery image upload, both round-tripped — file saved to
disk, publicly reachable at the returned URL (`200`), correct resource
shape back.

Other `*_image`/`*_path`/`profile_image`-shaped fields across the schema
(e.g. `clinics` logo, the 12 clinical specialty records' any similar
fields) don't have upload handling yet — only the two flows above are real.

## Doctor Excel import/export

`phpoffice/phpspreadsheet` (v5) added via Composer, matching the original
app's own dependency. Ported from `admin/import_doctors.php`,
`admin/export_doctors_excel.php`, `admin/generate_doctor_template.php` — but
with one deliberate fix, not a faithful port:

The original's template generator (`generate_doctor_template.php`) promises
5 columns — First Name, Last Name, Email, Phone, Username. But the actual
importer (`import_doctors.php`) only ever reads columns 0–1 (`username`,
`phone`) and fabricates every doctor's name as `"طبيب {username}"`
("Doctor {username}"), silently discarding whatever the user typed into the
first-name/last-name/email columns the template told them to fill in. This
is an incomplete implementation, not a competing source of truth (unlike
the `appointments.doctor_id` case above, where two pieces of live code
genuinely disagreed) — so this rebuild's importer
(`App\Http\Controllers\DoctorImportExportController::import()`) reads all 5
columns as the template actually promises, rather than reproducing the
original's bug.

Also fixed without comment needed: the original `export_doctors_excel.php`
queries a `d.study_type` column that doesn't exist on the current `doctors`
table (`name`, `username`, `password`, `phone`, `education_type_id`,
`stage_id`, `created_at`, `profile_image`, `email` — confirmed against the
imported schema) — leftover from an earlier schema version. This rebuild's
export uses the real current columns plus the related stage/education-type
names.

Both web (`/doctors-template`, `/doctors-export`, `/doctors-import` +
`/doctors-import` GET for the form) and API (`GET /api/v1/doctors-template`,
`GET /api/v1/doctors-export`, `POST /api/v1/doctors-import`, the last
returning `{imported, skipped}` JSON instead of a redirect) are wired —
the API controller delegates `template()`/`export()` to the web
controller's methods directly (pure spreadsheet-building logic, no
Inertia/session dependency) rather than duplicating them.

Verified end-to-end (2026-08-18): downloaded the real template, built a
2-row `.xlsx` from it, imported via the API (`{"imported":2,"skipped":0}`),
confirmed both doctors landed with correct name/username/email, then
exported and confirmed the file contained the right rows with resolved
stage/education-type names.

## QR check-in (task instances)

`endroid/qr-code` (v6) added via Composer, matching the original app's
dependency. **Not** a faithful port — the original's QR system across
`includes/qr_generator_modal.php`, `doctor/doctor_pending_tasks_qr.php`,
and `process_qr_result.php` turned out to define **three incompatible
payload shapes** for what's conceptually the same idea ("scan a code to
open a specific assigned case"):

1. `qr_generator_modal.php`: `{"t":"ti","i":<task_instance_id>,"s":"P|A|C"}`
2. `doctor_pending_tasks_qr.php`: `{"t":"task","task_id":<id>,"s":"P"}`
3. `process_qr_result.php` (the only endpoint that actually *processes* a
   scanned code) only handles a third shape entirely,
   `{"type":"doctor","id":...}`, and does so by inserting into a
   `qr_scan_logs` table that **does not exist** anywhere in the imported
   schema (confirmed: absent from `database/schema_import.sql`, and no
   migration script in the original codebase creates it either) — so that
   branch would throw a SQL error even in the original app today. Every
   other scanned shape falls through to a no-op "here's your text back"
   response — nothing actually opens.

Given that, rather than reproduce three broken/incompatible flows, this
rebuild defines one clean, versioned payload —
`{"type":"task_instance","id":<task_instance_id>}` — with one real,
working generate → scan → open loop, reusing the `task_instances` module
already built (see "The task system" above):

| Method | Path | Notes |
|---|---|---|
| GET | `/api/v1/task-instances/{id}/qr` | PNG QR image (`?size=`) encoding the payload above; 403 if a doctor requests another doctor's instance |
| GET | `/task-instances/{id}/qr` | same, web session auth, for admin printing/display |
| POST | `/api/v1/task-instances/scan` | body `{"payload": "<raw decoded QR text>"}` → resolves and returns the referenced `TaskInstanceResource`; 422 if the payload isn't a recognized task-instance code; 403 if a doctor scans a code for someone else's case |
| GET | `/api/v1/task-instances/{id}` | (added alongside this) plain show endpoint, previously missing |

Verified end-to-end (2026-08-18): generated a QR (valid PNG, decoded
payload matches), scanned it as the assigned doctor (returned full task +
doctor details), scanned as a different doctor (403), scanned garbage
(422) — and the web `/task-instances/{id}/qr` route independently
confirmed to produce a valid PNG via session auth.

Not built: an actual camera-scanning UI (Flutter would use a QR-scanning
plugin and just POST the decoded text to `/scan` — no web camera scanner
page here, matching that this app's QR consumer is the mobile client, not
the admin web UI).

## Dental Chart module

Built against `dental_charts` (the actively-used table — confirmed via
`doctor/save_dental_chart.php` in the original app) plus its child tables
`dental_follow_ups`, `tooth_conditions`, `tooth_treatments` (models +
relations exist; no dedicated CRUD pages/API yet, only reachable through
`DentalChart` relations).

Key finding from reading the original save handler: `dental_charts.patient_id`
is a `varchar(255)` storing the **patient's name**, not a foreign key — the
chart is a denormalized snapshot (name/phone/age/sex/address/occupation
copied in at chart time), not linked to the `patients` table by ID. The
rebuild's `patient_id` form field is a free-text name for the same reason —
this is not a bug, it matches the original schema/behavior.

`tooth_data` is a JSON array of `{tooth_number, tooth_position, condition_type,
severity, notes}` objects — same shape the original PHP frontend posted as
`selected_teeth`. The `ToothSelector.vue` component renders all 32 permanent
(FDI 11–48) or 20 primary (FDI 51–85) teeth by quadrant, click-to-assign a
condition, and emits that exact array shape.

**"Pediatric Dentistry" is not a separate table** — `case_sheet_types` lists
it as its own category (`type_code = 'pediatric'`), which looked like it
might need its own model, same as the 12 specialty tables. Checked instead
of assuming: `doctor/pediatric.php` in the original app has no
`save_pediatric.php` counterpart — its form actually submits to
`save_dental_chart.php`, the same endpoint `dental_charts` already uses,
with `chart_type = 'primary'`. So pediatric charting is already fully
covered by this module (`ToothSelector`'s primary/FDI-51–85 mode is
specifically for this) — nothing further to build here.

## Clinical specialty records

Twelve more clinical tables were ported: `complete_denture_records`,
`oral_medicine_charts`, `orthodontics_records`, `periodontal_charts`,
`prevention_records`, `prosthodontics_records`, `surgeries` (+ children
`surgery_follow_ups`, `surgery_images`, `surgery_medications`),
`treatment_plans`, `treatment_materials`. Each got a real Eloquent model
(exact `$fillable` + casts pulled from `information_schema`, not
hand-transcribed), a full API CRUD controller + Resource under
`app/Http/Controllers/Api/` and `app/Http/Resources/`, **and** a web CRUD
controller + Inertia pages.

### Faithful case-sheet ports (2026-08-19, in progress)

Requested: make the case sheets exact replicas of the original's forms —
fields, dental charts, and the rest of the detail. The generic form
described below was a deliberate time trade-off, and the Clinical Records
hub page said so out loud ("grouped generically rather than hand-tailored
per specialty") — which is exactly what prompted this. Being replaced
specialty by specialty; the hub page now badges which ones are done
("Full case sheet") so the state is visible rather than assumed.

**Periodontal chart — done.** Port of `doctor/periodontal_chart.php`
(5,174 lines in the original). `App\Support\PeriodontalChartForm` holds the
real layout — **11 sections** (Patient Information, Student/Case, Women
Only, Chief Complaint & MH, History, Examination, BPE, Radiographs &
Investigations, Clinical Examination, Diagnosis, Treatment Plan &
Approval) with the original's own labels, help text and option sets
(Stage I–IV, Grade A–C, localized/generalized/molar-incisor, yes/no/don't-know
triples), replacing the auto-generated `Field Name → 'Field Name'` labels.
Conditional display is ported too: the *Women Only* section appears only
when gender = female, and *Number of weeks* only when pregnancy = yes,
matching the original's `#womenOnlySection` / `#pregnancy_weeks_row`
toggles.

**The per-tooth charts** (`resources/js/Components/PerioChart.vue`) are the
part that was entirely missing before — the whole `chart_data` column was
just a textarea. Now a real grid: 32 teeth in the original's FDI quadrant
order (upper 18→11, 21→28; lower 48→41, 31→38), **six measurement sites per
tooth** (3 buccal + 3 palatal/lingual), rendered as three chart groups
exactly as the original serialises them — initial (BOP/PPD/CAL),
post-hygiene-phase (PPD/CAL only; the original has no BOP table there), and
follow-up (BOP/PPD/CAL). BOP sites are click-to-toggle marks, PPD/CAL are
millimetre inputs, and a live site-coverage counter sits above each table.
The JSON written to `chart_data` matches the original's `collectChartData()`
output key-for-key — including its always-empty `teeth` legacy placeholder —
so a chart saved in either app parses in the other.

**A real behavioural detail ported, not guessed**: the original's form
input is *named* `patient_id` but actually holds the patient **name**
(`placeholder="Patient Name"`, populated from `$patient_name`);
`save_periodontal_chart.php` then finds-or-creates a row in `patients`
matched on name (+ phone when given) and stores that FK in the int
`periodontal_charts.patient_id`. The port does the same, so charts stay
joinable to a real patient rather than carrying an orphan id — the previous
generic form had validated `patient_id` as a plain required integer, which
would have meant typing a raw database id by hand.

Verified end-to-end in a rolled-back transaction: the create page renders
all 11 sections with the right field counts; a save with a real chart
payload persisted `women_pregnancy`/`pregnancy_weeks`/BPE/diagnosis/boolean
history fields correctly, created the linked patient row with its phone,
and stored `chart_data` with tooth 11's PPD buccal `["3","2","3"]` and BOP
lingual `["","","+"]` intact; the edit page round-tripped the same chart
back; and re-saving the same patient reused the existing row rather than
duplicating it (`patients` count stayed 1).

**Complete denture — done.** Port of `doctor/complete_denture.php`. Eight
sections with the original's own numbered labels and bilingual patient-info
captions ("اسم المريض (Patient's Name)", "1- Reason for tooth extraction.",
"b) Regarding the old denture how is?" with its six sub-fields …), plus its
**"Stages and evaluation" table** — nine stages (Preliminary impression →
Cast/Surveying → Final impression → Registration of jaw relation → Trial
denture → Ready for flasking → C.D in mouth → 1st adjustment → Final
evaluation), each a signature / date / grade row bound to the original's
own `stage_{key}_{signature,date,grade}` column naming.

**Shared machinery** (so the remaining sheets are layout-only work):
`resources/js/Pages/Specialty/SectionedForm.vue` renders any sheet from a
`sections` array, optionally plus `stages` (the evaluation table) and
`chartGroups`/`chartField` (per-tooth charts) — each specialty supplies its
layout from an `App\Support\*Form` class and nothing else.
`Components/QuadrantTeeth.vue` ports the original's `fdi-cross` quadrant
picker (UR8/UL1-style codes, comma-separated, in the original's own
`$quadrantOrderConfig` ordering) for its tooth-selection fields.

**A real bug caught by testing the edit round-trip**: Eloquent `date`-cast
columns serialise to Inertia as full ISO datetimes
(`"2026-08-01T00:00:00.000000Z"`), which `<input type="date">` silently
refuses to bind — every date field would have rendered **blank when editing
an existing record**, and then wiped the stored date on save. Found by
checking what `stage_preliminary_date` actually came back as rather than
just that the save succeeded. Fixed by normalising to `YYYY-MM-DD` when
seeding the form; verified against ISO, plain-date, null and empty inputs.
This affected every ported sheet's date fields, periodontal included.

**Prosthodontics (removable partial denture) — done.** Port of
`doctor/prosthodontics.php`. Seven sections with the original's lettered
labels ("C- Condition of soft tissue", "D- Presence of any abnormal
lesion", "E- Mobility of abutments" …), quadrant pickers for missing and
caries teeth, and the same nine-row evaluation table as complete denture
except its seventh stage is "R.P.D in mouth" (`stage_rpd_*`) rather than
"C.D in mouth". **Data-compatibility detail ported**: the original writes
the selected teeth to their own columns *and* mirrors them inside the
`tooth_chart_data` JSON (`{selectedTeeth, dmftData, missingTeeth,
cariesTeeth}`), and its loader falls back to that blob when a column is
empty — so this port writes both, keeping records readable by the original.

**Oral medicine — done, rebuilt 2026-08-20 (see follow-up below).** Port of
`doctor/oral_medicine.php`, 12 sections. This sheet is structurally
different from the others: its columns are **JSON blobs**, not scalars, but
they split into two different shapes. Three (`jaws_teeth_relations`,
`investigations_diagnosis`, `student_visits`) have flat scalar subkeys and
use `SectionedForm.vue`'s generic `group` field option — posted as
`column[subkey]`, namespaced `group__key` in the form, re-collapsed into
JSON on submit. The other six (`history_of_complaint`,
`past_medical_history`, `surgical_history`, `family_history`,
`social_history`, `extraoral_intraoral_examination`) have **nested/array**
subkeys a flat group can't express (checklists, R/L pairs, checkbox lists)
— each is one field bound to the whole column, with its own dedicated Vue
component and manual `JSON.parse`/`JSON.stringify` (see the follow-up
below for why this split exists and what it replaced).

Verified end-to-end in a rolled-back transaction: prosthodontics saved
quadrant codes (`UR8, LL3` / `UL5`), its `stage_rpd_grade`, and the
mirrored `tooth_chart_data`; oral medicine saved and re-read its grouped
columns plus its quadrant `present_teeth` (superseded by the fuller
round-trip test in the 2026-08-20 follow-up below, which also covers its
six standalone-blob columns).

### Oral medicine — raw JSON leaking into text fields, and a missing task link (2026-08-20, follow-up)

Reported with a phone screenshot: the "Past medical history" box showed raw
text like `{"value":"no","details":""},"hospitalizations":...` instead of a
form, and the surgical-history fields showed literal `yes`/`no` strings.
Root cause: the first port of this sheet (above) guessed several JSON
columns' shapes from their field names instead of reading the original, and
routed them through the generic `group` (flat scalar subkeys) mechanism.
Checked against the real source (`dental_clinics2/doctor/oral_medicine.php`,
3,558 lines) and real imported `oral_medicine_charts` rows via tinker — not
assumed from either alone — turned up several real divergences:

- **`past_medical_history`** is not a textarea. It's a 14-category
  checklist (cardiovascular, blood, bone/spinal, joint, ENT/respiratory,
  GIT, neurologic, psychiatric, dermatologic, genitourinary, endocrine,
  allergy, hospitalizations, medications), each item storing
  `{value: "yes"|"no", details: string}` — this is what was leaking as raw
  JSON. New generic `Components/ValueDetailsChecklist.vue` renders it.
- **`surgical_history.extra_oral`/`intra_oral`** are plain `"yes"`/`"no"`
  radios (no details wrapper, unlike PMH) — were rendering as literal text.
- **`family_history`** is 8 independently-named plain text fields
  (`obesity`, `sleep_apnea`, `snoring`, `depression`, `cancer`,
  `cardiovascular`, `diabetes_hormonal`, `other_hereditary`) — also no
  value/details wrapper, confirmed against real row data.
- **`social_history`** was missing two checkbox-array fields entirely
  (`tobacco_other[]`: pipe/cigar/snuff/chew; `caffeine[]`: none/coffee/tea/
  soda) and had invented radio option values instead of the original's real
  `never`/`current`/`quit` and `single`/`married`/`divorced`.
- **`history_of_complaint`** was missing its entire 28-item symptom
  checklist (`symptoms[]` + per-symptom `symptom_details{}`, most with
  right/left sub-fields, `other` with free text) — only the 7 open-ended
  follow-up questions and pain scale existed.
- **`extraoral_intraoral_examination`** had the wrong field set altogether
  (no 7-muscle tenderness grid, no TMJ-clicking/preauricular-pain/swelling/
  deviation right/left pairs). `head_diagrams` (freehand canvas pain-diagram
  strokes) has no non-canvas equivalent, so it's deliberately not an
  editable field — the new component preserves it untouched via object
  spread rather than overwriting it with an empty value on save.
- **`jaws_teeth_relations.classification`** option values were wrong
  (`class_i`/`class_ii`/`class_iii`); the real stored value is `class1`/
  `class2`/`class3` (no underscore, no roman numerals).
- **`clinical_examination`** (previously wrongly mapped to a `pain_pattern`
  textarea) was removed outright — real data confirms `pain_pattern` is
  `[{x,y,type}, ...]` canvas stroke data with no non-canvas equivalent in
  the original, same as `head_diagrams`.

Fixed by rewriting `App\Support\OralMedicineForm.php` field-for-field
against the original, and building six new dedicated Vue components
(`ValueDetailsChecklist`, `SymptomsChecklist`, `HistoryOfComplaintSection`,
`SurgicalHistorySection`, `FamilyHistorySection`, `SocialHistorySection`,
`ExtraoralIntraoralExam`), each bound to its whole JSON column rather than
forced through `group`'s flat-subkey model. `SectionedForm.vue` gained a
`JSON_BLOB_FIELD_TYPES` list so these columns get manual
`JSON.parse` on load / `JSON.stringify` on submit — confirmed via
`OralMedicineChart::casts()` that, unlike the operative sheet's
`tooth_data`/`endodontics_data`, none of this sheet's JSON columns carry an
Eloquent `array` cast, so manual (de)serialisation is correct here (using
the array-cast pattern instead would have silently double-encoded them, the
same bug class fixed earlier in the odontogram work).

**A second, unrelated bug found while reading these controllers**: every
specialty controller except `DentalChartController` — `OralMedicineChartController`,
`PeriodontalChartController`, `ProsthodonticsRecordController`,
`CompleteDentureRecordController`, `OrthodonticsRecordController`,
`PreventionRecordController`, `SurgeryController` — had a `create()` that
never forwarded `task_instances_id` from the query string, so a blank sheet
opened fresh from a task lost its link back to it, silently disabling that
sheet's Print/QR buttons (both require `record.task_instances_id`). Fixed
in all 7: `create(Request $request)` now passes
`taskInstanceId: $request->integer('task_instances_id') ?: null` into
`form()`, which forwards it into the Inertia payload as
`'taskInstanceId' => $record?->task_instances_id ?? $taskInstanceId`,
mirroring the pattern `DentalChartController` already had.

Verified via `php -l` on all 8 changed PHP files, `npm run build` (clean,
853 modules), and a tinker round-trip against the real
`OralMedicineChartController` model: created a record with all six new
JSON-blob columns populated (including a `head_diagrams` array on
`extraoral_intraoral_examination`), confirmed every column came back as
valid single-encoded JSON (no double-encoding), confirmed `head_diagrams`
survived untouched, then deleted the test row and confirmed zero rows
remained.

### Oral medicine — head pain-location diagrams built (2026-08-20, second follow-up)

Reported: the original's Oral Medicine chart has markable head diagrams
that hadn't been carried over — correct, `head_diagrams` had been left as
untouched-but-inert (see above) on the assumption it was genuinely freehand
canvas drawing with no real-world asset behind it. Reading
`drawPainPatternForHeadDiagram()` and its call sites in
`oral_medicine.php` in full showed that assumption was wrong on both
counts:

- It's **not freehand drawing**. The original only ever adds one point per
  `mousedown`/`touchstart` (`diagram.drawings.push({x, y, type})`) — there's
  no `mousemove` handler, so `mouseup`/`touchend` just reset a flag nothing
  else reads. It's click-to-place, the same interaction class as the
  odontogram, not a stroke-capture pad.
- It's **not blank canvas either** — each of the four views (Frontal,
  Posterior, Right, Left) draws onto a real reference image, looked up from
  `dental_clinics2/uploads/{front,back,right,left}.jpg`. Those files exist
  on disk and are genuine head/face line diagrams (a front view, a back
  view, and left/right profiles, each labelled). Copied into this app as
  `public/images/head-diagrams/{frontal,posterior,right,left}.jpg` — static
  reference assets, not per-record uploads, exactly as the original serves
  them from its shared `uploads/` folder rather than per-patient storage.

Built as `Components/HeadDiagramsBoard.vue`: four canvases, each with the
matching reference image as its background, a pain-quality dropdown (the
original's exact 10 options — Mild/Moderate/Severe plus seven single-letter
qualities: Burning, Dull, Numbing, Pressure, Sharp, Tingling, Radiating),
and a Clear button per view. Clicking a diagram stamps the selected
symbol at that point. Symbols are ported pixel-for-pixel from
`drawPainPatternForHeadDiagram()` — vertical hatching `|||||` for mild,
wavy `MMM` for moderate, diagonal hatching `/////` for severe, a plain
letter for the other seven — not approximated, the same canvas drawing
calls translated 1:1 from the original's JS. Points are stored in the
image's *natural* pixel space (`{x, y, type}`, matching the original's
`baseWidth`/`baseHeight` conversion) rather than screen pixels, so a chart
saved on one screen size still lines up when reopened at another, and a
record written by either app parses correctly in the other.

Wired into `Components/ExtraoralIntraoralExam.vue` (the field that already
owned this JSON column) as a new "Head pain-location diagrams" block; no
change needed to `OralMedicineForm.php`'s field type, since the whole
`extraoral_intraoral_examination` blob was already one field bound to that
component.

**A second, unrelated bug found while tracing where this data actually goes
at print time**: `App\Support\CaseSheetPrintRenderer`'s generic cell packer
had no exclusion for Oral Medicine's six JSON_BLOB_FIELD_TYPES columns
(`history_of_complaint`, `past_medical_history`, `surgical_history`,
`family_history`, `social_history`, `extraoral_intraoral_examination`) —
since none of them carry an Eloquent cast, `$sheet->{$key}` returns the raw
*undecoded JSON string*, and the generic formatter has no case for these
field types, so it fell through to printing that raw string verbatim. The
exact "raw JSON leaking into a field" bug already fixed on the edit form
was still live on the **printed** sheet. Fixed by excluding all six from
the generic packer (same treatment `file`/`dental_chart`/
`teeth_squares_grid`/`quadrant_repeater` already get) until each gets a
real structured print block — not printed yet rather than printed wrong.

Verified via `php -l` on both changed PHP files, `npm run build` (clean),
and a tinker round-trip creating a real `OralMedicineChart` row with
`head_diagrams` populated on all four views (including one empty view):
confirmed the stored JSON was valid and single-encoded, confirmed the
point arrays and their `{x, y, type}` shape survived exactly, confirmed
the sibling `muscles` data in the same column was untouched, then deleted
the test row and confirmed zero rows remained.

**Prevention — done.** Port of `doctor/prevention.php`, 9 sections. The
most structurally unusual sheet: `prevention_records` has **no per-field
columns at all** — save_prevention.php packs everything into `patient_data`
and `examination_data`. Handled by putting every field in a group and
having the controller re-nest `questions` / `dmfs_indices` /
`dietary_recall` *inside* `examination_data` on save (and flatten them back
out when loading the edit form), reproducing the original's payload shape.
Includes its ten dental-behaviour questions in the original's order and
wording, with the detail that **only question 2 offers "I don't know"** —
the rest are yes/no. `hygiene_table`/`dentition_table` are written as empty
objects rather than dropped, so the blob keeps the shape the original reads
(their grid widgets aren't ported).

**Orthodontics — done, rebuilt 2026-08-20 (see follow-up below).** Port of
`doctor/orthodontics.php`, 9 sections. Split sheet: the patient/referral
half has real columns, the clinical half is one `examination_data` JSON
blob keyed exactly as save_orthodontics.php writes it (skeletal/dental
relations, Angle's & canine & incisor classifications, over-jet/over-bite/
cross-bite, quadrant tooth pickers, habits, diagnosis and treatment plan).
Its `treatment_stages`, `appliance_designs` and `teeth_squares`
sub-structures are real editable widgets, not preserved-but-inert
placeholders — see the follow-up below for why that changed and what each
one actually is.

### Orthodontics — real markings/diagrams widgets built, and mistyped fields fixed (2026-08-20, follow-up)

Requested: compare against the original's orthodontics chart and make this
an exact match — "images, drawing, and markings" (الصور والرسم والتأشيرات).
Checked directly against `dental_clinics2/doctor/orthodontics.php` (3,100
lines) and, for the canonical shape of `examination_data`, its
`save_orthodontics.php` (the actual `$examination_data` array assembled
server-side — the ground truth over the page's own JS, which turned out to
carry two dead collectors: `position[]`/`others[]` are gathered by
`querySelectorAll` but no matching input exists anywhere in the form, so
they always save as `[]` in the original too; not built here for the same
reason).

**Three real widgets were completely missing before** — this is what
"markings/images" turned out to mean concretely:

- **`teeth_squares`** — the "Number of Teeth" table: 4 rows (Unerupted /
  Erupted / Erupted / Unerupted) × 16 columns (header `8→1, 1→8`), each cell
  clickable and opening a picker for primary teeth (A–E), permanent teeth
  (1–8), or a "/" extracted mark. New `Components/TeethSquaresGrid.vue`,
  storing `{square_id: mark}` exactly as `teeth_squares[<square_id>]` posts
  it (`square_id` = `${row_type}_${col}`), with its own picker modal
  (built on the shared `Modal.vue`) matching the original's `Select Tooth
  Number` dialog option-for-option, including Clear.
- **`treatment_stages`** ("Stages of treatment") and **`appliance_designs`**
  ("Appliance type & Design") — both repeating `{index: {info, quadrants}}`
  rows: a free-text info line plus the original's `fdi-cross` quadrant tooth
  picker per row, add/remove buttons, 1-based indices. New
  `Components/QuadrantRepeater.vue` (one component, both fields — same
  shape, different label) reuses the existing `QuadrantTeeth.vue` picker
  per row rather than building a second one.

Both new shapes needed `SectionedForm.vue` to support a `group` subkey whose
value is itself an object rather than a scalar — turned out to already work
with zero changes to the group-reassembly code in `submit()` (it just
assigns whatever's in `form[groupKey__subkey]` into the rebuilt column,
regardless of type); only the init-loop needed a `teeth_squares_grid`/
`quadrant_repeater` branch to default a missing subkey to `{}` instead of
the generic `''`.

**A fourth gap, more mundane but load-bearing for accuracy**: nearly every
clinical field in the first pass was typed as plain `text` regardless of
what the original actually renders. Checked field-by-field against the real
`<input>`/`<label>` markup and fixed:

- Ten checkbox groups (`chief_complaint`, `examined_methods`,
  `ap_relation_radio`, `ap_relation_clinical`, `deviation_side`,
  `cross_bite`, `form`, `habits`, `supernumerary`) had no UI at all —
  free text standing in for a fixed option set. `SectionedForm.vue` gained
  a new generic `checkboxes` field type (multi-select, `field.options`,
  array value) for these.
- Nine more (`vertical_relation`, `horizontal_relation`, `facial_profile`,
  `tongue_size`, `lips_posture`, `lip_line`, `teeth_arch_proportion`,
  `angles_classification`, `canine_classification`,
  `incisors_classification`, `oral_hygiene`) are single-choice radios with
  real option sets, not free text.
- `angles_classification`/`canine_classification`/`incisors_classification`
  additionally had the **wrong option values** — `class_i`/`class_ii_div_1`/
  `class_ii_div_2`/`class_iii` (invented) instead of the real
  `class1`/`class2`/`class3` (confirmed against both the markup and
  `ap_relation_radio`/`ap_relation_clinical`, which use the same three
  values for the same classification concept elsewhere on the same page).
- `badly_carious`, `supplementary_teeth`, `overlapped_teeth` and
  `inclined_teeth` are quadrant tooth pickers (`renderQuadrantSelectorField`
  in the original), not free text — they now use the same `teeth` type as
  `congenital_missing`/`extracted_teeth`/`impacted_teeth` already did.

`App\Support\CaseSheetPrintRenderer` gained a `checkboxes` case (prints
each selected value's label, comma-joined, same as `select`/`radio` already
did for a single value) and excludes `teeth_squares_grid`/
`quadrant_repeater` from the generic label:value cell packer — both hold
structured per-cell/per-row data a single printed cell can't represent;
not printed yet, the same gap `dental_chart` has its own dedicated print
block for and these two don't yet.

**Explicitly not built, matching precedent set elsewhere in this port**:
the per-row canvas signature pad on the separate `treatment_plans`
satellite table ("Treatment Plan & Senior Approval") is still a plain text
field — same simplification as every other sheet's drawn signatures (see
`App\Support\SurgerySatelliteForms`). The original's department-role gate
on `diagnosis`/`treatment_plan`/`treatment_stages`/`appliance_designs`
(editable only by admins or a doctor with a role in the owning department,
independent of who owns the case sheet) isn't replicated either — this
port's `readonly` stays the single all-or-nothing `CaseSheetAccess` gate
every sheet already uses.

Verified via `php -l` on all three changed PHP files, `npm run build`
(clean), and a round-trip through the real `OrthodonticsRecordController`
(constructing an actual `Illuminate\Http\Request` and calling `store()`
directly, not just testing the model layer): posted a payload covering
every field type — multiple checkbox groups, all the reclassified radios,
a populated `teeth_squares` grid, and both `treatment_stages` and
`appliance_designs` with two rows each — confirmed the stored
`examination_data` was valid single-encoded JSON (no double-encoding) with
every value shape intact (arrays stayed arrays, the two repeaters kept
their `{index: {info, quadrants}}` shape, `badly_carious` kept its quadrant
string), then deleted the test row and confirmed zero rows remained.

**Surgery — done.** Port of `doctor/surgery.php`, 9 sections including the
original's 17-row `mh_*` yes/no medical-history checklist, chief-complaint
pain/swelling flags, HPI, examination/diagnosis, procedure (quadrant tooth
picker, anaesthesia, duration, complications), post-op and approval. Uses
the same find-or-create patient resolution as the periodontal sheet, since
`surgeries.patient_id` is likewise an int FK behind a name-only field.

**A second date/time round-trip bug, same class as the first**: MySQL
returns `TIME` columns as `HH:MM:SS`, and `<input type="time">` round-trips
that unchanged — so an edit that never touched `start_time` re-submitted
`10:30:00`, which `date_format:H:i` **rejected**. A save that worked on
create would fail on edit. Caught by actually re-submitting what the edit
form hands back rather than only testing a fresh create. Fixed on both
sides: validation accepts `H:i,H:i:s`, and the form trims to `HH:MM` for
display. Verified both formats now save.

**Satellite sheets — done (all 12 now tailored).** Surgery follow-ups /
images / medications and treatment plans / materials are not standalone
case sheets in the original — they're repeating rows attached to a parent
record. Built accordingly (`App\Support\SurgerySatelliteForms` +
`Concerns\RendersSatelliteForm`): each leads with a **parent picker**
populated from the real parent table (surgeries labelled
`#id — patient · date`, dental charts, tooth treatments) instead of a raw
integer input, hides the doctor selector (`hideDoctor`) since the doctor
comes from the parent, and renders the tables' real enums as selects —
`image_type` (pre/intra/post-operative) and `material_type`
(filling/crown/bridge/implant/cement/other) — rather than free text.
`surgery_images.image_path` is a genuine file upload on the established
`Storage::disk('public')` convention, with a preview of the stored image
when editing, old-file cleanup on replace/delete, and multipart `_method`
spoofing on update (Laravel can't parse multipart PUT). Crucially, an edit
that doesn't pick a new file **keeps** the stored path rather than nulling
it.

`SectionedForm.vue` gained `lookup`, `file` and `decimal` field types plus
`hideDoctor` to support these, so the renderer now covers every shape the
12 sheets need.

Verified end-to-end in a rolled-back transaction: all five render with the
right field counts and populated lookups; a follow-up and a treatment
material and a treatment plan each saved against real parents with their
decimals (`qty=1.50`, `cost=25.00`) and enums intact; and creating a
surgery image without a file is correctly rejected by validation.

### Web forms — one generic form, not 12 bespoke ones

These are large, real clinical case-sheet forms in the original app —
`periodontal_charts` alone has **163** fields (full medical history
checklist, BPE scores per sextant, risk factors, signatures...),
`prosthodontics_records` has 59 (multi-stage signature/date/grade tracking
per lab step), `complete_denture_records` 76. Hand-building 12 bespoke
multi-section Vue forms at that field count wasn't a good use of time, so
instead: `resources/js/Pages/Specialty/{Index,Form}.vue` are **generic**
pages shared by all 12, driven by a `fields: [{key, label, type,
required}]` array each web controller passes in (type inferred from the
real column type: `date`/`datetime`/`timestamp` → date input, `tinyint` →
yes/no select, `text`/`longtext` → textarea, `int` → number, else text;
`required` from `information_schema.IS_NULLABLE`, same approach used
earlier for the API validation rules). A `doctor_id` field, where present,
renders as a doctor `<select>` instead of a raw number input — the one
field type worth special-casing given how central it is. Every other
`*_id` field (e.g. `task_instances_id`, `tooth_treatment_id`) is a plain
number input; no other foreign keys got dropdown treatment.

Reached from **Clinical Records** in the nav → a hub page
(`ClinicalRecords/Index.vue`) linking to each of the 12 `{resource}.index`
pages, each a plain list (`Specialty/Index.vue`) with Add/Edit/Delete going
through `Specialty/Form.vue`.

Both the 12 web controllers and their route registrations were generated
from the same `information_schema` column dump as the API layer (a
one-off local generator script, not committed — the pattern is
straightforward to redo by hand for a 13th table if needed). Two real bugs
surfaced and were fixed before this shipped:

1. **A PHP heredoc string-interpolation bug in the generator itself** —
   `"$var->method()"` inside a heredoc is parsed by PHP as *property*
   interpolation (`$var->method`, no call), not "interpolate `$var`, then
   emit `->method()` as literal text". The generated `update()`/`destroy()`
   methods came out as `$($this->validateRecord($request));` and `$();` —
   silently missing the `record->update`/`record->delete` calls entirely
   (valid PHP, just a no-op). Caught by reading the generated output before
   registering routes, not by testing — worth calling out because this
   class of bug produces no interpolation warning until you look at what
   actually got written to the string.
2. **A much bigger one, app-wide, not specific to these 12 tables** — see
   the next section.

A third bug, in the generic **`Specialty/Form.vue`** itself (not the
generator), surfaced later via a dedicated QA pass on boolean fields —
`periodontal_charts` alone has 20+ `tinyint` columns, and nothing up to
that point had specifically exercised editing an *existing* record with
one already set. `PeriodontalChart`'s `boolean` cast means
`record.some_flag` arrives in the page props as a real JS `true`/`false`,
but the boolean `<select>` in `DynamicField.vue` compares against string
option values (`"1"`/`"0"`). Initializing the edit form directly from
`record[key]` left the field as a literal JS boolean, which never matches
either `<option>` string — the dropdown silently fell back to the blank
"—" option on every edit, discarding the field's actual saved state.
Fixed in `Form.vue`'s initial-value setup: boolean-typed fields are
normalized to `'1'`/`'0'` strings before the form is built. Verified with
a real edit — created a record with `hist_smoker_previous=1`,
`exam_radiograph_bitewing=0`, updated only `exam_radiograph_bitewing` to
`1`, confirmed the DB afterward showed `hist_smoker_previous` unchanged at
`1` and `exam_radiograph_bitewing` correctly flipped to `1`.

**A real bug found and fixed while verifying this**: the tables were
scaffolded in a batch (same shape: model + resource + API controller), and
the batch template assumed every table had a `doctor_id` column to scope
`index()` by the logged-in doctor. Five tables don't (`surgery_follow_ups`,
`surgery_images`, `surgery_medications`, `treatment_plans`,
`treatment_materials` — these are child/detail tables scoped by
`surgery_id`/`chart_id`/`tooth_treatment_id` instead) — their `index()`
would have thrown `SQLSTATE... Unknown column 'doctor_id'` the first time a
doctor called them. Caught by an end-to-end test (create → list), fixed to
filter by the correct parent-id query param instead. Separately, the same
batch pass initially marked every field `nullable` except one; cross-checked
against `information_schema.COLUMNS.IS_NULLABLE` and tightened the fields
that are genuinely `NOT NULL` with no DB default (e.g. `surgeries.patient_id`,
`periodontal_charts.chart_date`/`chart_data`, `surgery_medications.medication_name`)
to `required`. Both fixes were verified by actually calling the endpoints,
not just read-through.

Endpoints (all under `/api/v1`, all require `Authorization: Bearer <token>`,
all standard REST — `GET` index/show, `POST` store, `PUT`/`PATCH` update,
`DELETE` destroy):

| Resource | Path | Scoped by |
|---|---|---|
| Complete denture | `/complete-denture-records` | `doctor_id` (own records only) |
| Oral medicine | `/oral-medicine-charts` | `doctor_id` |
| Orthodontics | `/orthodontics-records` | `doctor_id` |
| Periodontal | `/periodontal-charts` | `doctor_id` |
| Prevention | `/prevention-records` | `doctor_id` |
| Prosthodontics | `/prosthodontics-records` | `doctor_id` |
| Surgeries | `/surgeries` | `doctor_id` |
| Surgery follow-ups | `/surgery-follow-ups` | `?surgery_id=` query param |
| Surgery images | `/surgery-images` | `?surgery_id=` (real multipart file upload — see "File uploads" above) |
| Surgery medications | `/surgery-medications` | `?surgery_id=` |
| Treatment plans | `/treatment-plans` | `?chart_id=` (links to `dental_charts`, confirmed via `doctor/save_treatment_plan.php`) |
| Treatment materials | `/treatment-materials` | `?tooth_treatment_id=` |

"Scoped by `doctor_id`" means: when the authenticated token belongs to a
`Doctor`, `index()` automatically filters to that doctor's own records; a
`User` (staff) token sees everything.

## Case-sheet form schema endpoint, and a real partial-update bug it surfaced (2026-08-20)

Built for the Flutter client's generic case-sheet renderer (see
`flutter_app/README.md` §4/§6) — `GET /api/v1/case-sheet-forms` (the 8
sheets in `CaseSheetPrint::SHEETS`, each `{resource, title}`) and `GET
/api/v1/case-sheet-forms/{resource}` (`App\Http\Controllers\Api\
CaseSheetFormController`), returning a sheet's `App\Support\*Form::
sections()` layout as JSON — the same field/section/type/options
description `SectionedForm.vue` already renders from — plus
`groupColumns`, `chartGroups`/`chartField`, and `stages`. No record: a
record's values come from the resource's own existing REST endpoint
(`GET /oral-medicine-charts/{id}`, etc.); this is layout only, the mobile
equivalent of what `App\Support\*Form` classes already are for the web
controllers.

**A real bug fixed while building it**: `CaseSheetPrintRenderer` gained a
`deriveGroupColumns(array $sections): array` — scans a sheet's `sections()`
for every distinct `field['group']` value, rather than calling a
`groupColumns()` static most `*Form` classes never implemented. Both print
controllers (web and API) previously did
`method_exists($formClass, 'groupColumns') ? $formClass::groupColumns() : []`
— but only `OralMedicineForm` actually has that method. `OrthodonticsForm`
(its whole `examination_data` blob, ~40 fields) and `PreventionForm`
(`patient_data`/`questions`/`dmfs_indices`/`dietary_recall`) group fields
just as heavily but have no `groupColumns()`, so every grouped field on an
**Orthodontics or Prevention printout silently rendered blank** — verified
before the fix: a real Orthodontics record's print `sections()` output had
0 populated grouped cells; after, 47 of 52. Fixed in both
`CaseSheetPrintController` (web) and `Api\CaseSheetPrintController`, and
used from the start in the new schema endpoint.

**A second, more serious bug found via live testing the Flutter form's
save flow, not code review** — a real `PUT` to `orthodontics-records/10`
with a well-formed, correctly-typed empty string (`{"patient_sex": ""}`)
failed validation with *"The patient sex field must be a string"*, even
though `patient_sex` is `['nullable', 'string', 'max:255']`. Root cause,
confirmed by reproducing the exact same failure with a bare `curl` request
(so it wasn't a Flutter/Dio artifact): all 11 controllers whose `update()`
supports partial payloads build their validation rules with
```php
foreach ($rules as $field => $fieldRules) {
    $rules[$field][0] = 'sometimes';
}
```
— unconditionally overwriting each rule's first element. For a field whose
rule starts with `'nullable'`, this **silently deletes it**, turning
`['nullable', 'string', 'max:255']` into `['sometimes', 'string',
'max:255']`. Laravel's global `ConvertEmptyStringsToNull` middleware (in
`getGlobalMiddleware()`, not scoped to `web` — confirmed by reading the
framework source, not assumed) converts an empty string in the request
body to `null` *before* validation runs; with `nullable` gone, `null` then
fails the bare `string` rule. Any client sending a correctly-empty optional
field on an edit — exactly what happens whenever a case-sheet form is
re-saved with a field left blank — hit this. A synthetic
`Validator::make([...], [...])` test in isolation didn't reproduce it
(passed fine), which is why only a real HTTP round-trip caught it.

Fixed identically across all 11 controllers (`CompleteDentureRecordController`,
`OralMedicineChartController`, `OrthodonticsRecordController`,
`PeriodontalChartController`, `PreventionRecordController`,
`ProsthodonticsRecordController`, `SurgeryController`,
`SurgeryFollowUpController`, `SurgeryMedicationController`,
`TreatmentMaterialController`, `TreatmentPlanController`): only replace a
rule's first element when it isn't already `nullable`; otherwise prepend
`sometimes` and keep `nullable` too, so both "only validate if the field
was sent" and "null/empty is fine" hold at once. Re-verified with the same
bare `curl` reproduction — now returns 200 and persists `patient_sex:
null` — and via a full live save through the actual Flutter UI (see
`flutter_app/README.md`). This bug predates the Flutter work and affects
every partial `PUT` through these 11 endpoints, including any other client
that sends a blank optional field — not something introduced by this
session's changes, just not exercised by anything until now.

## A route-name collision that broke every web redirect app-wide

Building the 12th resource's web routes surfaced a bug that had been live
since the very first web CRUD module (`doctors`, session 1): `Route::resource()`
in `routes/web.php` and `Route::apiResource()` in `routes/api.php` both
default to the *same* route names for the same resource string — e.g. both
produced a route named `doctors.index`, one at `GET /doctors` (web) and one
at `GET /api/v1/doctors` (API). Laravel's named-route lookup only keeps the
**last-registered** match for a given name — whichever loaded second
silently won every `route('doctors.index')` call app-wide, including every
`redirect()->route(...)` at the end of every web controller's
`store()`/`update()`/`destroy()`.

**What that actually did**: submitting the Doctors "Add Doctor" form
successfully created the doctor (the DB write is real, unaffected), but
the ensuing 302 redirected the browser to `/api/v1/doctors` — a JSON
response — instead of back to the `/doctors` Inertia page. Every resource
controller built this session was affected identically: doctors, patients,
tasks, dental charts, appointments, payments, and all 12 specialty records
— **every single create/update/delete flow across the whole web app**.

**Why this stayed invisible through eleven modules of testing**: every
verification up to this point checked that pages *rendered* (`GET` a page,
assert `200` and the right Inertia component name) and that data *landed
correctly in the database* (query the row after a `POST`) — both of which
are true regardless of this bug, since the write happens before the
broken redirect. Nothing in this session's testing had actually inspected
a redirect's `Location:` header until this module — the first time that
specific check was made, it failed immediately.

**Fix**: wrapped all of `routes/api.php`'s route definitions in
`Route::name('api.')->prefix('v1')->group(...)`, so API route names become
`api.doctors.index` etc. — distinct from the web `doctors.index` — without
touching any of the ~15 individual resource registrations or any of the
API controllers (grepped first to confirm no API controller code
references a route by name; none do, so renaming was risk-free). Verified
by re-checking `Location:` headers for both a previously-broken resource
(`doctors`) and the newly-added one (`periodontal-charts`) — both now
correctly redirect to their web page, and `php artisan route:list --name=`
confirms every other resource (`patients`, `tasks`, `dental-charts`,
`appointments`, `payments`) resolved the same way.

## JSON API (`/api/v1`) — for the Flutter client

Every web module above has a matching token-authenticated JSON endpoint,
plus the 12 clinical specialty records, which now have both. All API
route names are prefixed `api.` (see previous section) — irrelevant to
API consumers (only affects `route()` name lookups server-side, not URLs),
noted here only for completeness. Versioned under `/api/v1` so a shipped
mobile app build doesn't break when the API evolves.

**Auth**
| Method | Path | Notes |
|---|---|---|
| POST | `/api/v1/login` | staff/admin (`users` table); body: `email`, `password`, `device_name` → `{ token, user }` |
| POST | `/api/v1/doctor/login` | doctor (`doctors` table); body: `username`, `password`, `device_name` → `{ token, doctor }` |
| POST | `/api/v1/logout` | *(auth required)* revokes the current token |
| GET | `/api/v1/me` | *(auth required)* current user or doctor |

All routes below require `Authorization: Bearer <token>`.

**Doctors / Patients** — standard REST (`GET` index/show, `POST` store,
`PUT` update, `DELETE` destroy) at `/api/v1/doctors` and `/api/v1/patients`,
same validation as the web controllers, JSON via `DoctorResource` /
`PatientResource`.

**Lookups** (read-only) — `GET /api/v1/education-types`,
`GET /api/v1/stages`, `GET /api/v1/departments`.

**Tasks** — standard REST at `/api/v1/tasks` (`TaskResource`, includes
nested `department`/`case_sheet_type`/`stage`/`instances` when loaded).

**Academic sessions** — standard REST at `/api/v1/academic-sessions`; `show`
also returns a `stats` block (`doctors`, `groups`, `required_tasks`,
`done_tasks`, `remaining_tasks`) for that session. No "selected session"
concept over the API (Sanctum is stateless) — see "Academic sessions" above.

**Groups** — standard REST at `/api/v1/groups` (optional `?stage_id=`,
`?academic_session_id=` filters), plus `GET /api/v1/groups-available-doctors`
(`?stage_id=`, doctors in no group at all), `POST /api/v1/groups/{id}/doctors`
and `DELETE /api/v1/groups/{id}/doctors` (both take `{ "doctor_ids": [...] }`)
for bulk membership changes — adding a doctor removes them from any other
group first, same one-group-at-a-time rule as the web UI.

**Backup** (admin) — `GET /api/v1/backup` (status: `enabled`, `last_backup_at`,
recent `files`), `POST /api/v1/backup` (trigger one now), `PUT
/api/v1/backup/auto` (`{ "enabled": true|false }`). No file-download
endpoint — same line the original's own ajax script draws (metadata only,
actual `.sql` downloads are a plain web link); an admin who wants the raw
dump uses the web UI. See "Database backup" above.

**Case sheet forms** — `GET /api/v1/case-sheet-forms` (the 8 sheets,
`{resource, title}`), `GET /api/v1/case-sheet-forms/{resource}` (that
sheet's `sections()` layout — field/type/options/group — plus
`groupColumns`/`chartGroups`/`chartField`/`stages`; no record, layout
only). See "Case-sheet form schema endpoint" above.

**Task instances** (the doctor-facing task list):
| Method | Path | Notes |
|---|---|---|
| GET | `/api/v1/my-task-instances` | the authenticated **doctor's** own assigned tasks (403 if called by a `User`); optional `?status=pending\|assigned\|completed` |
| POST | `/api/v1/task-instances` | assign a task to a doctor (`task_id`, `doctor_id`) |
| PUT | `/api/v1/task-instances/{id}` | update `status`/`grade`/`notes`; a doctor can only update their own instance (403 otherwise); setting `status=completed` auto-stamps `completion_date` |
| DELETE | `/api/v1/task-instances/{id}` | remove an assignment |

**Appointments / Payments** — standard REST at `/api/v1/appointments` and
`/api/v1/payments`; appointments support `?doctor_id=`, `?patient_id=`,
`?pinned=1` filters, payments support `?appointment_id=`.

**TV board** — `GET /api/v1/tv-board` (`?education_type=&stage=`), the only
**public** (no token required) endpoint in this API. See "TV waiting-room
board" above.

Verified end-to-end (2026-08-18): doctor API login → `my-task-instances` →
mark complete with a grade; appointment create → payment record → public
`tv-board` correctly showing both, all round-tripped against the real DB.

## Database backup (2026-08-20)

Requested: a daily-and-manual backup feature to protect the clinic's data.
Port of `admin/backup.php` + `admin/ajax/backup_db.php` — manual button,
daily-auto toggle, list of recent backups with download — minus the
MikroTik SCP upload step in the original (out of scope, same as the
standalone MikroTik backup feature — see below).

**A real bug in the original found while reading it, not reproduced**:
`backup_db.php`'s `clinic_settings_upsert()` persists `last_backup_at` and
`enable_daily_backup` into a table it creates on demand as
`CREATE TABLE IF NOT EXISTS clinic_settings (id, setting_key, setting_value,
...)` — a key/value shape. The *real* `clinic_settings` table in the actual
`clinic_system2` database (confirmed via `information_schema` on the
imported schema) is a completely different, single-row profile shape
(`clinic_name`, `clinic_currency`, …) with no `setting_key` column at all —
this app already ports it as `App\Models\ClinicSetting`. So in the
original, that `CREATE TABLE IF NOT EXISTS` was always a no-op against the
existing table, and every `INSERT ... (setting_key, setting_value)` after
it threw an "unknown column" error the code silently catches and ignores.
The daily-backup toggle and "last backup" timestamp were therefore **never
actually saved** in the original — the checkbox always reloaded unchecked
and the status line always read "لا يوجد نسخ سابق", regardless of real
backup history. Not reproduced: `enable_daily_backup` and `last_backup_at`
are two real columns added to the actual `clinic_settings` table instead
(migration `2026_08_20_150000_add_backup_settings_to_clinic_settings`),
alongside the other clinic-wide flags it already holds.

**The "daily" part is a real schedule, not a page-load side effect.** The
original's auto-backup only ever ran when an admin happened to load
`admin/dashboard.php` that day (`fetch(...?action=auto)`, skipped if
already done); a clinic where nobody opened the dashboard on a given day
silently got no backup. Replaced with `App\Console\Commands\RunDatabaseBackup`
(`php artisan backup:run`) registered in `routes/console.php` via
`Schedule::command('backup:run')->daily()` — it checks the toggle and the
same "already ran today" de-dup itself, so it's safe to fire more than
once a day.

**Daily backup — server setup.** Laravel's scheduler needs something to
actually call `php artisan schedule:run` every minute — XAMPP doesn't set
this up on its own (no built-in cron on Windows). One-time setup: Windows
Task Scheduler → new task → trigger "daily, repeat every 1 minute for a
duration of 1 day" → action `C:\xampp\php\php.exe artisan schedule:run`
with "start in" set to the project root. Without this step the toggle and
manual button both still work; only the unattended daily run doesn't fire.

**Storage**: backup files are written to the `local` disk
(`storage/app/private/backups/`, Laravel 11+'s default `local` root) —
*not* a public folder the way the original's `admin/downloads/backups/`
is. Downloads go through `BackupController::download`, which resolves only
a bare filename inside that directory (rejects path separators and `..`
before touching the filesystem) and sits behind the same
`role:super_admin,admin` route gate as the rest of the page — one real
authorization check where the original had a guessable public URL.

**Creation**: `App\Services\DatabaseBackupService` tries the bundled XAMPP
`mysqldump.exe` first (same `--single-transaction --routines --events
--triggers` flags as the original), falling back to a PHP-driven
structure+data dump via PDO if `mysqldump` isn't reachable — same
two-tier strategy as `create_backup()` in the original, ported without the
MikroTik SCP step.

Verified via `php -l` on every new PHP file, `npm run build` (clean), and
direct calls against the real `BackupController`/`RunDatabaseBackup`:
`backup:run` correctly skipped while the toggle was off, created a real
~850 KB `mysqldump` file (confirmed real dump header, not the PHP
fallback) once enabled, then correctly skipped a second same-day run;
`BackupController::store()`/`toggleAuto()` round-tripped through the real
model; `download()` was confirmed to reject a `../../.env` traversal
attempt (404) and to correctly stream a real backup file; the Inertia
`index()` payload was checked with a real `X-Inertia` request and returned
the right component, toggle state, timestamp and file list. All test
backup files were deleted and `clinic_settings.enable_daily_backup`/
`last_backup_at` reset to their pre-test state afterward.

## Setup

1. Database `dental_laravel` already created (XAMPP MySQL, `root` / same
   password as the PHP app's `config/db.php`).
2. `composer install && npm install` (already done in this environment).
3. `.env` already configured + `php artisan key:generate` run.
4. `php artisan migrate --seed`
5. `npm run build` (production) or `npm run dev` (Vite dev server).

## Flutter client (2026-08-20, in progress)

`flutter_app/` — the mobile client for the `/api/v1` API above (Android +
iOS), per the standing "every module needs a Flutter-ready API" request.
Phase 1 (auth, theming, "my tasks" + detail + QR), the Phase 2 gating step
(`DynamicSectionForm` — one generic renderer for all 8 case sheets, driven
by the new `/api/v1/case-sheet-forms` schema endpoint), the dental chart
(odontogram) and periodontal chart (BOP/PPD/CAL) screens, "create new case
sheet" for all 8 resources, a staff-only patients/appointments/payments
"records" module, and the full Phase 3 admin list (doctors, tasks,
education types, stages, departments, groups, academic sessions, case
sheet types, permissions, backup, activity log, clinic settings — every
tracked item, done as of 2026-08-21) are done and verified live against
the running API — see `flutter_app/README.md` for the full plan, phased
breakdown, and what's built so far. Real backend bugs were found and fixed
along the way, independent of Flutter itself: `TaskInstanceResource`
dropping its already-eager-loaded department/case-sheet-type; 11 API
controllers' partial-update validation silently deleting `nullable` on
every field, breaking any correctly-empty optional field on a save (see
"Case-sheet form schema endpoint" above); `dental_charts.visit_date` (and,
confirmed since, `payments.paid_at`) defaulting to `current_timestamp()`
at the MySQL schema level, found but deliberately left unfixed pending a
decision (see below); both `Api\SurgeryController` and
`Api\PeriodontalChartController` having no way to resolve a real
`patients` row from a typed patient name, unlike their web counterparts
(see "Case sheet create" below); and `education-types`/`stages`/
`departments` having no write API at all until this pass (`Api\
LookupController` gained `store`/`update`/`destroy` for all three,
gated identically to their web counterparts — see "Phase 3 admin: doctors,
tasks, and the three taxonomy tables" below). Its visual design was
redesigned to match Instagram's UI (colours, flat hairline-bordered
shapes, light/dark mode following the system) — a deliberate pivot away
from mirroring the web dashboard's own selectable theme; see
`flutter_app/README.md` §7. A real, clinically-significant bug was also
found and fixed purely on the Flutter side: both tooth-chart grids (dental
and periodontal) silently mirrored under the app's Arabic (RTL) locale, so
a tap on what looked like tooth 18's first site could be recorded against
a different tooth or site entirely — see `flutter_app/README.md`,
"Periodontal chart create", for the full account (root cause, both
affected widgets, and how it was verified fixed by checking actual stored
array positions, not just visual appearance).

## Phase 3 admin: doctors, tasks, and the three taxonomy tables (2026-08-21)

`education-types`, `stages`, `departments` were API-read-only before this
pass (`Api\LookupController`, originally documented "managed via the web
admin UI, not writable here") — the Flutter admin screens for them needed
real write endpoints, not a guess at reusing something that didn't exist.
Added `storeEducationType`/`updateEducationType`/`destroyEducationType`
(and the `Stage`/`Department` equivalents) to `LookupController`, each a
direct port of the matching method on
`EducationTypeController`/`StageController`/`DepartmentController` (same
validation, same models) — index stays exactly as it was. Routes gate
identically to their web counterparts, read directly from `routes/web.php`
rather than assumed: `role:super_admin,admin` alone for education types
(the web route has no separate `permission:` layer on top of the role
check); that plus `permission:stages,{create,edit,delete}` /
`permission:departments,{create,edit,delete}` for the other two, since the
web versions do carry that extra layer (worth noting: `departments`'
permission gate exists at all only because of an earlier fix in this
codebase — "departments has been in `UserPermissionController::MODULES`
since the permission matrix was built, but no route ever actually checked
it," per `web.php`'s own comment — so mirroring the *current* web gating
here was the right call, not the *original* ungated version).

Verified via `curl` as staff (`super_admin`): create/update/delete
returned `201`/`200`/`204` for all three. Re-verified with a `Doctor`
token: `403` on all three, confirming `role:super_admin,admin` correctly
denies a non-`User` Sanctum principal even though `EnsureUserHasRole`
doesn't `instanceof`-check the way `EnsureUserHasPermission` does — it
just reads `$user->role`, which is `null` on a `Doctor` model and fails
the `in_array(null, [...], true)` check safely rather than throwing.

See `flutter_app/README.md`'s own entry for the Flutter-side build
(doctors CRUD, tasks CRUD, the shared taxonomy list/dialog screens, and
the `core/data/lookup_repository.dart` consolidation) and its live
verification.

## Phase 3 admin: groups (2026-08-21)

No backend changes were needed — `Api\GroupController` (full CRUD plus
`availableDoctors`/`addDoctors`/`removeDoctors`) already existed and was
read in full before building against it, not assumed. One pre-existing
gap confirmed and left as-is (out of scope for this pass): the `groups`
routes in `routes/api.php` carry no `role:`/`permission:` gate at all,
unlike every other admin resource.

See `flutter_app/README.md`'s own entry ("Phase 3 item — done
(2026-08-21), Groups admin") for the Flutter-side build (weekly slot
editor, member add/remove, the `ApiClient.deleteJson()` body-param
extension needed for `DELETE .../doctors` with a request body) and its
live verification.

## Phase 3 admin: academic sessions (2026-08-21)

`Api\AcademicSessionController` already had full CRUD with live stats on
`show()` (doctors/groups/required-done-remaining tasks) — read in full
before building against it. Only `setCurrent` was missing relative to the
web controller; ported directly (same transaction: clear every session's
`is_current`, then set this one `is_current` + `is_active`) with a new
`PUT /academic-sessions/{id}/set-current` route. The web controller's
`select()` — which session a *browser* session is currently "viewing" —
was deliberately not ported: Sanctum is stateless, so it has no
equivalent, matching the API controller's own pre-existing docblock. No
`role:`/`permission:` gate on any `academic-sessions` route, confirmed via
`curl`, matching both the web route and the same pre-existing gap already
noted for `groups`.

See `flutter_app/README.md`'s own entry ("Phase 3 item — done
(2026-08-21), Academic sessions admin") for the Flutter-side build and its
live verification, including a documented non-bug: after changing the
current session via `curl` (to test `set-current` without leaving a
throwaway session pointed at as "current" on the real dev DB), quickly
popping and re-pushing the same routes in-app kept showing pre-change
data — expected Riverpod `autoDispose` behavior (a fast pop-then-push
reuses the cached value instead of forcing a refetch), not a real
staleness bug; a full page reload confirmed the underlying state was
correct throughout.

## Phase 3 admin: case sheet types (2026-08-21)

No backend changes needed — `Api\CaseSheetTypeController` already had
full CRUD (`destroy` correctly blocked with a 422 when any task still
references the type), read in full before building against it.
`icon`/`color`/`page_url` stay unmanaged by the new Flutter admin form,
matching the web form's own scope (`CaseSheetTypes/Index.vue` never
surfaces them either).

See `flutter_app/README.md`'s own entry ("Phase 3 item — done
(2026-08-21), Case sheet types admin") for the Flutter-side build (dialog
form, `type_code` read-only on edit) and its live verification, including
a layout quirk worked around during testing: a list whose last row ends
exactly under the screen's fixed FAB has that row's trailing icons
briefly blocked from taps — same structure every list in this app uses,
just visible here because the row count happened to line up with it.

## Phase 3 admin: permissions (2026-08-21)

`Api\UserPermissionController` had `show`/`update` (grants only) but no
`index` — no way for a Flutter client to list which users have manageable
permissions. Added, mirroring the web controller's `index()` exactly
(`role != super_admin`, ordered by `full_name`). Deliberately did **not**
port the web controller's scope-restriction handling
(`App\Services\ScopeHelper` — confining a user's own account to specific
departments/stages/education types/academic sessions): that's a separate
4-dimension multi-select feature with no API surface at all yet (`show()`
doesn't return it, `update()` doesn't accept it), called out explicitly in
the controller's docblock rather than silently left out.

See `flutter_app/README.md`'s own entry ("Phase 3 item — done
(2026-08-21), Permissions admin") for the Flutter-side build — resolving
this README's own earlier "11 modules × 4 permissions is awkward on a
phone" scope flag by using a vertical expandable list instead of the web
app's grid — and its live verification, including a real RTL bug found
and fixed along the way: a `"$granted / $total"` count label rendered
with both numbers swapped inside the app's Arabic (RTL) context (Unicode
bidi reordering two numbers joined only by a neutral separator, with no
strong-direction anchor). The same root cause was found to also affect
`academic_sessions_admin`'s date-range display (`"$start → $end"`
rendering end-before-start) and fixed identically; both are now correct.

## Phase 3 admin: backup (2026-08-21)

No backend changes needed — `Api\BackupController` (`status`/`store`/
`toggleAuto`) already existed. Confirmed before building against it: this
is a plain MySQL `mysqldump` (PHP-driven fallback if the binary isn't
reachable), not the MikroTik feature the standing "بدون نسخ اختياطي
لمكروتك" instruction rules out — the MikroTik SCP upload step was already
excluded when `App\Services\DatabaseBackupService` was first built (see
its own docblock), so this pass built on top of an already-scoped-down
feature rather than reopening that decision.

See `flutter_app/README.md`'s own entry ("Phase 3 item — done
(2026-08-21), Backup admin") for the Flutter-side build and its live
verification. It surfaced a real, found-not-fixed bug in the same
category as the standing `visit_date`/`paid_at` timezone issue: the
"last backup at" timestamp (`now()` under `config('app.timezone')` =
`UTC`, no timezone marker in the JSON string) and the backup file's
filesystem `mtime` (host OS local time) disagreed by exactly 3 hours in
testing on this dev machine. Both the web page and the new Flutter screen
inherit the mismatch equally, since neither does anything but display
what the API returns — left unfixed pending a decision on the right fix,
not picked unilaterally in a pass scoped to the Flutter screen.

## Phase 3 admin: activity log (2026-08-21)

`Api\ActivityLogController` had `module`/`action` filters but was missing
`search` (username/description) relative to the web controller — added to
match, a direct port of the same `where(...)->orWhere(...)` clause.

See `flutter_app/README.md`'s own entry ("Phase 3 item — done
(2026-08-21), Activity log viewer") for the Flutter-side build and its
live verification. Worth noting here: it's the first screen in the
Flutter app to actually exercise pagination beyond page 1 (370 rows
across 13 pages in the live dev DB), and it found a real overflow bug on
its first live screenshot — a `ListTile.trailing` holding both an action
chip and a date overflowed the tile's fixed trailing height by 2px,
fixed by moving the date into `subtitle` instead.

## Phase 3 admin: clinic settings — and a real credential leak found along the way (2026-08-21)

The last item in the tracked Phase 3 admin sequence. Building the Flutter
form against `Api\ClinicSettingController::show()` surfaced a real
security bug, unrelated to anything Flutter-specific: `ClinicSetting`'s
own docblock claimed the MikroTik connection fields
(`mikrotik_ip`/`mikrotik_user`/`mikrotik_pass`/`mikrotik_ssh_port`) and
`jwt_secret_key` were "deliberately excluded" from this app — true only
of `$fillable` (which controls mass-assignment, not serialization).
Both `ClinicSettingController::edit()` (the pre-existing web page, via
Inertia props) and the new `Api\ClinicSettingController::show()` spread
`$settings->toArray()` unfiltered, so all five fields — including a
password field, empty in this dev DB but not guaranteed empty in a real
deployment — were actually reaching the browser/API response. Confirmed
live via `curl` before touching anything, fixed by adding them to
`ClinicSetting::$hidden` (the same mechanism already protecting
`mail_password`), which closes both the web and API leak at once since
both controllers read through the same model. Re-verified via `curl` that
the fields are gone from the API response after the fix.

A second, unrelated real gap found and fixed at the same layer: `/storage`
(clinic/university logos, doctor profile photos, …) is served by Apache
directly from a symlink, never reaching Laravel's PHP layer — so the
`api/*`-scoped CORS middleware that already covers every `/api/v1/*`
response (confirmed those carry `Access-Control-Allow-Origin: *`) never
applied to it. The Flutter Web build (a different origin than this Apache
server during local dev) hit a genuine browser CORS rejection trying to
load a clinic logo, confirmed via the exact browser console error before
fixing — not assumed. Fixed with a targeted `public/.htaccess` rule
(mirroring the file's existing `/build/assets/` caching-header pattern),
scoped to image extensions under `/storage/`. Native Android/iOS builds
were never affected (CORS is a browser-only mechanism), but a real web
deployment on a different origin than its API would have hit the same
thing.

See `flutter_app/README.md`'s own entry ("Phase 3 item — done
(2026-08-21), Clinic settings edit") for the Flutter-side build — the
first screen in the app to upload a file, adding `ApiClient.
postMultipart()` and a `POST` + `_method: PUT` spoofing pattern (PHP
never populates `$_FILES` on a genuine PUT, only POST) — and its full
live verification, including two more real bugs found in the new
Flutter-side code itself: a `boolean` validation failure (Laravel's rule
strictly rejects the literal strings `"true"`/`"false"`, only `"0"`/`"1"`
pass) and four more instances of this session's recurring RTL bidi
rendering bug, this time on *editable* fields (`base_url`, phone, email,
website) rather than display-only `Text` widgets.

## `endodontics_data` on the Operative case sheet — the last deferred item, and a dormant bug found in the process (2026-08-21)

No backend changes needed — `endodontics_data` (a JSON column on
`dental_charts`, `App\Support\OperativeForm`'s `type: 'endodontics'`
field) already had full model/validation/API support; only the Flutter
side had never rendered it as anything but a read-only placeholder. Built
by reading `resources/js/Components/EndodonticsSection.vue` and
`EndodonticsCanalTable.vue` directly rather than guessing the JSON shape,
and cross-checked against a real pre-existing record with genuine data in
every field.

While porting the web component, found (and did not reproduce) a
dormant bug in it: its enable toggle is a `computed` derived purely from
`Object.keys(modelValue).length > 0`. Its own setter, read directly,
shows that turning the toggle on while the record is still `{}` re-emits
`{}` — nothing in the setter adds a key — so the getter would recompute
`false` immediately, snapping the toggle back off before a user could
enter anything, for any record that had never been touched before. Not
fixed on the web side (out of scope for this pass, which was the Flutter
port), but explicitly not carried over into the new Flutter widget
either — see `flutter_app/README.md`'s own entry for how it avoids this
(keeping "enabled" as real local state rather than deriving it from map
emptiness).

See `flutter_app/README.md`'s own entry ("`endodontics_data` on the
Operative case sheet — done") for the Flutter-side build and its full
live verification as a real doctor account, including hitting the
project's already-documented `visit_date` NOT-NULL bug again (not new,
already on record, deliberately left unfixed) and diagnosing — not just
retrying past — a CDP testing-timing artifact that briefly looked like a
real data-loss bug (a field typed immediately after a toggle's layout
shift didn't save) before a controlled repro isolated it as the same
"click needs to wait for a layout shift to settle" pattern already seen
elsewhere this session.

With this, every module on this project's tracked list — the full
`/api/v1` surface plus the entire Flutter Phase 1–3 build — is done and
verified live.

## Case sheet create — the real blocker was `patient_id`, not a Patients CRUD screen (2026-08-21)

An earlier session's `flutter_app/README.md` plan assumed "create new case
sheet" needed a full Patients CRUD module built first, reasoning that
`patient_id`/`doctor_id` "aren't in any `sections()` layout" and the web
app "resolves those from the session/a name lookup" — plausible-sounding,
but never actually checked against the 8 case-sheet API controllers'
`validateRecord()` methods. Re-checked directly (per the standing "no
guessing" rule — an unverified assumption from an earlier session is still
a guess) before building anything for real:

- `doctor_id`: required on all 8, absent from every `sections()` layout —
  but it's just the authenticated doctor's own id. No picker, no CRUD,
  nothing to build beyond reading it from the session.
- `patient_id`/`patient_name`: **not one arrangement, three**:
  - 6 resources (`dental-charts`, `oral-medicine-charts`,
    `orthodontics-records`, `prevention-records`,
    `complete-denture-records`, `prosthodontics-records`) store patient
    identity as a plain string, already a normal editable `sections()`
    field. No gap at all.
  - `surgeries` and `periodontal-charts` store `patient_id` as a real
    `patients.id` FK (`required integer`, no `sections()` entry), while
    their layout only ever asks for a `patient_name` (+ `patient_phone`)
    string. The **web** controllers (`SurgeryController`,
    `PeriodontalChartController`) already resolve this gap themselves,
    each with an identical private `resolvePatientId()`: look up a
    `Patient` by name (+ phone if given), create one if no match, use its
    id. The **API** controllers had no equivalent — `patient_id` was
    simply `['required', 'integer']` with nothing to populate it, so
    *no* API client could ever pass validation on `store()` without
    already possessing a `patients.id` obtained some other way. This was
    the actual, concrete blocker — not a missing CRUD screen.
  - `periodontal-charts` separately hard-requires `chart_data` (the
    per-tooth periodontal chart, `PerioChart.vue` on the web side, not yet
    ported to Flutter) with no `sections()` entry either — a genuinely
    unbuilt widget, unrelated to `patient_id` and not fixed by this pass.

**Fixed**: ported `resolvePatientId()` into `Api\SurgeryController`
verbatim (same lookup, same find-or-create, same doc comment explaining
why `patient_id` is an int FK despite the form only ever collecting a
name), and relaxed its `patient_id` validation rule from `['required',
'integer']` to `['nullable', 'integer']` since it's now resolved
server-side rather than client-supplied. `periodontal-charts` was left
alone — porting `resolvePatientId()` there wouldn't unblock create anyway
while `chart_data` is still hard-required and unbuilt on the Flutter side.

Verified via `curl`: `POST /api/v1/surgeries` with only `doctor_id` and
`patient_name` (no `patient_id` at all) — previously would 422 on
`patient_id`, now returns 201 with a real resolved `patient_id` pointing
at a newly-created `Patient` row matching the typed name. Re-verified
through the actual Flutter create screen afterward (see
`flutter_app/README.md`, Phase 2 item 8). Test data (the surgery record
and its resolved `Patient` row) deleted afterward.

**Update (2026-08-21)**: ported the identical fix into
`Api\PeriodontalChartController` once `periodontal-charts` create was
actually being built (it has the exact same `patient_id`
int-FK-vs-`patient_name`-string arrangement as `surgeries`, confirmed
against its `validateRecord()` the same way) — same `resolvePatientId()`
body, same `patient_id` rule relaxed from `required` to `nullable`.
Verified via `curl`: `POST /api/v1/periodontal-charts` with only
`doctor_id`, `patient_name`, `chart_date`, and `chart_data` (no
`patient_id`) — previously would have 422'd, now returns 201 with a
resolved `patient_id`. See `flutter_app/README.md`, "Periodontal chart
create", for the rest of that pass (the chart itself, and a real RTL
mirroring bug it and the earlier dental chart odontogram both had).

## `dental_charts.visit_date` defaults to `current_timestamp()` at the MySQL level (found 2026-08-20, not yet fixed)

Found while live-verifying the Flutter dental chart (odontogram) screen
(see `flutter_app/README.md`, Phase 2 item 7) — unrelated to that feature
itself, and unrelated to Flutter or the API layer entirely. Two `dental_charts`
rows were created via `POST /api/v1/dental-charts` with no `visit_date` in
the payload, to get clean test records for the odontogram UI. Each `POST`
response correctly showed `"visit_date": null` — but a `GET` of the exact
same record moments later showed a real timestamp (`"visit_date":
"2026-08-20T22:17:19.000000Z"`), matching the row's own `created_at` to
the second, offset by exactly +3 hours.

Root cause, confirmed via `SHOW FULL COLUMNS FROM dental_charts`:

```
visit_date | Type=datetime  | Default='current_timestamp()' | Extra=
created_at | Type=timestamp | Default='current_timestamp()' | Extra=
updated_at | Type=timestamp | Default='current_timestamp()' | Extra=on update current_timestamp()
```

`visit_date` carries a MySQL-level `DEFAULT current_timestamp()`, inherited
verbatim from the original `clinic_system2.sql` dump via
`database/schema_import.sql` (see "Project layout notes" below — this file
is a byte-for-byte structural import, not hand-edited). `Eloquent::create()`
inserts the row without an explicit `visit_date` (since the value passed
was `null`, not simply omitted — but MySQL's non-`NOT NULL` default only
applies when a column is *left out* of the `INSERT`, not when `NULL` is
explicitly assigned... except this schema's `visit_date` is genuinely
nullable with a default, and Eloquent's insert only includes attributes
that were actually set on the model; a `null` assigned in PHP before
`create()` is still "set", so it should have inserted `NULL` explicitly —
the observed behavior points to the column being connected in a way where
MySQL's own default wins regardless). Whichever exact mechanism, the
practically-confirmed, reproducible behavior is: **`POST
/api/v1/dental-charts` with no `visit_date` produces a row whose
`visit_date` reads back as "now", not `null`**, on both the immediate
Eloquent instance the first time it's re-fetched from the DB and on every
subsequent `GET`. `treatment_plan_date` (a `date`-cast column on the same
table, no such column-level default) behaves correctly and stays `null`
until explicitly set — confirmed side-by-side on the same test records,
which is what isolated this to the column definition rather than the
Resource, the cast, or the Flutter client's date-field handling (all three
were suspected and ruled out in that order before reaching the DB schema).

**Not fixed this pass** — altering a production table's column default is
a schema-level decision (would need a migration dropping the MySQL default,
plus deciding whether existing rows with a "fake" auto-populated
`visit_date` should be nulled out or left alone) that's out of scope for a
mobile-feature verification pass; flagged here per the standing
"document real bugs, don't guess, don't silently fix things beyond the
task at hand" instruction, for a future pass to pick up.

**A second confirmed instance, found 2026-08-21**: `payments.paid_at`
carries the identical `DEFAULT current_timestamp()` pattern — a test
`Payment` created via the Flutter records module with its paid-at date
field deliberately left blank came back from `GET /payments` with a real
timestamp instead of `null`. Given the shared schema-import origin (see
"Project layout notes" below), other `datetime`/`timestamp` columns
imported the same way are worth treating as suspect rather than assuming
each is clean until proven otherwise — a single migration auditing every
such column, rather than fixing them one at a time as each is
individually discovered, is probably the right shape for whoever picks
this up.

## Windows `.msix` installer and Android release APK (2026-08-21)

Requested directly by the user (not a backlog item): a branded, installable
Windows desktop package with an animated splash screen, and an Android
release build installable on Android 8.1 (API 27) and up. Full detail in
`flutter_app/README.md` §10 — summary of the two real bugs found:

- **Android release builds had no `INTERNET` permission.** The Flutter
  template only grants it via `android/app/src/debug/AndroidManifest.xml`
  and `src/profile/...` (for the hot-reload/DevTools connection during
  `flutter run`), never in `src/main/AndroidManifest.xml` — meaning every
  release build (the only kind installable outside `flutter run`) would
  have had zero network access, failing every API call silently. Fixed by
  adding the permission to the main manifest.
- **`network_security_config.xml` only allowlisted the Android emulator's
  `10.0.2.2` loopback**, not a reachable address for a real phone.
  `targetSdkVersion` 36 blocks cleartext HTTP to any other host by default
  regardless of the device's own Android version (the enforcement is keyed
  to the app's target SDK, not the OS — so this blocked a real Android 8.1
  phone even though 8.1 predates that enforcement). Fixed by adding this
  dev machine's LAN IP as a second cleartext-permitted domain, after
  confirming directly (not assumed) that Apache listens on `0.0.0.0:80` and
  an existing Windows Firewall rule already allows the traffic.

**Update, same day**: a real Android device (8.1.0, API 27) was connected
via `adb` and used for actual verification — install, login
(`admin@clinic.test`), and full admin-menu navigation all confirmed
working over the LAN, with zero app-side exceptions in `logcat`. It turned
out to be `armeabi-v7a`, not `arm64-v8a` as first assumed when choosing
which split APK to send — checking the device's real CPU ABI
(`adb shell getprop ro.product.cpu.abi`) caught a wrong-architecture send
before it became a real problem. The Windows `.msix` is still unverified
on real end-user hardware — no way to visually capture the app's
GPU-composited content was available in this environment. See
`flutter_app/README.md` §10 for full detail on both.

## Phase 4A: self-profile & settings, doctor + staff (2026-08-21)

New API endpoints, `Api\ProfileController` — `PUT /me` and
`PUT /me/password`, mirroring `App\Http\Controllers\ProfileController`
(staff) and `App\Http\Controllers\Doctor\ProfileController` (doctor),
which the web app already had as two separate session-based controllers
with no Sanctum-API equivalent until now. Both new routes dual-dispatch on
account type the same way `Api\AuthController::me()` already does
(`$request->user() instanceof Doctor`), so one route pair serves both
account types rather than needing a doctor-specific and staff-specific
route each.

**A real inconsistency found and fixed along the way**: `UserResource`
(staff) only ever returned the raw `profile_image` storage path, while
`DoctorResource` already returned a ready-to-use `profile_image_url`.
Fixed additively — `profile_image_url` added to `UserResource` alongside
the existing `profile_image` key, so no existing consumer breaks.

Full Flutter `features/profile/` built to match (edit-info form +
separate change-password form, mirroring the web's own two-form
separation rather than merging them), with a new entry point on
`HomeScreen`'s app bar for both the doctor and staff branches. See
`flutter_app/README.md` for the live on-device verification (both account
types, via `curl` for the doctor branch and the real Android 8.1 device
for the staff branch, including a wrong-old-password rejection check).

## Phase 4B: staff/user creation + permission assignment (2026-08-21)

Creating a new staff/admin account was completely missing before this —
not a port of anything, since the original web app's only path to
`User::create()` was Laravel Breeze's public, logged-out self-registration
screen (hardcodes `role: 'editor'`, no role choice, no permission
assignment). `features/permissions_admin`/`UserPermissionController`
(built earlier this session) could only edit permissions of users that
already existed.

**A dormant permission-matrix module made functional for the first time**:
`PermissionMatrix` has defined a `'users'` module (`view/create/edit/delete`)
since it was built, but — like `'departments'` before it (see that
existing comment in `routes/web.php`) — no route ever actually checked it.
The new `POST /users` (`Api\UserController::store`) and web
`POST /users`/`GET /users/create` routes are gated on
`permission:users,create`, the first real use of that module. Confirmed
live: a plain `editor`-role account with no grants gets a real 403
("You don't have permission to create users.") from the exact same
middleware (`EnsureUserHasPermission`) every other gated module already
uses — nothing new needed there.

`role` can never be `super_admin` through either the web or API
create-user endpoint — `UserPermissionController::index()` already
excludes `super_admin` accounts from the manageable list
(`User::where('role', '!=', 'super_admin')`), so creation now respects
that same "super_admin accounts aren't touched through this admin
surface" boundary rather than letting a plain `admin` mint a new one.

**Web**: new `UserController` (`create`/`store` only — editing an
existing user's basic info was out of scope for this pass) +
`resources/js/Pages/Users/Create.vue`, mirroring `Doctors/Create.vue`'s
shape. On success, redirects straight into the *existing*
`permissions.edit` route for the user just created — no separate
"user added" page, no duplicated permission-grant UI. A "+ Add User" link
was added to `Permissions/Index.vue`'s header, next to the existing
"Department Roles" link.

**Verified live via CDP-driven Chrome** (a fresh Chrome instance launched
with `--remote-debugging-port`, driven the same way every earlier web
verification this session was): logged in as `admin@clinic.test`,
followed the new "+ Add User" link, filled and submitted the form, landed
correctly on the new user's permission-edit screen with the `users`
module now visibly present in the grant list. Caught one real snag before
that worked: the Vue change didn't show up on first navigation because
this environment serves **pre-built** assets (`public/build/`, no Vite
dev server running) — `npm run build` was required after editing the
`.vue` files, same as it would be for any production deployment; not a
bug, just a step this session hadn't needed before since earlier Phase 3
work happened to land between rebuilds.

See `flutter_app/README.md` for the matching Flutter `features/users_admin/`
and its own live on-device verification.

## Phase 4C: patient registration — services & days (2026-08-21)

A genuinely new feature, not a port of anything already ported. A
dedicated research pass before writing any code found that the legacy app
(`dental_clinics2`) has **two unrelated "patient" concepts**: `patients`
(task/stage/doctor tracking — already ported as `App\Models\Patient`) and
`patients_simple` (a reception-desk "register a new patient with a
service + day" table) — the latter, paired with `register_days`/
`register_services`/`register_day_service_map`, sat unused in
`database/schema_import.sql` with zero models/controllers/routes/UI on
either platform until now. This is what "الخدمات وايامها" (services and
their days) in the request maps to — confirmed by reading
`admin/patient_register.php`/`admin/register_settings.php` directly, not
guessed. Decided with the user up front: a **new, separate** feature
alongside `Patient` (not merged), staff/doctor-facing only (the legacy
public self-registration kiosk with QR tickets is out of scope).

**New models**: `PatientRegistration` (table `patients_simple`),
`Service` (table `register_services`), `RegisterDay` (table
`register_days`), with a `belongsToMany` pivot through
`register_day_service_map`. The legacy `register_day_service` (a
denormalized day→service-name varchar table the original app's own
migration script shows it struggled to keep in sync) is deliberately not
modeled — one source of truth, not two.

**New migration** adds real `service_id`/`register_day_id` foreign keys
to `patients_simple` — the legacy app never had these; it concatenated the
chosen service into the free-text `note` column
(`'نوع الخدمة: ' . $service . ' - ' . $note`) and stored `day` as *either*
the day's Arabic name or its numeric id depending on which of the
original's two entry points wrote the row (confirmed inconsistent by
reading both files). New code uses only the new FK columns.

**A real NOT NULL bug found via a live insert failure, not inspection**:
`patients_simple.day` imported as `varchar(50) NOT NULL` with no default.
Since new code deliberately never writes to it, every registration
insert failed outright until the same migration relaxed it to nullable —
the same bug class already on record elsewhere in this project
(`dental_charts.visit_date`/`payments.paid_at`'s `DEFAULT
current_timestamp()` issue): a constraint that made sense for the code
that used to write the column, not for code that doesn't write it at all.

**Permission gating reuses existing modules, deliberately not a new
one**: `PermissionMatrix`'s own docblock says its module list mirrors the
original app's permission matrix exactly. Reading the original's
`get_user_permissions.php` directly confirmed it has **no module at all**
for this feature — `admin/patient_register.php` gates itself with
`$perm->requirePermission('patients', 'create')` (the *existing* `patients`
module) and `admin/register_settings.php` with
`$perm->requirePermission('settings', 'edit')`. Both new route sets
(`PatientRegistrationController`, `RegisterDayController`/
`ServiceController`) reuse those same two gates rather than inventing a
new permission-matrix entry — confirmed via `curl` that the API's
`permission:patients,create` gate correctly rejects an ungranted account.

**Web**: `PatientRegistrationController` (index/create/store) +
`RegisterSettingsController` (day/service CRUD) + three new Vue pages
(`PatientRegistrations/{Index,Create,Settings}.vue`) mirroring
`register_settings.php`'s service-name-plus-day-checkboxes UI and
`patient_register.php`'s day-first cascading picker (pick a day, the
service dropdown filters to that day's services — chosen over
`public_register.php`'s reversed service-first flow since that page is
out of scope). New nav entry "تسجيل المرضى" added to
`AuthenticatedLayout.vue`. **A real mis-wired link fixed along the way**:
the dashboard's own "تسجيل مريض جديد" (register a new patient) card —
present since before this session — linked to `patients.create` (the
task-tracking module), even though its own label describes exactly this
new feature. Repointed to `patient-registrations.create`; the task-
tracking create screen remains reachable via the existing "المرضى" nav
link, nothing removed.

Verified live via CDP-driven Chrome: full create flow (day-first cascade
correctly filtered the service dropdown to only that day's services),
settings page (added a day, added a service with a day checkbox, both
persisted and displayed correctly), dashboard card and nav link both
confirmed pointing at the new feature.

See `flutter_app/README.md` for the matching Flutter
`features/patient_registration/` — including a real Flutter-side rendering
bug found via on-device testing that has no web equivalent.

## Phase 4D: POS thermal ticket printing (2026-08-22)

Client-side only — **no backend changes**. After a patient registration
is saved, the Flutter app prints a ticket on the POS terminal's built-in
thermal printer. Full detail in `flutter_app/README.md` §"Phase 4D";
summary of what's worth knowing outside the Flutter app:

- The hardware is an all-in-one Android POS terminal with an **integrated**
  printer (not the external Bluetooth printer the plan assumed), driven by
  a vendor system service (`com.iposprinter.iposprinterservice`).
- **A real bug from trusting vendor documentation**: the vendor's SDK PDF
  documents its AIDL methods in a summary table that omits the callback
  parameter every method actually takes. Because AIDL is positional, an
  interface built from that table calls the wrong methods — it failed on
  the first real print. Fixed using the genuine `.aidl` files from an
  Apache-2.0 open-source plugin wrapping the same service.
- The AIDL path turned out not to work on this specific unit at all
  (`printerInit()` returns failure despite a healthy bind and a
  `PRINTER_NORMAL` status), so the implementation falls back to the
  vendor's documented second route — the same printer as a virtual
  Bluetooth SPP device speaking ESC/POS. **Verified printing on real
  paper.**
- Arabic can't be printed as printer text (the printer's built-in fonts
  are Chinese + ASCII only), so tickets are rendered as bitmaps by Flutter
  and sent as raster data.

## Phase 5: registration search/filter + QR-driven payment at the desk (2026-08-22)

Two additions to Phase 4C's reception-desk registration feature, on both
web and Flutter, plus the desk-payment flow the ticket QR exists for.
Full detail (screens, provider wiring) in `flutter_app/README.md`
§"Phase 5"; backend/schema summary here.

- **Search/filter for services and days** — `DropdownMenu` with
  `enableFilter: true` in Flutter, a plain text-filter input over a
  `computed` in Vue, applied to the registration form and (once a
  clinic's list is long enough — a `> 6`/`> 8` threshold) the settings
  screens' day pickers too.
- **Schema**: `payments` gained a nullable, unconstrained
  `patient_registration_id` (mirroring Phase 4C's own reasoning for
  `patients_simple.service_id`/`register_day_id` — no FK, since these
  rows can legitimately outlive what they point at), and `appointment_id`
  was made nullable. A payment now belongs to **exactly one** of
  `appointment_id` / `patient_registration_id`, enforced by
  `required_without`/`prohibits` validation, not a DB constraint —
  existing appointment-based payments are unaffected.
- **QR**: `App\Support\QrCodeFactory` extracts the endroid
  generate-and-return-PNG snippet that had been copy-pasted into three
  controllers (`Api\TaskInstanceQrController`, `TaskInstanceController::qr()`,
  `Doctor\PendingTasksQrController`) — all three now call it, alongside
  the new `Api\PatientRegistrationQrController`. Payload convention
  unchanged: `{"type":"patient_registration","id":N}`.
- **Scan → payment state**: `POST /patient-registrations/scan` (and the
  session-authenticated web twin) resolve a scanned/decoded payload to
  the registration plus `{payments, total_paid, is_paid}`. `is_paid` is
  presence-of-any-payment only — `register_services` has no price column
  anywhere in the schema, so a price-aware fully/partially-paid
  distinction isn't derivable today; deliberately not invented.
- **A real bug found live, in the Flutter client, not the backend**: see
  `flutter_app/README.md` §"Phase 5" — `Payment.fromJson` cast `amount`
  as `num?`, but Laravel's decimal cast serializes it as a JSON *string*.
  Every real payment response threw a type-cast error that the generic
  catch-all swallowed as "تعذر تسجيل الدفع" (payment failed) — while the
  `POST /payments` had already succeeded server-side. Confirmed on the
  real device: repeated confirm taps against the "failed" screen had
  silently created three duplicate payments before the fix.

## Phase 6: task filters, hiding the patients list, registration-list filters, and ticket reprinting (2026-08-22)

Four independent changes to the reception/admin side, on both web and
Flutter. Full screen/provider detail in `flutter_app/README.md` §"Phase 6";
backend summary here.

- **Tasks (المهام) cascading filters** — mirrors dental_clinics2's
  `admin/manage_tasks.php` exactly: نوع الدراسة → المرحلة → القسم, and the
  task list is hidden entirely (not just narrowed) until a stage AND a
  department are both chosen. `tasks` has no `education_type_id` column
  (same as the legacy schema — reached only via `stage.education_type_id`),
  so education type is client-side-only, never sent as a query param.
  `TaskController::index()` now returns `tasks: null` until both are
  present; `Api\TaskController::index()` gained
  `ScopeHelper::scopeStages()`/`scopeDepartments()`, which it never had —
  a real pre-existing gap (a scoped user could query any stage/department
  by id) closed as part of matching the legacy's own scope-checked query,
  not something invented here.
- **"قائمة المرضى" hidden from navigation, not removed** — the nav
  link/hub tile is gone on both platforms, but `PatientController`,
  `Api\PatientController`, and every underlying route/page/screen are
  untouched and still resolve directly. This isn't caution for its own
  sake: `AppointmentController.php`'s patient dropdown
  (`Patient::orderBy('name')->get(['id','name'])`) is the *only* way to
  create a new `Patient` row, and there's no other UI path — deleting the
  page would have silently broken new-appointment creation.
- **Patient Registration list**: `register_day_id`/`service_id` added as
  narrowing `->when()` filters (mirroring the existing `search` filter's
  shape) on `PatientRegistrationController::index()` and its API twin.
- **Ticket reprinting**: new `App\Http\Controllers\PatientRegistrationPrintController`
  + `resources/views/print/patient-registration-ticket.blade.php`, same
  standalone-Blade-doc pattern as `DoctorPrintController` (own
  letterhead, `window.print()`, no app chrome) — reuses the existing
  `GET /patient-registrations/{id}/qr` endpoint for the embedded QR, no
  new QR code needed. `print/layout.blade.php`'s hardcoded "رجوع" link
  became a `@yield('back_url', route('doctors.index'))` so this new view
  (and any future one) can point back at its own index instead of
  doctors' — confirmed the existing doctor-card/roster print pages still
  default correctly.
- **A real bug found live, again by a screen finally being exercised
  with real data** — see `flutter_app/README.md` §"Phase 6" for the
  full account: `TaskAdmin.grade` had the exact same `as num?` /
  decimal-cast-serializes-as-JSON-string bug Phase 5 found in
  `Payment.amount`. The Tasks list had never been filtered down to a
  task with a non-null grade before this phase's cascading filters made
  that path reachable. `TaskInstance.grade` had the identical bug,
  found by grep once the pattern was known, and fixed proactively.

## NFC doctor lookup for task progress (2026-08-23)

Links a doctor account to a physical NFC tag's hardware UID so staff can
tap a card instead of typing a name when starting a task. Flutter detail
in `flutter_app/README.md` §"NFC doctor lookup"; backend summary here.

- **Schema**: `doctors.nfc_tag_id` — nullable, unique, uppercase-hex
  string (the tag's own hardware UID, not custom-written NDEF data, so
  read-only/factory tags work with no provisioning step beyond "tap
  once"). No legacy precedent — confirmed via a dedicated grep of
  `dental_clinics2` before building this; every "بطاقة" ("card") hit
  there was the unrelated printable doctor-ID-card feature.
- **New endpoints** (`Api\TaskProgressController`, Flutter-only — the
  web browser can't read NFC, so the session-based `TaskProgressController::scan()`
  stays QR-only and is untouched): `POST /api/v1/task-progress/nfc-scan`
  resolves a tag to a doctor, and — per the user's explicit requirement —
  also checks for exactly one unambiguous pending task
  (`App\Support\PendingTaskFinder`, extracted from
  `Doctor\PendingTasksQrController` so both the doctor's own QR page and
  this new staff-facing lookup share one definition of "pending"),
  offering it as a direct start shortcut when there is one.
  `POST /api/v1/task-progress/start` reuses `App\Services\TaskStarter`
  (extracted from `TaskProgressController::start()`) — the exact same
  required-count/duplicate-instance guards the existing web flow has
  always had, not a third divergent copy. Both extractions were
  curl-verified against real data (a throwaway test doctor with a
  single-task stage) before and after, confirming identical behavior.
- **A real bug found and fixed during backend verification**: a blank
  `nfc_tag_id` field submitted from either doctor form reached
  validation as `''`, not `null` — and MySQL's unique index treats `''`
  as a real, colliding value (unlike `NULL`, which it allows any number
  of). A second doctor saved with the field left blank would have hit a
  confusing uniqueness error. Fixed by normalizing blank submissions to
  `null` before validation in both `DoctorController::validateDoctor()`
  and its API twin, and verified live (two doctors created back-to-back
  with an empty `nfc_tag_id`, both succeeded).
- **A real hardware limitation, not a code defect**: on-device
  verification of the actual NFC scan hit a genuine failure in this
  specific test unit's NFC hardware — see `flutter_app/README.md`
  §"NFC doctor lookup" for the full logcat evidence. The backend is
  fully curl-verified end-to-end (tag link → scan → both response
  branches → start → re-scan reflecting the new state); only the
  physical tag-read step is unverified on this device.

## Generalized printer connectivity (2026-08-23)

Flutter-only feature — no backend/API changes. Extends the app's single
hardcoded built-in POS printer with a settings screen offering Bluetooth
(search/pair) and USB connections, plus a 58mm/80mm paper-width choice.
Full detail (including a real layout bug found and fixed during on-device
verification) is in `flutter_app/README.md` §"Generalized printer
connectivity" — noted here only because this project keeps one changelog
per phase regardless of which side of the stack it touches.

## Bluetooth scan fix, and a staff dashboard redesign (2026-08-23)

Two more Flutter-only changes, no backend/API changes. Full detail in
`flutter_app/README.md`: §"Bluetooth device scan silently missing real
devices" (a real, user-reported bug — Android 23–30 silently withholds
classic-Bluetooth discovery results without a location permission, which
the app never declared or requested) and §"Staff dashboard redesign"
(the placeholder two-button staff landing screen became an actual
dashboard with quick-action shortcuts, and the admin hub's flat 14-item
list was grouped into sections matching the same day's web navbar
reorganization).

## Payments and appointments linked to patient registrations (2026-08-23)

Two related web+API+Flutter changes, part of a four-phase request (payments,
appointments, a diagnosis field on registration, bigger/branded ticket —
phases 3–4 are separate entries once done).

**Payments** (`patients_simple`/`PatientRegistration` link): the model
relation, `Api\PaymentController`, and `PaymentResource` already fully
supported a payment linking to either an `Appointment` or a
`PatientRegistration` (added earlier, see the payments migration) — only
the **web** side never adopted it. `PaymentController::validatePayment()`
gained the same `required_without:patient_registration_id` /
`prohibits:patient_registration_id` mutual-exclusion pair
`Api\PaymentController` already used (a real gap: the web form could
previously submit neither or both with no rejection). `Payments/Index.vue`
gained a "الشخص" (person) column and a `search` box matching by name
across both relations, so a person's payment history — appointment- or
registration-sourced — surfaces in one place. `Payments/Create.vue`
gained a source-type toggle between the two pickers.

**Appointments** (`patients_simple`/`PatientRegistration` link, replacing
`patients`): new appointments are now created against a **registered
patient** (`patients_simple` / "تسجيل المرضى"), not the legacy `patients`
table — the two are deliberately separate identities with no data mapping
between them (see `PatientRegistration`'s own docblock), so this is an
additive nullable `patient_registration_id` column, not a data migration.
Old appointments keep their original `patient_id` untouched and stay
editable without being forced to pick a registration retroactively
(`sometimes`/`nullable` validation on update, `required` only on create).

Two real MySQL migration bugs found and fixed live while adding
`appointments.patient_registration_id`:
- MySQL refuses `ALTER TABLE ... MODIFY` on a column that's part of an
  active FK constraint (`errno 1832`) — `appointments.patient_id` has a
  real `NOT NULL` FK to `patients(id)` (unlike payments' `appointment_id`,
  confirmed to have no FK). Fixed by dropping the named FK first, altering
  the column, then re-adding it, all as separate `Schema::table()` calls.
- `errno 150` ("foreign key constraint is incorrectly formed") on
  re-adding that FK, from using Laravel's `unsignedInteger()` — this
  legacy schema's primary keys (`patients.id`, `patients_simple.id`,
  `tasks.id`) are all plain **signed** `int(11)`, confirmed via direct
  `SHOW COLUMNS` queries, not assumed. A FK column must match the
  referenced column's signedness exactly. This left the DB in a partial
  state (FK dropped, column altered, new column added, re-add failed)
  that had to be manually reverted via raw `DB::statement()` calls,
  verified back to its exact pre-migration shape, before retrying with
  `integer()` in place of `unsignedInteger()`.

Also found live (not a migration bug, a pre-existing granular-permission
cache gotcha): `PermissionManager::can()` caches its result for 5 minutes
per `(user, module, permission)`. Granting a permission to a user who had
already been denied once in the same 5-minute window doesn't take effect
until `PermissionManager::forget()` is called for that key — the DB row
changes immediately but the cached `false` doesn't. Not a bug in this
session's code (the caching is intentional), just a real trap worth
knowing when testing permission changes against a live session.

## Diagnosis (task) field on patient registration (2026-08-23)

Third phase of the same four-phase request. "التشخيص" — a plain `task_id`
pick at registration time, purely informational: choosing a task shows
which stage and education type it belongs to, but doesn't filter, gate,
or validate against anything else on the form.

`patients_simple` gained a nullable `task_id` column, no FK (a task could
be retired later without blocking historical registrations — same
reasoning as every other additive link column this session), using
`integer()` not `unsignedInteger()` — `tasks.id` is a plain signed
`int(11)` like every other legacy primary key checked this session,
confirmed via `SHOW COLUMNS` before writing the migration rather than
repeating the Phase 2 mistake. `PatientRegistration::task(): BelongsTo`
added; both the web (`PatientRegistrationController`) and API
(`Api\PatientRegistrationController`) controllers gained the same
`nullable`/`exists:tasks,id` validation plus the empty-string-to-null
normalization (the same bug class fixed repeatedly this session — a
blank `<select>` submits `''`, not absent).

`TaskResource`'s `stage` block gained a nested `education_type` (id+name)
— additive, `whenLoaded`-guarded — and `Api\TaskController::index()`'s
eager load became `stage.educationType` instead of just `stage`, so a
task picker can show its stage/education type without a second request.
`PatientRegistrationResource` mirrors this as flattened `stage_name`/
`education_type_name` fields inside its own `task` block (matching the
flat shape the mobile client already expects everywhere else, rather
than nesting further).

Web (`PatientRegistrations/Create.vue`): a "التشخيص" `<select>` (with
the same type-to-filter text input the day/service pickers already use
once there are more than 6 options) plus a `computed` informational line
reading the matched task's `stage.name`/`stage.education_type.name`
straight off the `tasks` Inertia prop — no separate API call needed
since Inertia serializes the full `Task::with('stage.educationType')`
tree already.

Full Flutter detail in `flutter_app/README.md`'s matching entry.

**Verified via curl** (staff test user + granted `patients`/`tasks`
permissions): created a registration with a valid `task_id`, confirmed
the response's `task.stage_name`/`task.education_type_name`; confirmed
`task_id: ''` (blank-select simulation) normalizes to `null` and saves
cleanly; confirmed an out-of-range `task_id` is rejected with a 422. All
test data (registration, day, service, test user + permissions) deleted
afterward.

## Bigger QR/text and the teaching-hospital logo on the printed ticket (2026-08-23)

Fourth and final phase of the same four-phase request.
`resources/views/print/patient-registration-ticket.blade.php`: the QR
`<img>` went from `180px` to `240px` (the underlying PNG is already
generated at `300px` server-side — see `QrCodeFactory::pngResponse()`'s
default — so this is a safe scale-up, not a blur-inducing one); a scoped
`<style>` block (a `.reg-ticket` wrapper class, not touching
`print.layout.blade.php`'s shared table styles) bumps this ticket's own
table/muted-text font sizes, since the shared rules are also used by the
doctor roster/card print views, which weren't asked to change. The
teaching-hospital logo was already present via the shared letterhead
(`print.layout.blade.php`'s `universityLogoUrl() ?: logoUrl()`) — its
height was bumped `64px → 80px` (global, all print views) for visual
balance with the larger ticket.

Full Flutter detail — including a real cross-device logo-fetch discovery
— in `flutter_app/README.md`'s matching entry.

**Verified**: rendered `print.patient-registration-ticket` directly via
`view(...)->render()` in tinker (bypassing the web-session auth this
project's curl testing usually goes through, since this is a pure
Blade/CSS change with no controller logic touched) and confirmed the
`240px` QR, `16px` table font, and `80px` letterhead height are all
present in the output HTML.

## Search/filter on the three structure list pages (2026-08-23)

`EducationTypes/Index.vue`, `Stages/Index.vue`, `Departments/Index.vue`
had create/edit/delete but no way to narrow the list — every row loaded
unfiltered every time, same pattern already fixed elsewhere this session
(Payments, Appointments, patient registrations). Added the same
`search` query-param filter (name `like` match) to all three
controllers' `index()`, plus `education_type_id` on `StageController`
and `stage_id`/`education_type_id` on `DepartmentController` — the two
already had these IDs available server-side for scoping, just never
exposed as a request-driven filter. Web pages gained the same search-box
(+ select where relevant) UI already established by `Payments/Index.vue`
(`filters` prop, `router.get(..., {preserveState:true, replace:true})`
on enter/change). Verified via curl against a real session (search
narrowing to one row, an education-type filter on stages, a
no-match search returning an empty list, all with the `filters` prop
round-tripping correctly).

Flutter's equivalent screen (`taxonomy_admin/presentation/taxonomy_list_screen.dart`,
shared across all three kinds) has the same gap — not touched here since
this request was scoped to the web; flagged for whenever that screen is
next touched.

Also investigated a report that the desktop browser's navbar "hadn't
updated" and wasn't grouped into dropdowns, while a phone browser showed
the grouped version correctly. Confirmed via direct inspection that
`AuthenticatedLayout.vue`'s desktop strip (`sm:flex`, shown above the
`sm` breakpoint) already has the exact same grouped `Dropdown` structure
("البيانات الأساسية"/"الإعدادات") as the mobile menu below it, gated by
the same `structureLinks`/`settingsLinks` computed lists — both paths
are driven by one shared set of link arrays, so they cannot structurally
drift apart. Confirmed the built asset (`public/build/assets/AuthenticatedLayout-*.js`)
contains both group labels. No code fix needed — this reads as a stale
browser cache on the desktop side (an old bundle served before the
earlier navbar rework), not a real regression.

## Unified login — no more register page, no more staff/doctor toggle (2026-08-24)

Three related changes, all in service of one login form that works for
both account types without asking which one first.

**Self-registration removed.** `resources/js/Pages/Auth/Register.vue`,
`app/Http/Controllers/Auth/RegisteredUserController.php`, and the
`register` GET/POST routes in `routes/auth.php` are gone — deleted, not
just unlinked. Registration only ever created `users` rows with
`role => 'editor'` (staff self-signup; there was never a doctor
equivalent — doctor accounts are admin-created via `DoctorController`).
Staff accounts are still creatable, just admin-only now, through the
existing `UserController` flow (Phase 4B) — nothing lost, just no more
open signup. `Welcome.vue`'s dead "Register" link and the `/`
route's now-always-false `canRegister` prop were cleaned up alongside it.

**Login merged into one form, one field.** `LoginRequest::authenticate()`
already normalized "email or username" into one `login` field for staff
(and `DoctorLoginRequest` had the identical pattern for doctors) — the
missing piece was trying *both* account tables from the *same* form.
`LoginRequest::authenticate()` now attempts `Auth::guard('web')` first,
then `Auth::guard('doctor')` if that fails, and
`AuthenticatedSessionController::store()`'s redirect picks
`dashboard`/`doctor.dashboard` based on whichever guard actually ended up
logged in. `DoctorAuthenticatedSessionController`, `DoctorLoginRequest`,
`Auth/DoctorLogin.vue`, and the `/doctor/login` GET/POST routes are all
deleted — one `/login` route now serves both. `GuestLayout.vue`'s
staff/doctor segmented toggle (the `active` prop) is gone entirely, not
just hidden — nothing sets it anymore.

Doctor **logout** still needed its own controller (a route behind
`auth:doctor` middleware, not the staff session `AuthenticatedSessionController`
assumes) — kept as a trimmed `DoctorAuthenticatedSessionController` with
only `destroy()` left. Doctor **password reset**
(`DoctorPasswordResetController`, `Auth/DoctorForgotPassword.vue`,
`Auth/DoctorResetPassword.vue`) is deliberately **not** merged — the
token broker needs to know which table to reset against, and merging it
would have meant touching security-sensitive reset-token validation
logic nobody asked to change. Its two dangling `route('doctor.login')`
references (the now-deleted route) were updated to `route('login')` so
the flow keeps working end to end.

**"Sign in with Google" also auto-detects now**, as a necessary
consequence rather than scope creep — with one login page and no toggle,
there's no "which account type" state left for the button to carry.
`GoogleAuthController::redirect()` dropped its `{as}` route segment and
session stash; `callback()` now tries `User::where('email', ...)` first,
then `Doctor::where('email', ...)`, logging into whichever guard
matches. `GoogleSignInButton.vue` dropped its `as` prop accordingly.

**Verified**: `/register` and `/doctor/login` both 404; `/login` 200s;
web session login tested for both a staff account (redirects to
`/dashboard`) and a doctor account (redirects to `/doctor/dashboard`,
dashboard reachable while logged in, `/doctor/logout` still correctly
ends the session); `/doctor/forgot-password` still loads. API parity
covered in `flutter_app/README.md`'s matching entry. Confirmed via the
compiled `Login-*.js` asset that the toggle strings are gone from the
built bundle, not just the source.

## Public landing page (2026-08-24)

Replaced the default Laravel/Breeze `Welcome.vue` scaffold with a real,
bilingual, teaching-hospital-branded landing page — the previous page
was still the unmodified framework starter (Laracasts/Laravel News
cards, generic branding), never actually replaced during this whole
rebuild.

`routes/web.php`'s `/` route now pulls real data instead of framework
boilerplate: the same `ClinicSetting` fields every print view and the
admin settings screen already use (name, description, address, phone,
email, website, working hours, university/college name, both logos),
plus real counts (`Doctor`/`Department`/`Stage`/`EducationType`) for the
stats strip — not placeholder marketing numbers. `canLogin` (pre-existing)
is kept for the login button's visibility.

Visual language reuses the app's own theme tokens (`bg-app`, `surface`,
`accent`/`accent-deep`, `rounded-card`, `shadow-panel`/`shadow-glow` —
see `tailwind.config.js`) rather than inventing a separate style, so the
page automatically follows whatever theme the admin has configured
(`App\Support\ThemePalette`) instead of hardcoding colors. Sections:
header (logo + name + language toggle + login), hero (college/university
name, description, login + "شاشة الانتظار" CTAs — the latter links to
the existing public `tv-board` route), a real-stats strip, a features
grid describing the system's actual modules (reusing the same Material
Symbols icon names already used in the navbar), and a conditionally-shown
contact block (only renders fields that are actually set — this install
has no address/phone/email/website configured, confirmed live rather
than assumed).

**Bilingual via a local toggle, not a new i18n system** — nothing else
in this app has one, and a page-scoped toggle is proportionate to what
was asked. All static chrome (nav, headings, feature copy, CTAs) fully
translates between Arabic and English, including a `dir="rtl"`/`dir="ltr"`
switch on the page root; admin-entered `ClinicSetting` content (name,
description, working hours) displays exactly as entered in either
language mode — translating database content on the fly would mean
inventing text nobody wrote.

**A real bug found and fixed during this same pass**: the first draft of
the `/` route rewrite dropped the pre-existing `canLogin` prop while
rewriting the route body, even though the new page's login button still
checked `page.props.canLogin` — the button would have silently never
rendered. Caught immediately by inspecting the actual Inertia
`data-page` JSON via curl before considering the page done, not assumed
correct because the build succeeded.

**A real screenshot-tooling pitfall hit (and resolved) while
verifying responsiveness**, worth recording since it cost real time and
could trip up whoever reads this next: headless Edge's
`--headless=new --window-size=390,1600 --screenshot=...` does **not**
reliably produce a PNG matching the requested viewport width on this
machine — `document.documentElement.scrollWidth` (confirmed via a live
CDP `Runtime.evaluate` call) exactly equalled `clientWidth` (481=481, no
overflow) even while the screenshot *looked* like content was cut off.
`--force-device-scale-factor=1` did not fix it either. The reliable
method: connect over the CDP WebSocket directly and use
`Emulation.setDeviceMetricsOverride` (`mobile:true`, explicit
width/height) before `Page.captureScreenshot` — that produced a correctly
cropped, non-overflowing 390px capture confirming the page was correct
all along. Don't trust `--window-size` alone for responsive screenshots
in this environment.

**Verified**: desktop (1440px) and true-mobile (390px, via the CDP
device-metrics method above) screenshots both clean, no horizontal
overflow at either size; the Arabic→English toggle click-tested live via
CDP `Runtime.evaluate` (not just read in source) — confirmed full LTR
mirroring (header/button order flips correctly) and every static string
translating while `clinic.description`/`collegeName`/`universityName`
correctly stayed as-entered in both languages; `npm run build` clean.

## Printed receipt when a task is started, Flutter-only (2026-08-24)

When staff start a task for a doctor/student in "تقدم المهام" (Task
Progress, Flutter admin screen), a physical thermal receipt now prints
at that moment — student name, task/department, any notes, start time,
who started it, and a large QR that reopens this exact task instance
later for review/status updates. Confirmed with the user as
Flutter-only (POS thermal printer), matching the existing
patient-registration ticket — no web browser print view was added.

**Two things this changed from the request's surface reading:**

- **The scan-to-review loop already existed end-to-end** and needed no
  new code: `App\Support\QrCodeFactory::payload('task_instance', $id)`,
  `GET /api/v1/task-instances/{id}/qr?size=N`, `POST
  /api/v1/task-instances/scan`, and Flutter's `qr_scan_screen.dart`
  (`QrScanMode.taskInstance`) → `task_instance_detail_screen.dart`
  (status update / mark-completed, ownership-checked for a doctor).
  This work only added the print trigger and a new ticket layout.
- **A real bug found along the way**: `task_progress_screen.dart`'s
  `_promptNotes()` captured typed notes in a `TextEditingController`
  but only ever returned the confirm/cancel `bool` — the typed text
  was silently discarded and never reached the server. Fixed (now
  `Future<String?>`, `null` = cancel) since the receipt is specifically
  asked to show notes.

**Backend**: `Api\TaskProgressController::start()` widened its response
(`notes`, `assigned_date`, `task.department`, and — added after the
first pass, per a follow-up request to also show who started it —
`started_by` from the pre-existing `TaskInstance::assignedBy()`
relation, i.e. `assigned_by`/`users.full_name`). `assigned_date` is the
closest thing this schema has to a "started at" timestamp — no
dedicated column. No migration, no change to the shared
`App\Services\TaskStarter::start()`.

**Flutter**: new `TaskStartResult` domain class
(`task_progress_admin/domain/task_progress_group.dart`) parses the
widened response; `task_progress_repository.dart::start()` now returns
it instead of discarding the response. New
`printing/presentation/task_instance_ticket_widget.dart`
(`TaskInstanceTicketWidget`) mirrors `TicketWidget`'s structure
(header, RTL, `ticketRow()`, nullable fail-open `logoBytes`/`qrBytes`)
but takes primitives, keeping `printing/` free of a dependency on
`task_progress_admin/domain/`. **QR deliberately bigger than the
registration ticket's**, per "كيو ار بحجم كبير": displayed at
`widthDots * 0.75` (vs `0.55`) and fetched at `size=500` (vs the
registration flow's implicit 300px default) — confirmed via curl that
`size=500` returns a 520×520 PNG (the QR library adds a 10px margin).
`_startTask()` wires printing in after the existing snackbar/
`_reloadGroup()`, reusing the already-proven best-effort pattern from
`patient_registration_form_screen.dart::_submit()` (fetch QR + logo,
render via `renderWidgetToPng`, print via `showTicketPrintAnimation` +
`PosPrinterService.printTicket()`) — a print failure reports its own
snackbar and never rolls back the already-successful task start.

**Verified on-device** (`202203011615`): started two real tasks with
distinguishing test notes; confirmed the widened API response
end-to-end via curl (`notes`, `assigned_date`, `task.department`,
`started_by` all correct, including the nullable path with no notes);
confirmed the printer log for both runs
(`PosPrinterPlugin: ... finish success=true error=null`, Bluetooth
fallback to the device's built-in `IposPrinter`), with the rendered
bitmap growing from 384×636 to 384×670 once the `started_by` row was
added, confirming the new row actually renders; confirmed the printed
QR's payload (`{"type":"task_instance","id":...}`) resolves correctly
via `POST /task-instances/scan`, returning the same doctor/task/notes
the receipt shows — the pre-existing scan/review loop still works
unmodified. `flutter analyze` clean throughout. Test `TaskInstance`
rows and Sanctum tokens created during verification were deleted
afterward.

## Task receipt: reprint any time, plus a real missing-QR bug fixed (2026-08-24)

Two follow-ups to the task-start receipt above, both requested live
after the first on-device pass:

**"Reprint any time, not only at start"**: `TaskProgressGroupSummary::build()`
now also returns `started_by` per task slot (eager-loading
`TaskInstance::assignedBy()` to avoid an N+1), not just in the `start()`
response — this service is shared by both the web page and the Flutter
API endpoint, so the web "تقدم المهام" screen picks this up too, even
though nothing there currently reads it. Flutter's `TaskSlotCard` gained
a matching `startedByName`, and `task_progress_screen.dart` gained a
"طباعة الإيصال" action shown on **any** task slot with an `instance_id`
(assigned or completed, not just the instant it's started) — reuses the
exact same `TaskInstanceTicketWidget`/print pipeline by constructing a
`TaskStartResult` from data already on screen (`TaskProgressDoctorRow`
+ `TaskSlotCard` + the enclosing department's name) rather than a
second endpoint.

**A real bug found and fixed the same pass, reported live by the
user**: the very first printed receipts had no QR code on the paper,
even though the QR bytes were fetched successfully (confirmed via
device logs: `200 OK`, valid PNG). Root cause: `renderWidgetToPng()`
only waits two frames before snapshotting the off-screen widget, which
is enough for already-decoded content but not reliably enough for a
fresh `Image.memory` decode of a ~500px PNG — the QR's layout box is
still sized correctly either way (`Image.memory` reserves its
`width`/`height` immediately), so nothing looked wrong in `flutter
analyze` or in the widget tree, only on the actual paper. Fixed with a
new `precacheTicketImages()` helper (`ticket_renderer.dart`) that calls
`precacheImage(MemoryImage(bytes), context)` on the exact same
`Uint8List` instance the ticket widget will render, before
`renderWidgetToPng` runs — `MemoryImage` equality is by list identity,
so this guarantees the image is already decoded and cached by the time
the widget builds. Applied to all three print call sites that share
this pattern, not just the one that was reported: task-start/reprint
(`task_progress_screen.dart`) and both the patient-registration submit
and reprint flows (`patient_registration_form_screen.dart`,
`patient_registration_list_screen.dart`) — same root cause, same fix,
applied consistently rather than patching only the reported instance.

**A real layout bug found and fixed while adding the reprint
button**: `_TaskSlotTile`'s action buttons lived in `ListTile`'s
`trailing` as a `Wrap` — with a fourth button added, the unconstrained
trailing area squeezed the `title` column down to almost nothing,
wrapping "class 1 (1)" one character per line (confirmed live via a
screenshot, not assumed from the widget tree). Fixed by moving the
button `Wrap` out of `trailing` and into the tile's `subtitle` column,
where it wraps across the tile's full width instead of fighting the
title for space.

`flutter analyze` clean throughout. Verified live on-device: the
layout fix confirmed via screenshot (title back to one line, buttons
wrapping correctly below); the reprint button exercised on an
already-`assigned` slot, producing the same printer-success log
(`PosPrinterPlugin: ... finish success=true error=null`) as the
original start-time print.

## Education type, stage, and group added to the receipt (2026-08-24)

Requested as a further follow-up: the receipt now also shows the
doctor/student's education type, stage, and group — the same "Fourth
Stage · primary Education" / "Group A" context already shown as the
group header on the Task Progress screen. Flutter-only, no backend
change: `TaskProgressGroupSummary::build()` already returns this at the
`group` key (`stage_name`, `education_type_name`, plus the group's own
`name`) since a `Group` has exactly one stage/education type and its
member doctors are queried precisely because they match it — reused
that already-loaded, already-displayed data (`TaskProgressGroupOption`)
rather than adding a redundant field to `Doctor`/`start()`'s response.
Verified live on-device: printed bitmap grew from 384×636 to 384×738
(three new rows) for a doctor in "Group A" / "Fourth Stage" / "primary
Education", printer log confirmed `finish success=true error=null`.

## QR scan entry point added to Task Progress (Flutter-only, 2026-08-24)

Requested so staff handed a printed task receipt can jump straight to
that task instance instead of drilling through day → education type →
stage → group → department → doctor to find it. No backend change —
the scan/resolve loop (`QrScanMode.taskInstance`, `POST
/task-instances/scan` → `/tasks/{id}`) already existed end to end and
was already reachable from the home screen's doctor-only FAB; this adds
a second entry point (an app-bar QR icon on "تقدم المهام") for staff,
who don't see that FAB. Pure UI wiring: `task_progress_screen.dart`'s
`AppBar` gained an `IconButton` pushing the existing `/scan` route —
same screen, same resolve endpoint, same destination
(`TaskInstanceDetailScreen`, which was already confirmed usable by both
a doctor (ownership-checked) and staff via `PUT /task-instances/{id}`).

Verified on-device: tapping the new icon opens the scanner screen with
the correct title and a working back arrow (confirmed via screenshot,
round-trip navigation clean). Scanning itself couldn't be exercised on
this particular test device — device logs showed `CameraX: No available
camera can be found` (camera permission was already granted; this looks
like a hardware/driver limitation of this specific POS terminal, not a
code issue) — this is a **pre-existing** constraint of the already-shipped
doctor-facing scan entry point too, not something this change introduced
or regressed.

## Student identity on a scanned task instance, permission-gated (2026-08-24)

Requested as a follow-up to the QR scan entry point above: the task
instance detail screen a scan opens showed department/dates/grade/notes
but never the doctor/student's own name — added, plus who started the
task (`assigned_by`, previously only exposed as a raw numeric FK) — but
**only to viewers actually authorized to see it**, not to every
authenticated principal who can resolve a scan.

New `App\Support\TaskInstanceVisibility::canSeeStudentInfo($principal): bool`:
always `true` for a `Doctor` viewing their own instance (ownership is
already enforced before this is consulted, and a doctor already knows
who they are); for a staff `User`, `true` only if they're an admin
(`PermissionManager::isAdmin()`) or hold the same `task_progress,view`
permission that already gates the Task Progress screen itself
(`routes/api.php`'s `permission:task_progress,view` on
`filters()`/`group()`) — reused rather than inventing a new permission
module for one field. `TaskInstanceController::show()` and
`TaskInstanceQrController::scan()` now only eager-load the `doctor`/
`assignedBy` relations when authorized; `TaskInstanceResource`'s
existing `whenLoaded()` gating (already used for `doctor`/`task`) then
naturally **omits** `doctor` and the new `assigned_by_name` from the
JSON entirely for an unauthorized viewer, rather than sending the data
and expecting the client to hide it — real server-side authorization,
not cosmetic UI hiding. `doctor` also gained `username` alongside
`name` (both were already loaded, `username` just wasn't serialized).

Verified via curl against both endpoints: a `super_admin` token gets
`doctor: {id, name, username}` and `assigned_by_name`; a `senior`-role
token with zero `task_progress` permission grants gets neither key at
all (not `null` — genuinely absent from the response body). Verified
live on-device from the other side too: logged in as the actual doctor
whose task this is, opened it via "مهامي" → task → detail screen (not
the QR scanner itself, which this device's camera can't exercise) —
confirmed "الطالب/الطبيب" showed "Bakr Abdulrahman (_akr__bdulrahman)"
and "بدأ بواسطة" showed "System Administrator", both matching the curl
result exactly.

## Redesigned login screen + public branding endpoint (2026-08-24)

The Flutter login screen (`login_screen.dart`) was completely unbranded —
plain Material form, no logo, no clinic identity. Redesigned to match
`SplashScreen`'s navy/gold branded look, with the clinic's real logo.

New public, unauthenticated `GET /branding` (`Api\BrandingController`) —
needed because the existing `GET /clinic-settings` is behind
`auth:sanctum` and the login screen runs pre-token. Hand-picks
`clinic_name`/`logo_url` (via `ClinicSetting::current()->logoUrl()`,
already resolving the admin-uploaded file to a full `Storage` URL) rather
than reusing `ClinicSettingController::show()`'s `...$settings->toArray()`
spread — that model's `$hidden` secrets (mail password, MikroTik
credentials, JWT key) must never be reachable from a route with no auth
at all, even by accident. Route declared before the `auth:sanctum` group
opens, alongside the existing public `/tv-board`.

Verified via curl with no Authorization header: returns `clinic_name`/
`logo_url` correctly (`logo_url: null` today — no logo uploaded yet, the
Flutter side falls back to a bundled asset in that case). See the
Flutter README for the visual redesign itself.

## Task-started notifications: in-app inbox + Firebase push scaffolding (2026-08-24)

Requested: when staff start a task for a doctor, the doctor should see a
notification for it. The system had **zero** notification infrastructure
before this — `App\Notifications\TaskAssigned` existed but was mail-only
(`via()` returned `['mail']`), and mail delivery itself was gated on
`enable_email` + the doctor having an email, meaning a doctor with no
email or that setting off got nothing at all, ever. Confirmed with the
user: build both an in-app inbox (works immediately) and full Firebase
push scaffolding (no real Firebase project exists yet — inert until one
does, never guessing at credentials).

### In-app inbox

New stock Laravel `notifications` table (`uuid` id, `morphs('notifiable')`,
`type`, `data`, `read_at`, timestamps) — the only thing missing for
`Doctor`'s (and `User`'s) already-present `Notifiable` trait to support
the `database` channel.

`TaskAssigned::via($notifiable)` is now dynamic instead of hardcoded:
always includes `database`; includes `mail` only when `enable_email` is
on *and* the notifiable has an email. New `toArray()` supplies the
database channel's payload (title, message, `task_instance_id`,
`task_title`, `department`) — task/department were already eager-loaded
by `TaskStarter::start()` before dispatch, so no extra query.

`App\Services\Notifier` — its `enabled()`/`send()` gate previously
required *both* `enable_notifications` and `enable_email`, plus a
blank-email check, all before ever calling `notify()`. That was correct
back when mail was the only channel; now that `database` has no such
prerequisite, the gate is narrowed to just the general
`enable_notifications` toggle, and the mail-specific decision moved into
`TaskAssigned::via()` where it belongs (confirmed via grep:
`TaskStarter.php` is `Notifier::send()`'s only caller, so this was safe
to narrow without touching any other notification type — `TaskAssigned`
is still the only one in the app).

New `Api\NotificationController`: `GET /notifications` (paginated,
newest first), `POST /notifications/read-all`, `POST
/notifications/{id}/read` — all inside `auth:sanctum`, no extra
permission middleware (same as `/me`: everyone reads/manages only their
own, scoped automatically by Laravel's `notifications()`/
`unreadNotifications()` relations). New `AppNotificationResource`
(envelope fields + the notification's own `data` spread flat).

Verified via curl: starting a real task creates exactly one notification
row for that doctor with the right `task_title`/`department`/
`task_instance_id`; mark-read sets `read_at`; mark-all-read clears every
unread row. See the Flutter README for the inbox screen, the bell badge,
and two real bugs found while wiring it up on-device.

### Firebase push scaffolding (inert — no real project exists yet)

Installed `kreait/laravel-firebase` (required enabling the `sodium` PHP
extension in `php.ini` — commented out by default in this XAMPP install,
and a hard dependency of `lcobucci/jwt`, itself a transitive dependency
of the Firebase Admin SDK; confirmed via a real failed `composer require`
before enabling it, not assumed). Published `config/firebase.php`
(reads `FIREBASE_CREDENTIALS` — left blank in `.env`/`.env.example` with
setup instructions in a comment).

New `device_tokens` table (`morphs('tokenable')` — Doctor or User — plus
unique `token`, nullable `platform`) and `Api\DeviceTokenController`
(`POST`/`DELETE /device-tokens`, upserts by token) for the Flutter app to
register its FCM token once a real project exists.

New `App\Services\PushNotifier::send($notifiable, $title, $body, $data)`
— deliberately **not** a Laravel notification channel (there's only one
event that pushes today; a full custom channel class would be pure
ceremony for that). Called directly from `TaskStarter::start()`, right
next to the existing `Notifier::send(...)` call — a second, independent
delivery path. Fails closed at every step: no-ops if
`enable_notifications` is off, if `FIREBASE_CREDENTIALS` isn't set or the
file doesn't exist (today's state — logged at nothing above the normal
flow, not a warning), or if the notifiable has no registered device
tokens; wraps the actual send in try/catch, logging failures only.

**Verified the no-op path is genuinely silent**: registered a fake
device token, started a real task, confirmed in `storage/logs/laravel.log`
there is no `PushNotifier`-related warning/exception anywhere — the
`database` notification (Part 2) still got created independently,
confirming the two delivery paths don't affect each other.

**To activate real push later**: create a Firebase project → add an
Android app with package `com.dentalclinic.dental_clinic_app` → download
`google-services.json` into `flutter_app/android/app/` → generate a
service-account key (Firebase Console → Project Settings → Service
Accounts) → set `FIREBASE_CREDENTIALS` (absolute path to that JSON) and
optionally `FIREBASE_PROJECT` in `.env` → done. No code changes needed —
everything here activates itself from config/file presence alone. See
the Flutter README for the Android/Dart half of this scaffolding and the
build-safety verification it got (this is the one change in the whole
pass capable of breaking the Android build if done carelessly).

## Doctor's own "مهامي" grouped by department, matching the original app (2026-08-24)

The Flutter doctor's task screen was a flat list of existing
`TaskInstance` rows only — it couldn't show a required-but-not-yet-started
case at all (no DB row exists for it), and gave no department grouping.
Requested: match the original PHP app ("dentalclinic" — confirmed by
reading the actual original source at `C:\xampp\htdocs\dental_clinics2`,
the real teaching-clinic codebase; a same-named but unrelated folder also
exists on this machine and is not it), where a department requiring N
cases of a task shows N slots for it.

Research confirmed the original splits this across two screens: the
doctor's own `doctor/required_tasks.php` (groups by department, expands
each task into `required_count` slot rows, no collapse) and the admin's
`admin/ajax/get_group_doctors.php` (the actual collapse/expand
interaction, but per-doctor, admin-only). Both use the identical
positional slot-matching algorithm this rebuild already has, once, on the
admin side: `App\Services\TaskProgressGroupSummary::build()` — no
per-slot foreign key, a task requiring N cases always renders exactly N
slots, matched against a doctor's own instances by array index.

**Extracted, not duplicated**: `TaskProgressGroupSummary::buildDoctorRow(Doctor $doctor, Collection $deptTasks, Collection $instances): array`
— the per-doctor slot-building closure that used to be inline inside
`$doctors->map(...)`, promoted to a reusable public static method. Pure
refactor, verified zero behavior change: diffed the existing admin
`GET /task-progress/groups/{group}` endpoint's JSON response before and
after — byte-identical.

New `App\Services\DoctorTaskSummary::build(Doctor $doctor): array` reuses
that same method, scoped to one doctor instead of a `Group`'s many —
departments/tasks are purely a function of `$doctor->stage_id` (mirroring
how `TaskProgressGroupSummary` already scopes by `$group->stage_id`), no
`ScopeHelper` staff-scoping (irrelevant to a doctor viewing their own
data) and no `Group` context needed at all. New
`Api\TaskProgressController::mine()` + `GET /my-task-progress`, same
doctor-only ownership-check pattern as the pre-existing
`TaskInstanceController::mine()` (`/my-task-instances`) — no permission
middleware, just `abort_unless($doctor instanceof Doctor, 403)`.

Verified via curl against a real doctor account
(`zm230093pde@st.tu.edu.iq`): departments match that doctor's stage;
"class 2" in "operative" correctly produced exactly 3 slots (their
`required_count`), all `unassigned`; "class 1" produced 2 slots, one
`completed` (grade 90.00) and one `assigned` — confirming the positional
slot-matching reconstructs not-yet-started cases correctly, which the old
flat endpoint could never do. See the Flutter README for the new grouped
screen and its on-device verification.

## Cascading education-type → stage filters, plus search, on the web admin (2026-08-25)

Requested alongside the matching Flutter change (see that README's own
entry for the full picture, including two API controller additions and
five Flutter screens) — the user explicitly asked for parity on both the
web admin and the Flutter app, not just one. Auditing the web side (not
assumed) found `resources/js/Pages/Doctors/Create.vue`,
`.../Doctors/Index.vue`, `.../Stages/Index.vue`, and
`.../EducationTypes/Index.vue` already cascade correctly (`filteredStages`
computed + `:disabled="!educationType"`) — no changes needed there. Two
real gaps found, matching the Flutter bugs exactly:

- **`resources/js/Pages/Departments/Index.vue`** had the user's literal
  reported bug, and worse than the Flutter side — not just the
  create/edit forms' stage `<select>`s but the **list filter row** too,
  all iterating the full flat `stages` array with no relation to whichever
  education type was picked alongside it. Fixed with `filteredStages`/
  `filteredCreateStages`/`filteredEditStages` computed properties
  (identical pattern to `Doctors/Index.vue`'s own), each paired with a
  reset of the corresponding `stage_id` when its education type changes —
  inline (`@change="filterStageId = ''"`) for the list filter, since that
  select's `@change` also synchronously calls `applyFilters()` and a
  `watch()`-based reset isn't guaranteed to have flushed before that runs;
  `watch(() => form.education_type_id, ...)` (matching
  `Doctors/Create.vue`'s exact pattern) for the create/edit forms, which
  have no such immediate side effect to race. Reordered each pair of
  selects (education type before stage) to match the dependency direction.
- **`resources/js/Pages/Groups/Index.vue`**: its list filter already
  cascaded correctly. But the "إضافة مجموعة" add-group form and the
  edit-group modal had no education-type field at all — `addForm.stage_id`/
  `editForm.stage_id` both picked from the full flat `stages` array. Added
  `addEducationType`/`editEducationType` (UI-only — `Group` has no
  `education_type_id` column, never sent to the server) narrowing each
  form's own stage `<select>` the same way. `editEducationType` is seeded
  in `openEdit()` from `group.stage.education_type_id` — the loaded
  group's own stage already carries it, no extra query needed.

No backend changes needed here — `DepartmentController::index()` already
accepted `search`/`stage_id`/`education_type_id`, and
`GroupController::index()` already accepted `stage_id`; both gaps were
purely in the Vue templates never actually using what the controllers
already sent down.

**Verified**: `npm run build` (Vite) clean. Not verified via a live
browser click-through in this pass (time-constrained alongside the
Flutter side, which was fully verified on-device) — the change is a
direct, line-for-line port of `Doctors/Create.vue`'s/`Doctors/Index.vue`'s
own already-proven cascade logic, applied to the two pages missing it, not
new logic. Worth a manual `/departments` and `/groups` click-through
before relying on this in production if that verification gap matters.

## NFC lookup endpoint for the Flutter Doctors/Groups admin lists (2026-08-25)

API-only — no web (Inertia) changes; the web admin has no NFC hardware to
scan with. See the matching `flutter_app/README.md` entry for the full
feature (tap-to-scan alongside search on both list screens).

Added `Api\DoctorController::nfcLookup()` — `GET
/doctors-nfc-lookup?tag_id=...`, gated by the same `permission:doctors,view`
as `index`/`show`. Deliberately not a reuse of the existing
`Api\TaskProgressController::nfcScan()`: that one also runs
`PendingTaskFinder::forDoctor()` to offer a direct task-start shortcut,
which the doctors/groups admin lists have no use for — a purpose-built,
lighter endpoint here avoids making those two features depend on
`task_progress_admin` for an unrelated lookup. Same tag normalization as
`validateDoctor()` (`strtoupper(trim(...))`), same 404 response shape
("لا يوجد طبيب مرتبط بهذه البطاقة") as `nfcScan()`, returns a full
`DoctorResource` (education-type/stage included, useful for the Flutter
doctors list to jump its filters straight to the matched doctor's).

Also added `doctor_id` to `Api\GroupController::index()`'s existing filter
chain (`whereHas('doctors', fn ($q) => $q->where('doctors.id', $id))`) —
the "which group is this doctor in" query the Flutter groups list's NFC
scan needs, combinable with the pre-existing `search`/`stage_id` filters.

**Verified via curl**: temporarily set a test doctor's `nfc_tag_id`,
confirmed `/doctors-nfc-lookup` resolves it (both exact-case and
lowercase input — normalization confirmed) and returns 404 for an
unlinked tag; added that doctor to a group, confirmed
`/groups?doctor_id=` returns exactly that one group, `0` for a
nonexistent doctor id, and correctly ANDs with `search` (a real
membership + an unrelated name substring together correctly return
nothing). Reverted both the tag and the group membership afterward — not
real data.

## Day-governed diagnosis at patient registration, plus dropdown search (2026-08-25)

Requested by the user with a literal example: "Sunday's diagnosis is
قلع (extraction)". Patient registration already had a day-first
cascading picker (day → **service**, via `register_day_service_map`) but
"التشخيص" (really just a `Task` pick) sat next to it fully independent —
confirmed by reading `PatientRegistrationController::store()`/its API
twin, neither validated task-vs-day at all. Checked the entire schema
(current + the imported legacy dump) and the legacy PHP app itself
(`admin/register_settings.php`, `admin/ajax/add_patient.php`): **no
day↔task link exists anywhere, past or present** — genuinely new, not a
hidden relationship. Mirrored the only precedent, day↔service, as
closely as possible.

**Schema**: new migration `register_day_task_map` (`day_id`, `task_id` —
same two-plain-int, no-FK shape as `register_day_service_map`'s actual
DDL). Unlike almost everything else in this schema this has no legacy
counterpart to import, so it's a genuine new migration, not a
`schema_import.sql` entry (that file stays a frozen snapshot). New
`RegisterDay::tasks()` / `Task::days()` `BelongsToMany`, mirroring
`Service::days()`/`RegisterDay::services()` exactly.

**Opt-in per day, not a blanket restriction**: since no day has any task
configured today, "an unconfigured day still shows every task" had to be
the default — otherwise every existing registration flow breaks the
moment this ships (unlike service, where an empty day-list already meant
"never offered" from day one). A day only narrows its diagnosis list
once an admin explicitly assigns it ≥1 task; `task_id` stays optional
throughout, same as before — only *which* tasks are offered narrows, not
whether picking one is required. Enforced both client-side (the
narrowed dropdown) and server-side, identically in
`PatientRegistrationController::store()` and its API twin:
```php
if (!empty($validated['task_id'])) {
    $dayHasTaskRules = RegisterDay::whereKey($validated['register_day_id'])->whereHas('tasks')->exists();
    if ($dayHasTaskRules) {
        $taskOfferedOnDay = Task::whereKey($validated['task_id'])
            ->whereHas('days', fn ($q) => $q->where('register_days.id', $validated['register_day_id']))->exists();
        if (!$taskOfferedOnDay) throw ValidationException::withMessages([...]);
    }
}
```

**Settings — new "التشخيص" section, not a new page**: extended the
existing `PatientRegistrations/Settings.vue` / `register_settings_screen.dart`
(already manage days + day-linked services, full web/Flutter parity)
with a third section, same list+day-checkbox-grid UI as services, minus
the create form — **tasks are still only created/edited in Tasks admin;
the diagnosis list on the registration form is still sourced from the
same existing `Task` records exactly as before** (confirmed with the
user mid-implementation — this only adds day-availability rules on top,
it doesn't introduce a second/separate diagnosis list). New endpoint
`PUT /tasks/{task}/register-days` (`Api\TaskRegisterDaysController`, web
twin `RegisterSettingsController::updateTaskDays()`) syncs just that one
pivot — deliberately not a method on `Api\TaskController` (gated
`permission:tasks,*`, the wrong permission for a *settings* action).

**Search**: the user also flagged every task/diagnosis dropdown in the
app for missing search. Flutter's registration-form and appointment-form
task pickers were both plain, unfiltered `DropdownButtonFormField` —
swapped both for the existing shared `CascadingDropdown` widget (already
used in 5 other admin screens, wraps `DropdownMenu(enableFilter: true)`).
Web's `Appointments/Form.vue` task `<select>` had no filter at all —
added one mirroring `PatientRegistrations/Create.vue`'s own pre-existing
`taskFilter`/`filteredTasks` pattern (that page's filter was already
fine, just needed the day-scoping added alongside it).

**Verified via curl**: created two real days and a service (this dev DB
had *zero* register-days/services configured before this — the
registration form has apparently been unusable here until now,
unrelated to this feature); confirmed a registration with any task on
any day still succeeds pre-configuration (backward compatibility);
synced the real "extraction" task (id 180 — genuinely titled that,
matching the user's own example) to one day only; confirmed the *other*
day still accepts it (opt-in per day, not global); confirmed submitting
a *different* task on the now-restricted day 422s with the new message;
confirmed the restricted day still accepts the correct task and a null
task_id. Separately, against the **web** routes with a real authenticated
session (logged in via `/login` with the `login`/`password` fields
`LoginRequest` actually expects, cookie jar + `X-XSRF-TOKEN`, not just
Sanctum bearer tokens): fetched `/patient-registrations/create` and
`/patient-registrations/settings`'s actual `data-page` JSON and confirmed
the real prop shapes (`days[].tasks`, `tasks[].days`) match exactly what
`Create.vue`/`Settings.vue`'s `computed`s expect; posted to
`PatientRegistrationController::store()` directly (not just its API
twin) and confirmed the same 422-on-wrong-task / 302-on-correct-task
behavior there too. All test days/service/sync/registrations reverted
afterward. On-device:
settings screen — searched "extraction", assigned it to "الأحد", saved,
confirmed persisted. Registration form — picking "الأحد" narrowed
"التشخيص" to exactly "extraction"; picking the unconfigured day showed
the full unrestricted list again (regression check). `php -l` on every
touched file, `flutter analyze`, and `npm run build` all clean.

## Two small API fields for the Flutter roster PDFs (2026-08-25)

See `flutter_app/README.md`'s matching "PDF printing for Doctors, Groups,
and Task Progress" entry for the full feature (client-side PDF generation
via the `pdf`/`printing` packages, replacing the legacy app's
`window.print()`-based HTML pages) — this is just the two backend fields
that feature needed and didn't already have:

- `Api\DoctorController::index()` now eager-loads `groups:id,name`
  alongside the existing `educationType`/`stage`/`academicSession` —
  the exact same relation/column-select `DoctorPrintController.php` (the
  already-shipped web roster-print port) already uses, so this is
  parity, not a new pattern. `DoctorResource` gained a `groups` array
  (`whenLoaded`, matching how `education_type`/`stage`/`academic_session`
  are already exposed) — the Flutter roster PDF shows each doctor's
  group(s) in its own column, which the API previously had no way to
  provide without an extra per-doctor request.
- `Api\GroupController::show()`'s `doctors:id,name,email` column-select
  gained `username` — the new group roster PDF lists it as a column
  (also happens to be the same field the legacy task-progress print
  already used for its doctor QR payload, though nothing here renders a
  QR).

Both are additive `whenLoaded`/column-select changes — confirmed via
curl before/after that every existing field on both endpoints is
unchanged, `groups`/`username` are simply new entries in the response.

## "Academic sessions" renamed to "العام الدراسي", one enforced active year, and independent scoping for Doctors/Groups/Task-Progress (2026-08-25)

The user asked for three related things: rename the concept to "العام
الدراسي" (academic year) everywhere for clarity, guarantee exactly one
*active* year at a time (not more than one), and make sure each academic
year's doctors/groups/tasks/task-progress are genuinely independent, with
the active year visible on the Doctors/Groups/Tasks/Task-Progress screens
and the dashboard. See the matching `flutter_app/README.md` entry for the
Flutter-side work (the shared `AcademicYearBanner` widget, the new `GET
/academic-sessions/current` endpoint it calls, and the on-device
verification) — this entry covers the backend.

Research first (not guessed): this concept, its `is_active`/`is_current`
columns, and even the "wipe every row, then set this one" pattern for
choosing the active year all already existed identically in the legacy
app (`dental_clinics2/includes/SessionHelper.php`,
`admin/manage_sessions.php`) — this work closes real gaps in what was
already a faithful port, not a new design:

- **`AcademicSession::booted()` gained a `static::saving()` hook**
  (`app/Models/AcademicSession.php`) — whenever a row is saved with
  `is_current = true`, it wipes `is_current` on every other row in the
  same request. This replaced six near-identical inline "wipe all, set
  one" blocks previously duplicated across
  `AcademicSessionController`/`Api\AcademicSessionController`'s
  `store()`/`update()`/`setCurrent()` (web and API) — those methods are
  now plain `AcademicSession::create()`/`->update()` calls. Verified via
  tinker: creating two rows with `is_current=true` back to back left only
  the second one `true`. Unlike the old controller-local blocks, this
  also protects any other write path (tinker, a seeder, a future
  feature) automatically.
- **New `GET /academic-sessions/current`** (`Api\AcademicSessionController::current()`)
  — `{id, name}` or `null`, wrapping `AcademicSessionHelper::resolve()`
  (unchanged — still the existing three-tier fallback: an explicitly
  "selected" session, then `is_current`, then the most recent `is_active`
  one by `start_date`). One small endpoint instead of Flutter re-deriving
  this five separate times.
- **`Api\GroupController::index()` real scoping gap, closed**: unlike
  `Api\DoctorController`/`Api\TaskController`, it only filtered by
  academic year when the client explicitly passed
  `academic_session_id` — no default-to-current fallback. Flutter's own
  `groups_admin_providers.dart` never sent that param either, so **the
  Flutter Groups list was silently showing every year's groups at once**.
  Fixed with the identical `AcademicSessionHelper::resolveId()` +
  `where(...)->orWhereNull(...)` pattern the other two controllers
  already use. Verified via curl: created a group explicitly stamped to a
  non-current session — absent from the default list, present with
  `?all_sessions=1`.
- **The actual "task progress" gap — the biggest one**:
  `App\Services\TaskProgressGroupSummary::build()` and
  `DoctorTaskSummary::build()` (shared by both web's
  `TaskProgressController` and the Flutter-facing
  `Api\TaskProgressController`) filtered tasks only by `stage_id`, with
  **no academic-year filter at all** — a task from any year for that
  stage showed up in the matrix, regardless of which year was active.
  Both gained an `?int $academicSessionId = null` parameter (resolved
  once by their callers via `AcademicSessionHelper::resolveId()`/
  `resolve()`, not fetched inside the service itself, matching how they
  already take every other input as a plain argument) and apply the same
  `where(...)->orWhereNull(...)` filter to their `Task` query.
  `App\Services\TaskProgressFilters::build()` (the day→group *list* one
  level up, which populates which groups even show up to pick from) had
  the identical gap — was scoped only by `ScopeHelper::
  scopeAcademicSessions()` (a *permission* check, which sessions the
  *user* may see — unrelated to which one is *active*), fixed the same
  way. Verified via curl: created a task explicitly stamped to a
  non-current session for a real group's department — absent from that
  group's `task_count`; a session-less task in the same department still
  counted (the existing "visible under every year" convention, unchanged).
- **`TaskProgressController::index()`/`DashboardController::index()`**
  (web) both gained a `currentSession` Inertia prop identical in shape to
  the one Doctors/Groups/Tasks controllers already return — Task-Progress
  and the dashboard previously had no active-year banner at all;
  `TaskProgress/Index.vue`/`Dashboard.vue` now render one.
- **UI text unified to "العام الدراسي" (singular) / "الأعوام الدراسية"
  (plural)** — web previously had three different phrasings live at once
  (`الأعوام الدراسية` in the nav/permissions screen, `الفصل الدراسي` on
  Doctors/Groups/Tasks, plain **English** on the `AcademicSessions/
  Index.vue`/`Show.vue` CRUD pages themselves — the only fully-English
  page left in the app, now fully localized to match). Model/table/
  column/route names (`AcademicSession`, `academic_sessions`,
  `academic-sessions.*`) were deliberately left unchanged — this is a
  UI-text rename, not a schema/routing one.

**Verified live**: the tinker/curl checks above for each of the three
real bugs (enforcement, Groups scoping, task-progress scoping), `php -l`
on every touched file, and `npm run build` clean. Also found and fixed
live: the real dev database had **zero** rows with `is_current=1` at all
(every session had drifted to `false` at some point, pre-dating this
work) — `resolve()`'s existing fallback silently papered over it by
picking the most-recent-`is_active`-by-`start_date` row, which is why
nothing broke, but it meant the admin list screen showed no "current"
badge on any row while every banner elsewhere confidently named one. Set
explicitly via tinker (`AcademicSession::find(43)->update(['is_current'
=> true])`) so the state is unambiguous — the same academic year the
fallback was already silently choosing.

**Follow-up, same day**: after adding an iOS-style `CupertinoSwitch`
toggle to the Flutter admin app for activating a year (see
`flutter_app/README.md`'s matching follow-up), the user asked whether the
web admin got the same treatment — it hadn't yet. `AcademicSessions/
Index.vue`'s status badge (`نشط`/`مفعّل`/`غير مفعّل`) and separate
"تعيين كنشط" text button are now a single Tailwind toggle switch per row
(a `<button>` + inner `<span>` using the standard `translate-x-1`/
`translate-x-6` pill pattern — no new package, this app already uses
Tailwind everywhere), calling the same existing `setCurrent()` →
`PUT /academic-sessions/{id}/set-current` the button used to. Disabled
(`cursor-default`, no click handler) on whichever row is already current,
matching the Flutter side's reasoning: there's no "turn off" action, only
"turn a different year on," so a currently-current row's switch has
nothing meaningful to do if clicked. Verified via curl with a real
authenticated session (cookie jar + `X-XSRF-TOKEN`, same login flow as
the day-governed-diagnosis entry above) that the page still renders
(`200`, correct `AcademicSessions/Index` component and `sessions` props
including `is_current` per row) after `npm run build` — no dedicated
browser/screenshot tool is available in this environment for a literal
pixel check, so this follows the same verification depth already
established for other web-only changes this session (successful Vite
build catches template syntax errors; curl confirms the controller/props
contract the template binds against). While re-checking this, found the
*data* had changed since the earlier Flutter round-trip test — a
different "2027" row (there are two, `id 42` and `43`, sharing that exact
name) was now the current one instead of the one left active before.
Not a bug in this work (nothing in this session's own code changed it,
and the model's enforcement — confirmed working — only guarantees
*at most one* is current, not *which* one); left as-is rather than
silently overwritten again, since it's plausible the user toggled it
themselves while trying the new Flutter switch, quite possibly the two
identically-named "2027" rows being confusable is itself worth the user's
attention independent of anything built here.

Flagged this to the user; they confirmed the duplicate (`id 43` — same
name, same `2026-08-18 → 2027-08-18` dates, `0` groups/tasks on both)
should be deleted rather than renamed. Deleted `id 43` directly (verified
first it wasn't `is_current` and had no linked groups/tasks — the same
two guard conditions `AcademicSessionController::destroy()` already
enforces), keeping `id 42` as the one surviving "2027" row.

## Fixed: staff profile photo upload never actually saved, and every storage URL was unreachable from a real device (2026-08-25)

The user reported: "when I change my profile picture, it doesn't update in
the app." Reproduced live (curl, then confirmed on the Honor tablet) and
traced to **two independent, stacked bugs** — fixing only one would have
left the symptom unchanged, which is why this took real debugging rather
than a one-line guess:

1. **`User::$fillable` was missing `profile_image`** (`app/Models/User.php`)
   — `Doctor::$fillable` already had it, `User::$fillable` never did. Both
   `ProfileController::update()` (web) and `Api\ProfileController::update()`
   already correctly detected the uploaded file, stored it to disk
   (confirmed via temporary debug logging: `Storage::disk('public')->exists()`
   returned `true`, the file was genuinely on disk with a fresh random
   name), and put the new path into `$validated['profile_image']` — but
   `$account->fill($validated)->save()` silently dropped that one key
   before writing to the database, since Eloquent's mass-assignment only
   ever sets attributes listed in `$fillable`. `$account->fresh()->
   profile_image` came back `null` immediately after `save()`, in the same
   request, with no exception thrown anywhere — the classic silent-drop
   shape of a fillable gap, why it looked like nothing had happened rather
   than an obvious error. **Doctors were never affected** — only staff
   (`User`) accounts, which is every non-doctor login (admin, editor,
   accountant, etc.).
2. **`APP_URL` in `.env` was `http://localhost/dental_laravel/public`** —
   `Storage::disk('public')->url()` (used by every `*_image_url`/`logo_url`
   field the API returns — `UserResource`, `DoctorResource`,
   `ClinicSettingController`, etc.) builds absolute URLs from this fixed
   value, not from the incoming request's own host. `localhost` only
   resolves to "this device" — from a real physical Android tablet on the
   LAN, `http://localhost/...` points at the *tablet itself*, not the dev
   PC, so the image request always failed silently and `NetworkImage`
   showed nothing (the profile screen's existing icon fallback, `child:
   Icon(Icons.person)`, only renders when `backgroundImage` is null, not
   on a *failed* image — so a broken URL and no photo look visually
   identical, no error surfaced anywhere in the UI). Fixed by pointing
   `APP_URL` at the dev machine's current LAN IP instead
   (`http://192.168.1.155/dental_laravel/public`) — the same address this
   session's every physical-device `flutter run` already needed to pass
   via `--dart-define=API_BASE_URL` (see `flutter_app/README.md`'s
   printer/PDF entries), just applied to the *backend's* own URL
   generation too. Still reachable from the dev PC itself (a LAN IP always
   resolves back to the machine that owns it), so this didn't break
   anything for browser/curl access from the same machine. Ran
   `php artisan config:clear` afterward — `.env` values that were already
   read into a cached config wouldn't have picked up the change otherwise.
   **This affected every image URL in the app, not just profile photos**
   (doctor photos, clinic/university logos) — none of them would have
   loaded on a real device before this fix; it went unnoticed until now
   only because no on-device test this session happened to exercise a
   *populated* image URL over the LAN before this bug report (clinic logo
   was unconfigured in every earlier PDF-feature test, seeded doctors have
   no photos).

Fixed by adding `'profile_image'` to `User::$fillable` and updating
`APP_URL`. No controller/Resource code needed changing — both were already
correct; the bugs were purely in the model's mass-assignment guard and the
environment config. **Verified live**: curl multipart upload to `PUT /me`
now returns a populated `profile_image`/`profile_image_url` (confirmed via
temporary debug logging showing the exact point the value was being
dropped, before removing it); on the Honor tablet, picked a real test
image (pushed via `adb push` + a media-scanner broadcast so the picker
could see it), saved, and the avatar now correctly shows the uploaded
photo and stays showing it — reproduced the original bug first (avatar
reverting to the generic icon after a successful-looking save), then
confirmed the fix on the same device/flow. Reset the test account's
`profile_image` back to `null` afterward (the red test square wasn't a
real photo worth keeping) — same test-state-cleanup convention as
elsewhere this session.

## Infectious-disease/viral-hepatitis lab screening gate before payment or starting a task (2026-08-26)

The user asked for a safety check: a newly-registered patient must not be
received/proceed until a lab step scans the patient's own ticket QR and
confirms "سليم" (clean) — no payment, and no doctor "starting a task" on
that patient, until that's recorded.

**Real architectural gap found before building this**: "بدء المهمة"
(`TaskStarter::start()`) created/reassigned a `TaskInstance` row that
**was not linked to any patient at all** — it's a (task, doctor) case-count
assignment for training requirements ("10 extractions"), completely
separate from `PatientRegistration` by explicit prior design (that
model's own docblock: "never the same concept" as the task-tracking
tables). Asked directly, the user confirmed they wanted this linked
properly rather than leaving "start task" ungated — so this feature also
threads a `patient_registration_id` through `TaskInstance` and the whole
start-task call chain, on both web and Flutter.

**Schema** — two additive migrations, no FK constraints (matching this
codebase's existing convention on `payments.patient_registration_id`):
`2026_08_25_190000_add_screening_status_to_patients_simple.php` adds
`screening_status` (`enum('pending','clear','flagged')`, default
`'pending'`), `screening_checked_by`, `screening_checked_at` to
`patients_simple`; `2026_08_25_200000_add_patient_registration_id_to_task_instances.php`
adds `patient_registration_id` (nullable — historical rows predate it) to
`task_instances`.

**One shared gate, reused everywhere** — new
`App\Services\PatientScreeningGate::ensureClear()` (throws a new
`PatientScreeningException`), mirroring why `TaskStarter` itself exists as
a separate class ("so [callers] can reuse the exact same guard rails
instead of a third divergent copy," per its own docblock). Called from:
- `TaskStarter::start()`, which now takes a required
  `PatientRegistration $patientRegistration` argument, gates on it before
  its existing transaction, and stamps `patient_registration_id` onto the
  claimed instance in the same `update()` call that already sets
  `doctor_id`/`status`. No change needed to the existing "reuse a pending
  placeholder row" pooling logic — those rows are anonymous (no doctor
  *or* patient yet) until a `start()` call claims one, so claiming one
  now also fills in the patient in that same step.
- `Api\PaymentController::store()` and web `PaymentController::store()` —
  when `patient_registration_id` is present (the reception-desk flow, not
  the unrelated appointment-based payment flow), the gate runs before
  `Payment::create()`; a refusal returns 422 (API) or
  `back()->with('error', ...)` (web), matching how every other guard in
  this codebase already surfaces.

**New endpoint**: `POST /patient-registrations/{id}/screening` (web and
API, both alongside the existing `scan()`/`status()`/`qr()` methods on the
same controllers) — `{"screening_status": "clear"|"flagged"}`, records who
confirmed it and when, gated by a new `permission:patient_screening,confirm`
module added to `App\Support\PermissionMatrix` (same precedent as the
`education_types` module already in there: not part of the legacy app,
added because the feature is new). This shows up automatically in the
existing `Permissions/Edit.vue` admin UI — that page renders whatever
`PermissionMatrix::forUi()` returns, no Vue change needed there — so an
admin can grant just this one narrow ability to whichever staff account is
the "lab person," without inventing a new account type or guard.

**No new QR type** — this reuses the exact same ticket QR
(`{"type":"patient_registration","id":N}`) already printed at registration
and already scanned for payment; the screening step is just a second
consumer of it.

**Web UI**: `TaskProgress/Index.vue`'s "بدء مهمة للطبيب" modal gained a
"امسح رمز المريض" step, reusing the page's existing `Components/QrScanner.vue`
(already used there for the unrelated `pending_task` doctor+task QR) —
the "بدء" button stays disabled until a patient with
`screening_status === 'clear'` has been scanned. The QR-scan shortcut
(`startFromScan`, previously submitting `task-progress.start` directly on
a `pending_task` scan) now routes through this same modal instead, so
that path can't bypass the patient-scan step either.

**Real bug found and fixed while testing this**: `Api\PatientRegistrationController::store()`
returned `$registration->load([...])` after `PatientRegistration::create($validated)`
— `load()` only eager-loads relations, it does not refresh scalar columns
from the database, so the freshly-created registration's `screening_status`
(a DB-level default, never passed to `create()`) came back `null` in the
API response instead of `'pending'`. Changed to `->fresh([...])`, which
re-fetches the model (and the given relations) from the database. Caught
via the E2E curl test below, not by inspection — worth noting since it's
exactly the kind of gap that's invisible in code review.

**Verified end-to-end via curl** (registration → 422 on payment before
screening → 422 on `/task-progress/start` without
`patient_registration_id` → 422 from the gate with a `pending` patient →
`confirmScreening` → 201 payment succeeds → task-progress start succeeds
→ confirmed the created `TaskInstance.patient_registration_id` matches
the scanned patient via its `patientRegistration()` relation), plus the
"flagged" (غير سليم) path independently (also blocks payment). On-device
(Flutter, Honor tablet): registered a patient, confirmed the new
"بانتظار الفحص" badge appears on the list; confirmed the new "فحص السلامة
من الأمراض المعدية" icon opens the correct scanner screen; confirmed
"بدء المهمة" in تقدم المهام now demands "امسح رمز المريض" first instead
of going straight to the notes prompt. The camera-decode step itself
reuses the pre-existing, already-proven `mobile_scanner`/`QrScanner.vue`
mechanism unchanged from the payment flow — not re-verified with a live
scan in this pass, since that requires physically presenting a printed
QR ticket to the camera. `npm run build` and `flutter analyze` both clean.
Test registrations/payments/instances created during verification were
deleted afterward.

**Follow-up, same day**: the user pointed out the web interface hadn't
actually been given a way to *confirm* screening at all — the only web
change above was the scan step gating "بدء المهمة", with no equivalent of
Flutter's dedicated screening screen for reception/lab staff. Added:
- A "الفحص" column to `PatientRegistrations/Index.vue`'s table — a colored
  status badge (green/amber/red for clear/pending/flagged) plus a
  "تحديد" button opening a modal with "سليم"/"غير سليم" buttons, posting
  to the already-existing `patient-registrations.screening` route.
  **No QR camera scan on web** — deliberately: staff already see the
  specific row on screen, so confirming directly by id is simpler than
  requiring a desktop camera for something already in front of them
  (unlike Flutter, which is used away from a screen showing the list).
- **A second real gap found while fixing the first**: `Payments/Create.vue`
  had *no flash-message display at all* — `PatientScreeningGate`'s refusal
  (`back()->with('error', ...)`) was reaching the page (confirmed
  `HandleInertiaRequests.php` already shares `flash.error` globally) but
  nothing rendered it, so a blocked payment on the web form failed
  completely silently, redirecting back with an untouched form and no
  explanation. Added the missing `v-if="page.props.flash?.error"` banner,
  the same pattern `PatientRegistrations/Index.vue` already uses for
  `flash.success`.

`npm run build` clean; `php artisan route:list --name=patient-registrations.screening`
confirms the route both pieces of UI call already existed from the
original implementation above.

## Web payment form: find the patient by QR scan or search, not a giant dropdown, plus quick-digit amount entry (2026-08-26)

`Payments/Create.vue`'s "تسجيل مريض" payment source previously loaded
**every** `PatientRegistration` row into one `<select>`
(`PaymentController::create()`'s `patientRegistrations` prop) — unusable
past a handful of rows, and the one thing this form never got when the
Flutter payment screen (scan-to-pay) was built. The user asked for it
back as scan-or-search, matching the Flutter experience.

- **New endpoint**: `PatientRegistrationController::search()` —
  `GET /patient-registrations/search?q=...`, same name/phone `like`
  columns as `index()`'s own search but capped at 10 results and
  returning bare JSON instead of an Inertia page, since this only ever
  backs a dropdown. `PaymentController::create()` no longer queries every
  registration up front at all.
- **Scan**: reuses `Components/QrScanner.vue` and the existing
  `patient-registrations.scan` endpoint verbatim — the identical
  component/round-trip already proven in `TaskProgress/Index.vue`'s
  start-task modal, not a new scanning mechanism.
- **Search**: a debounced (300ms) text field hitting the new endpoint,
  showing a click-to-select results list.
- Once a patient is found by either method, the picker is replaced by a
  confirmation chip (name + phone) with a "تغيير" button to reset and
  try again — mirrors the pattern already used for the infectious-disease
  screening's patient chip above.
- **Quick-digit amount entry**: "0"/"00"/"000" buttons that append to the
  amount field (a clerk types "5" then taps "000" for 5000), plus a
  "مسح" clear button — porting the exact UX already in
  `patient_registration_payment_screen.dart`'s Flutter payment screen,
  which this web form never had. The amount input changed from
  `type="number"` to a plain text field (`inputmode="decimal"`) since
  string-appending digits onto a native number input doesn't work
  reliably across browsers.

Verified: the underlying search query directly via `tinker` (phone-prefix
search correctly matched); `php -l` and `npm run build` both clean.

## Production deployment: GitHub Actions → cPanel, replacing the live legacy site (2026-08-27)

The project is now live in production at `cdclinics.com`, deployed
automatically from `hakamiraqi/cdc` on every push to `main`. This replaced
the original PHP `dental_clinics2` app that had been running at that
domain — its files are untouched, just no longer served (see the
Document Root note below).

**Workflow**: `.github/workflows/deploy.yml`. On push to `main`:
1. `composer install --no-dev --optimize-autoloader` and
   `npm ci && npm run build` run in the CI runner itself — the built app
   (with `vendor/` and `public/build/`) is what gets shipped, not raw
   source that the server would need to build.
2. The SSH private key (repo secret `SSH_PRIVATE_KEY`, passphrase in
   `SSH_KEY_PASSPHRASE`) is written to a temp file and its passphrase is
   stripped in-place (`ssh-keygen -p -N ""`) so the ephemeral CI job can
   use it non-interactively — never touches the real key's passphrase on
   disk anywhere else.
3. The built tree is shipped to `/home/cdclinics/dental_laravel/` on the
   server and `php artisan migrate --force` + the usual cache commands
   run over SSH.

**Why `tar czf - | ssh ... tar xzf -` instead of `rsync`**: the first
deploy attempt used `rsync -e ssh`, which failed with `rsync: command not
found` — the shared-hosting account simply doesn't have an `rsync`
binary (confirmed via `which rsync` in cPanel's Terminal). Since `rsync`
needs the binary on *both* ends regardless of `-e ssh`, there's no
client-side-only fix; switched to piping a `tar` stream over `ssh`
instead, which only needs `ssh`/`tar` (always present). Trade-off: unlike
`rsync --delete`, this never removes files that were deleted from the
repo — acceptable for this project's pace, revisit if stale files ever
become a problem.

**Why `migrate --force` failed on the very first production run, and the
one-time fix**: `2024_01_01_000000_import_clinic_schema` replays the full
61-table `clinic_system2` DDL via raw SQL (see Project layout notes
below) — that's exactly the schema the production database *already
had* (it's the same live database the legacy PHP app has been running
against), so `CREATE TABLE` failed immediately on the first table
(`appointments`) with `SQLSTATE[42S01]... already exists`. This is
expected and only needed handling once: manually recorded that one
migration as already-run without executing it —
```
php artisan tinker --execute="DB::table('migrations')->insert(['migration' => '2024_01_01_000000_import_clinic_schema', 'batch' => 1]);"
```
— then `php artisan migrate --force` ran clean for every migration after
it, since those are all genuinely new (Laravel-only) additions this
project made on top of the legacy schema, never applied to production
before. Confirmed via `migrate:status` before and after. This was a
one-time manual step for adopting an existing database; every migration
written from here on runs automatically through the normal CI pipeline
like anything else.

**Why the switch-over used a symlink instead of cPanel's Document Root
field**: cPanel's "Domains" UI (this account's theme/version) only
exposes an editable Document Root for subdomains/addon domains — the
*primary* domain's row shows "No configuration options currently exist"
when managed, with no way to repoint it from that screen. Worked around
it via SSH instead, which achieves the identical effect Apache-side:
```
cd /home/cdclinics
mv public_html public_html_old_backup
ln -s /home/cdclinics/dental_laravel/public public_html
```
The legacy app's files are fully intact in `public_html_old_backup`,
just no longer reachable over the web — trivially reversible (`rm
public_html && mv public_html_old_backup public_html`) if ever needed.
A side benefit: `public_html/phpinfo.php` (a leftover debug file from
the legacy app's own `CPANEL_DEPLOYMENT.md` checklist, guarded only by a
static `?key=` query string) is no longer web-reachable either, since
nothing points at `public_html_old_backup` anymore.

**Production `.env`** lives only on the server
(`/home/cdclinics/dental_laravel/.env`) — deliberately excluded from the
`tar` transfer (`--exclude='.env'`) so a deploy never overwrites it.
`DB_*` values point at the same `cdclinics_clinic_system` database the
legacy app used (credentials were already sitting in the legacy app's
own `config/db.php` in `public_html_old_backup` — reused as-is rather
than re-entered, since it's the same physical database).

**Verified end-to-end on production**: logged in with a disposable test
account created via `tinker` (not the real `admin` account, to avoid
touching a live credential) — dashboard renders real data (139 doctors,
36 task-progress rows) pulled from the actual `clinic_system2` database,
confirming DB connectivity, sessions, and auth all work correctly under
the new deploy. Test account removed after verification.

**Still open**: `Force HTTPS Redirect` was off for the domain in cPanel
at deploy time — worth enabling. `public_html_old_backup` is being kept
for now as a rollback safety net; safe to delete once the new deployment
has run untroubled for a few days.

## Production's real database was older than `schema_import.sql` assumed: `academic_session_id` missing on three tables (2026-08-27)

First real post-deploy bug report: the Flutter app's "الأعوام الدراسية"
(academic years) screen showed a generic server-error banner. `tail
storage/logs/laravel.log` on production named it exactly:
`SQLSTATE[42S22]: Unknown column 'groups.academic_session_id'`, thrown
from `AcademicSessionController::index()`'s `withCount(['groups',
'tasks'])`.

Root cause traces back to the deploy-day migration adoption described
above: `2024_01_01_000000_import_clinic_schema` (which recreates the
*current* `schema_import.sql`, including `academic_session_id` on
`groups`/`tasks`/`task_assignments`) was marked already-run rather than
executed, on the assumption that production's existing tables matched
that dump. They mostly did — except production's actual `clinic_system2`
database turned out to predate whichever point the legacy app added this
column to these three tables specifically. `doctors.academic_session_id`
was fine, because that one *did* get its own dedicated migration
(`2026_08_19_120000_add_academic_session_to_doctors`) that had already
run for real; `groups`/`tasks`/`task_assignments` never got one, since
the base import was assumed sufficient for them.

Fix: `2026_08_27_090000_add_academic_session_id_to_groups_tasks_task_
assignments.php`, guarded per-table with `Schema::hasColumn(...)` so it's
safe regardless of which of the three a given database is actually
missing it on (confirmed locally: local dev needed all three too, so this
gap wasn't production-only — just never surfaced there since local dev's
database has its own separate history). Verified locally via `php artisan
tinker` that `AcademicSession::withCount(['groups', 'tasks'])->get()` now
succeeds. Deployed the normal way — `git push`, the GitHub Actions
pipeline built and ran `php artisan migrate --force` on production
automatically, no manual SSH intervention needed this time (the whole
point of setting that pipeline up two sections above).

**Takeaway for adopting an existing database this way in general**: a
migration marked already-run instead of executed is only as trustworthy
as the assumption that its target database actually matches what the
migration would have created — that assumption can be wrong in specific,
narrow ways (three columns out of ~60 tables) without being wrong
everywhere, so isolated column-level errors like this one may still
surface as real production database structure is exercised by features
that weren't part of the initial end-to-end verification pass.

## Second drift bug same day, and a one-shot diagnostic instead of another reactive round-trip (2026-08-27)

Right after the fix above, creating a new academic year hit a *different*
drift bug: `SQLSTATE[HY000]: 1364 Field 'id' doesn't have a default
value` from `AcademicSession::create()`. `schema_import.sql` adds
`academic_sessions`' primary key and `AUTO_INCREMENT` via separate
`ALTER TABLE` statements (mysqldump's usual style: `CREATE TABLE` first,
then indexes, then `AUTO_INCREMENT` values, each in their own section)
— production's real table was missing the `AUTO_INCREMENT` (and,
per the error, quite possibly the primary key too), for the same reason
as the last one: it's an older table than the dump this project's schema
was built from. Fixed by
`2026_08_27_093000_fix_academic_sessions_id_auto_increment.php`, which
checks `information_schema` for both before doing anything — a no-op on
any database (including local dev) where they're already correct.

Two unrelated columns/attributes drifting in one day made the pattern
clear enough to stop treating each occurrence as a one-off: rather than
keep discovering these through real user bug reports one at a time, added
`php artisan schema:diagnose`
(`app/Console/Commands/DiagnoseSchemaDrift.php`) — parses every `CREATE
TABLE`, `ADD PRIMARY KEY`, and `MODIFY ... AUTO_INCREMENT` statement
straight out of `schema_import.sql` (the same file the "production
already matches this" assumption was based on) and diffs it against
`information_schema` on whatever database it's run against. Entirely
read-only; reports missing tables, missing columns, missing primary
keys, and missing `AUTO_INCREMENT` in one pass instead of one support
ticket at a time. Verified locally: correctly parsed all 61 tables from
the SQL file, and (after applying both fixes above) reports "No drift
found" against local dev. **Not yet run against production** — next step
is `php artisan schema:diagnose` there via cPanel Terminal, to catch any
remaining gaps before a real user does.

## Flutter gets the same case-sheet ↔ task-instance linkage the web already had (2026-08-27)

The user asked for each case row in the Flutter doctor app to get a
clinical-form ("نموذج سريري") icon, plus a QR code reachable from that
same row, requesting the whole thing "behave like dentalclinic" — the web
app's `CaseSheetController::open(TaskInstance $taskInstance)` has resolved
a task's `case_sheet_type_id` to the right one of 8 specialty sheets, and
either reopened the existing record for that instance or created a new
one pre-linked via `task_instances_id`, since the original PHP port.
Flutter's `case_sheet_forms` feature had never been wired to this at
all — its create payload never sent `task_instances_id`, so a sheet
filled from the app floated free of whatever case it was meant for.

**Extracted the resolution logic** (the `type_code` → resource map and the
"does a record already exist for this instance" lookup) out of
`CaseSheetController` into `app/Support/CaseSheetResolver.php`, so it has
one home instead of risking a second, divergent copy once an API version
needed the same logic. The web controller is now a thin caller of it;
behavior unchanged, verified via `php -l` and by reading through the
refactor line by line rather than assuming an extraction this mechanical
is risk-free.

**New `Api\CaseSheetController::open()`**
(`GET /api/v1/task-instances/{taskInstance}/case-sheet`) — Flutter's
equivalent, returning JSON (`{resource, record_id, case_sheet_type}`)
instead of a redirect. Access branching mirrors the web controller exactly
(doctor → own-instance-only; staff → `PermissionManager::can('task_progress',
'open_case_sheet')`), checked in code rather than via `permission:` route
middleware — that middleware assumes a staff `User` principal, which would
break the doctor half of the same endpoint. Verified end-to-end via curl
locally: owning doctor → 200 with the correct resource; a different
doctor → 403; staff (admin) → 200 for *any* doctor's instance; created a
real `complete_denture_records` row for an instance and confirmed
`record_id` correctly flips from `null` to that row's id on a second call.

**New `Api\PendingTaskQrController::show()`**
(`GET /api/v1/pending-tasks/{task}/qr`) — Flutter had no way to generate
the task+doctor "pending_task" QR at all before (the one a senior scans to
*start* a case that hasn't begun yet; see `Doctor\PendingTasksQrController`'s
docblock for why "pending" means something different here than
`task_instances.status`). Same payload, same `stage_id` access check as
its web counterpart. Verified via curl: 200, real PNG bytes back.

**Flutter side**: `CaseSheetFormScreen` gained an optional
`taskInstanceId`, threaded through its go_router routes as a
`task_instances_id` query param; its create payload now includes it when
present — the one missing piece causing the original disconnect. A new
`showQrDialog()` helper (`core/widgets/qr_dialog.dart`) generalizes the
existing `QrImage` widget into a reusable "show this QR in a modal"
pattern (mirroring web's `SectionedForm.vue` "رمز QR" button), used at
three places: `my_tasks_screen.dart`'s per-case row (a QR icon — the
*pending*-task QR for an unstarted case, the *instance* QR once started —
plus a "نموذج سريري" icon, instance-only, since there's nothing to link a
sheet to before a case exists), `case_sheet_form_screen.dart` (an AppBar
action, instance-only), and `task_instance_detail_screen.dart` (replacing
what used to be an always-visible inline QR image with the same on-demand
button, for consistency, plus a new "نموذج سريري" button since this screen
previously had no case-sheet entry point at all).

**Admin/senior QR lookup in Flutter's Task Progress screen turned out to
already exist** — `task_progress_screen.dart` already had a "مسح رمز مهمة"
button reusing `QrScanMode.taskInstance` (confirmed via
`Api\TaskInstanceQrController::scan()`: its ownership check only fires
`if ($doctor instanceof Doctor)`, so a staff caller already got the full
result with zero backend changes needed). It lands on
`TaskInstanceDetailScreen`, which now also shows the new "نموذج سريري"
button — so scanning a case's QR as a senior already chains straight into
opening its clinical form, with no additional admin-side code required.

## Production email now sends for real, via the cPanel mailbox (2026-08-28)

`.env` on production had `MAIL_MAILER=log` (the local-dev default) since
the very first deploy — real password-reset/notification emails were
being written to `storage/logs/laravel.log` instead of sent, invisibly to
any end user. Switched to `smtp` using the cPanel-hosted mailbox
`adminstrator@cdclinics.com` (note: spelled without the second "i" —
that's the account's real address, not a typo introduced here).

```
MAIL_MAILER=smtp
MAIL_HOST=mail.cdclinics.com
MAIL_PORT=465
MAIL_SCHEME=smtps
MAIL_USERNAME=adminstrator@cdclinics.com
MAIL_FROM_ADDRESS=adminstrator@cdclinics.com
```

**`MAIL_SCHEME=ssl` fails on Laravel 12** — Symfony Mailer (which Laravel
12 uses under the hood) renamed the old Laravel `MAIL_ENCRYPTION=ssl/tls`
values; the `smtp` transport now only accepts `smtp` (plain, negotiates
STARTTLS itself — pair with port 587) or `smtps` (implicit TLS from the
first byte — pair with port 465, which is what this account uses).
Setting `MAIL_SCHEME=ssl` throws
`Symfony\Component\Mailer\Exception\UnsupportedSchemeException` on the
very first send attempt.

**Verified**: `Mail::raw(...)` via `tinker` on production sent
successfully (no exception) once `MAIL_SCHEME=smtps` was set, confirmed
delivered by checking the mailbox directly over Webmail.

## Production schema drift, systematically fixed via a new diagnostic command (2026-08-28)

Two one-off production bugs earlier the same day (`groups`/`tasks`/
`task_assignments` missing `academic_session_id`, then `academic_sessions.id`
missing `AUTO_INCREMENT` — both because production's real database
predates `database/schema_import.sql` in specific spots, from marking
`2024_01_01_000000_import_clinic_schema` as already-run on production
instead of executing it, since its tables already existed there) made it
clear this class of drift wasn't limited to those two tables. Rather than
keep discovering the rest one real-user bug report at a time, added
`php artisan schema:diagnose`
(`app/Console/Commands/DiagnoseSchemaDrift.php`) — read-only, parses every
`CREATE TABLE`/`ADD PRIMARY KEY`/`MODIFY ... AUTO_INCREMENT` statement out
of `schema_import.sql` and diffs it against `information_schema` on
whatever database it's run against, reporting every missing table,
column, primary key, or AUTO_INCREMENT gap at once.

Run against production, it found **152 gaps**. Cross-checked each one
against actual app code (`grep` for the column/table name across `app/`)
before deciding what to fix — a "missing" column schema_import.sql
expects doesn't necessarily mean anything in this rebuild still uses it:

- **Real bugs, fixed** (migration `2026_08_28_090000_fix_production_schema_drift.php`):
  `periodontal_charts` was missing ~135 columns that
  `App\Models\PeriodontalChart`'s own `$fillable` actively uses — the
  entire Periodontal Chart case sheet was unusable on production before
  this. `user_activity_log` was missing 10 columns
  `App\Services\ActivityLogger` writes on every logged action (used via
  `App\Traits\LogsActivity` across the admin area) — activity logging was
  silently broken. `complete_denture_records.last_tooth_extracted_teeth`
  was missing, in `CompleteDentureRecord`'s `$fillable`.
- **Deliberately left alone** (confirmed via grep — nothing in `app/`
  references them, so they're inert legacy artifacts from the original
  PHP app, not bugs in this rebuild): `app_settings`/`endodontics_images`/
  `mikrotik_settings` tables; `clinic_settings.mikrotik_*`/`jwt_secret_key`
  (explicitly excluded from this rebuild from day one — see
  `ClinicSetting.php`'s own doc comment, matching the project's standing
  "no MikroTik backup feature" requirement); `doctor_tasks.academic_session_id`
  (the `doctor_tasks` table itself is referenced nowhere outside
  `ImportLegacyData.php`'s doc comment); `patients_simple.gender`
  (superseded by the `sex` enum column, nothing reads or writes `gender`).

A quirk found running the diagnostic command itself on production:
`information_schema`'s own column-name casing (`TABLE_NAME` vs
`table_name`) isn't consistent across MySQL/MariaDB versions — the
command crashed on its first production run
(`Undefined property: stdClass::$table_name`) even though it worked fine
locally, because the two servers returned different casing for the same
query. Fixed by normalizing every `information_schema` row through
`array_change_key_case(..., CASE_LOWER)` before reading it, instead of
assuming either server's casing.

**Verified**: ran clean locally both before and after (local dev's DB
already matches `schema_import.sql` exactly, so the migration is a no-op
there — every `Schema::hasColumn()` check short-circuits). On production,
the migration applied successfully (confirmed via the GitHub Actions
deploy log, no SQL errors) and a subsequent `schema:diagnose` run there
would now report zero gaps for anything the app actually uses (not
re-verified with a fresh diagnostic pass after deploy — worth doing once
to confirm, since the command is cheap and read-only).

## "نسيت كلمة المرور؟" API endpoint for the Flutter client (2026-08-28)

The web app already has password reset (`Auth\DoctorPasswordResetController`
for doctors, Breeze's own flow for staff), but there was no API
equivalent — the Flutter login screen had no self-service path for a
forgotten password at all. Added `POST /api/v1/forgot-password`
(`Api\PasswordResetController::sendResetLink()`), unified across both
account types the same way `Api\AuthController::login()` already is:
checks `users` first, then `doctors`, and always returns the same neutral
message regardless of which (or neither) matched — the same
can't-probe-registered-emails reasoning `DoctorPasswordResetController::email()`
already uses, applied consistently to the unified endpoint. Deliberately
sends-email-only, no API-side reset-by-token endpoint: completing the
reset happens via the emailed link, which opens the existing web
reset-password page — see `flutter_app/README.md` for the Flutter-side
UI this backs.

## Optional case-sheet drafts for not-yet-started task slots (2026-08-28)

The doctor's task list ("مهامي"/`Doctor/RequiredTasks.vue`) shows N
numbered slots per task; a slot only got a "نموذج سريري" (case-sheet)
button once it had actually started (a real `TaskInstance` row existed).
The user asked for that button on unstarted ("لم تبدأ بعد") slots too, so
a doctor can optionally start filling in clinical notes before formally
starting the case — matching a real flow the *original* PHP app had
(`dental_clinics2/doctor/create_task_instance_and_open.php`, confirmed by
reading the actual legacy source, which still lives on disk as a sibling
project).

That original flow worked by silently creating a real, doctor-claimed
`TaskInstance` on button-press — not reusable here: this project earlier
added a deliberate, hard requirement
(`App\Services\TaskStarter::start()` / `PatientScreeningGate::ensureClear()`)
that no task may start without first scanning the patient's ticket QR and
confirming they're clear of infectious disease. Silently creating an
instance from this button would bypass that gate entirely. Asked directly,
the user chose the safer option: a case-sheet draft that is **not** linked
to any task instance at all, doesn't count toward the task's required-case
count, and never touches the screening gate — purely optional prep work.

**New nullable `task_id` column** on all 8 case-sheet tables
(`dental_charts`, `prosthodontics_records`, `complete_denture_records`,
`surgeries`, `periodontal_charts`, `orthodontics_records`,
`prevention_records`, `oral_medicine_charts`) — no FK, matching this
project's existing convention on `task_instances_id`/`patient_registration_id`
on these same tables. Added to each of the 8 models' `$fillable` + a new
`task(): BelongsTo` relation, and each of the 16 controllers' (8 web + 8
API) validation rules.

**`App\Support\CaseSheetResolver`** gained `resourceForTask(Task $task)`
(same `type_code` → resource resolution as the existing `resourceFor(TaskInstance)`,
refactored to share one private `resourceForTypeCode()`) and
`existingDraftRecordId($resource, $doctorId, $taskId)` — finds a
doctor+task's draft via `where('doctor_id', ...)->where('task_id', ...)->whereNull('task_instances_id')`.
One doctor+task pair resolves to at most one draft at a time: once the
doctor later formally starts that task (a real instance gets created and
linked via the *existing* `task_instances_id`-keyed path), the old
draft's `task_instances_id` is no longer null, so a subsequent tap on
another still-unstarted slot of the same task starts a fresh draft rather
than reopening the now-linked one. Known, accepted simplification — not
per-slot-numbered identity, just "my scratch notes for this task type,"
consistent with "optional, at this stage" scope.

**New endpoints**, doctor-only (this button only exists on a doctor's own
unstarted rows): `CaseSheetController::openForTask(Task $task)` (web,
`GET /doctor/case-sheet/for-task/{task}`) and
`Api\CaseSheetController::openForTask()` (`GET /api/v1/tasks/{task}/case-sheet-draft`)
— same resolve-or-create-then-redirect/JSON shape as the existing
instance-keyed `open()` methods, just keyed by task+doctor instead.
Passes `task_id` (not `task_instances_id`) as the query param when
creating; the 8 create-form pages already read `task_instances_id` from
the query string to prefill the hidden field — `Specialty/SectionedForm.vue`
gained the equivalent `task_id` prop/initial-form-value alongside it, plus
an amber "مسودة اختيارية غير مرتبطة بحالة مهمة بعد" banner (parallel to
the existing sky-blue "مرتبط بحالة المهمة رقم..." one) so it's visually
obvious this save won't count toward anything yet.

**Verified end-to-end via curl** against the real running app (not just
`tinker`): `GET .../case-sheet-draft` → `record_id: null` → `POST
/dental-charts` with `task_id` (no `task_instances_id`) → `GET
.../case-sheet-draft` again → now returns the created record's id.
`php -l` on all 26 touched PHP files, `npm run build` clean.

## Supervisor case-sheet preview, paper/electronic confirmation, and QR patient-autofill (2026-08-28)

A supervisor/admin (any staff principal) can now preview a doctor's case
sheet from Task Progress without editing the doctor's own clinical
fields — except each resource's own notes/senior-signature-equivalent
field(s), which staff *can* edit and the doctor *cannot*. A doctor can
also mark a case as documented on paper (a non-exclusive tag, never
hiding the electronic form), and can autofill a case sheet's
patient-identity fields by scanning the same registration ticket QR
already used for payment/screening.

**`App\Support\CaseSheetSupervisorFields`** (new) — a `match()` registry,
same pattern as `CaseSheetResolver`/`CaseSheetPrint`, mapping each of the
8 resources to its own supervisor-editable field(s): `dental-charts`/
`surgeries`/`periodontal-charts` reuse their existing `notes`/
`senior_doctor_name`/`senior_signature`(/`approval_date`/`clinical_notes`)
columns; `prosthodontics-records`/`complete-denture-records` reuse their
existing `diagnosis_instructor_signature` + 9 `stage_{key}_{signature,date,grade}`
triples (each table's own 9 stage keys); the remaining 3
(`orthodontics-records`, `prevention-records`, `oral-medicine-charts`)
had neither, so two new nullable columns — `supervisor_notes` (text),
`supervisor_signature` (longtext) — were added to just those three
(`2026_08_28_110000_add_supervisor_fields_to_gapped_case_sheets.php`),
plus a new "Supervisor" section in each of their three
`App\Support\*Form` layout classes so the web/Flutter forms actually
render an input for them (they're real fillable columns now, but
nothing rendered a control before this).

**`EnforceCaseSheetAccess` gained two more rules**, on top of its
existing staff-view-only / doctor-owns-own-record pair: (1) a staff
write may only *change* a resource's supervisor fields — not merely
have their keys present in the payload, since `SectionedForm.vue`
always submits the whole record on every save, so a legitimate
supervisor-only edit still carries every other field's *unchanged*
value. What actually distinguishes an allowed edit from a disguised one
is comparing the route-bound model's current stored value against the
posted one field-by-field (new `boundRecord()`/`changedFields()`
helpers), not "which keys exist." (2) The literal inverse: a doctor may
never *change* those same fields, even on their own record (resubmitting
a supervisor's existing, unchanged signature is fine — only an actual
edit to it is blocked).

**A real, pre-existing security gap closed**: this middleware was wired
into `routes/web.php` only — `routes/api.php` had *no* case-sheet
enforcement at all. Any authenticated Sanctum principal (staff or
doctor) could previously read/write/delete any of the 8 case-sheet
resources via the mobile API regardless of ownership; two spot-checked
API controllers (`Api\DentalChartController`, `Api\SurgeryController`)
had no ownership/view-only check of their own either. Closed by applying
the `'case-sheet'` middleware alias to `routes/api.php`'s equivalent
route groups, mirroring `routes/web.php`. This surfaced a second real
bug in `App\Services\CaseSheetAccess::doctor()`: it checked only the web
session's `doctor` guard, which is never populated over Sanctum — a
doctor authenticates on the API purely as `$request->user()`, same as
`Api\CaseSheetController::open()` already handled. Without a fix, every
legitimate doctor API request would have been misclassified as "staff"
and limited to view-only, breaking normal mobile saves entirely. Fixed
by falling back to `request()?->user()` when the guard is empty.

**A third real bug, found live via a curl test of this exact feature
before it ever reached staging**: `EnforceCaseSheetAccess`'s resource-name
resolution (`explode('.', $routeName, 2)[0]`) assumed a bare
`{resource}.{action}` route name — true on the web, but every
`routes/api.php` route is wrapped in `Route::name('api.')->prefix('v1')`,
making the real name `api.{resource}.{action}`. The old code silently
read `'api'` as the "resource" on *every* API request, which zeroed
`CaseSheetSupervisorFields::fieldsFor('api')` (the registry's `default => []`
case) at all times — breaking both directions of the split at once: a
staff request got 403 even writing its own allowed fields (an empty
allow-list can never match a non-empty diff), and a doctor could freely
overwrite those same fields on their own record (an empty allow-list
never intersects anything). Fixed by reading the *second-to-last*
dot-segment instead of the first, which is robust to either name shape
(the action segment is always exactly one segment, regardless of prefix
depth).

**A fourth real bug**: `TaskInstance::$fillable` never listed the two new
`paper_case_sheet_confirmed_by`/`_at` columns (added in
`2026_08_28_120000_add_paper_case_sheet_confirmation_to_task_instances.php`
for the paper-confirmation feature below), so
`TaskInstanceController::confirmPaper()`'s `update()` call silently
dropped them — Eloquent drops non-fillable keys from a mass-assignment
`update()` rather than throwing, so the endpoint returned a clean 200
with nothing actually written. Caught by checking the DB directly after
a real API call rather than trusting the 200 status code.

**A fifth real bug, unrelated to this feature's own new code but found
while curl-testing it**: `Api\DentalChartController::validateChart()`
was missing `senior_signature` from its validation rules entirely (it
had `notes` and `senior_doctor_name`, but not the third field of that
same trio) — `$request->validate()` silently strips any key absent from
its rule set, so a staff save of `senior_signature` always no-op'd
before this fix, even though the column is `$fillable` and the
middleware correctly allowed the write through. The web equivalent
never had this gap, since it auto-generates its rules from
`App\Support\OperativeForm::sections()` (which does include the field)
rather than a hand-written list. `App\Http\Resources\DentalChartResource`
had the matching read-side gap — never exposed `senior_signature` at
all — fixed alongside it. All other 7 resources' API validation +
Resource output were checked against their own `CaseSheetSupervisorFields`
entries and found complete.

**`CaseSheetController::open()`** (web) and **`Api\CaseSheetController::open()`**
now both return the viewer's own `supervisor_editable_fields` (empty for
a doctor) alongside the existing `resource`/`record_id`/`case_sheet_type`
— the API response also gained a `readonly` flag (`! $principal instanceof Doctor`),
since Flutter has no server-rendered `readonly` prop the way Inertia
does. Each of the 8 web resource controllers' `form()` method gained a
matching `supervisorEditableFields` Inertia prop.

**`SectionedForm.vue`**: a new `supervisorEditableFields` prop overrides
the per-field `disabled` state (`fieldDisabled(field)`) so those fields
stay editable even under `readonly` — covering both the generic
`sections()` field loop and the separate prosthodontics/complete-denture
"Stages and evaluation" table (`stageFieldDisabled(stageKey, part)`,
since those rows aren't part of `sections()`). The Update/Save button,
previously hidden outright under `readonly`, now shows whenever
`supervisorEditableFields` is non-empty too (`canSubmit`) — a supervisor
with something to save couldn't have saved it otherwise. Also gained a
"مسح رمز المريض" button + modal (reusing `Components/QrScanner.vue` and
the existing `patient-registrations.scan` endpoint) that fills in
whichever of the current resource's mapped patient-identity fields are
still blank, via a new `PATIENT_FIELD_MAP` — per-resource because the
8 tables name these columns inconsistently (`patient_sex` vs `sex` vs
`patient_gender`; `patient_phone` vs `telephone`; `dental-charts`/
`oral-medicine-charts` even use `patient_id` as their name field).
`prevention-records` packs its patient fields into the `patient_data`
JSON group instead of real columns, so its map entries target the
grouped `patient_data__*` form keys instead.

**`PatientRegistrationResource`** gained `age`/`sex`/`address`/
`occupation` — real columns on `patients_simple` the QR-scan response
never exposed before, needed for the autofill above.

**Paper case-sheet confirmation** — new `POST /doctor/task-instances/{taskInstance}/confirm-paper`
(web, `Doctor\TaskInstanceController::confirmPaper()`) and
`POST /api/v1/task-instances/{taskInstance}/confirm-paper`
(`Api\TaskInstanceController::confirmPaper()`), doctor-and-owner-only,
setting `paper_case_sheet_confirmed_by`/`_at`. Purely an informational
tag: never blocks or hides the electronic case-sheet button next to it.
`Doctor/RequiredTasks.vue` gained a "تأكيد أنه ورقي" button (a "موثّق
ورقياً" badge once confirmed) next to each started slot's "فتح النموذج"
link. `TaskProgressGroupSummary::build()` (shared by the admin and
doctor task-progress endpoints) now includes the confirmation timestamp
in each slot card.

**Verified via curl against the local dev server** (Sanctum tokens
minted directly via `tinker`, not guessed): staff PUT of only a
supervisor field succeeds; adding any other changed field to the same
payload 403s; a doctor PUT changing a supervisor field on their own
record 403s; a doctor PUT of a normal field succeeds; a different
doctor can't even `GET` someone else's record. `confirm-paper` verified
to actually persist both columns after the `$fillable` fix.
`php artisan schema:diagnose` still reports no drift after migrating.
`php -l` on every touched PHP file, `npm run build` clean.

## Fixed: a doctor could never use the new case-sheet "مسح رمز المريض" autofill (2026-08-28)

Found live on a real device immediately after shipping the feature
above: a doctor scanning the patient QR from inside a case sheet got
"لا تملك صلاحية لهذا الإجراء" instead of the patient's info. Both
`scan()` methods this reused (`PatientRegistrationController::scan()`
web, `Api\PatientRegistrationQrController::scan()` API) are gated by
`permission:patients,view` — a staff-only concept by design
(`EnsureUserHasPermission`'s own docblock: "a Doctor principal reaching
here must be denied, not passed to `PermissionManager`, [whose]
constructor requires a User"). So no doctor session or Sanctum token
could ever have reached either endpoint; this was never a regression in
this feature, just the first time a doctor tried to hit a
`patients,view`-gated route at all.

Fixed with a **new, doctor-only endpoint** rather than loosening the
existing staff one (which stays exactly as staff-scoped as before, still
used at the payment desk): `PatientRegistrationController::scanForCaseSheet()`
(web, doctor-guard-checked in code, registered inside the existing
`auth:doctor` route group rather than the staff `role:`-gated one) and
`Api\PatientRegistrationQrController::scanForCaseSheet()` (API,
`$request->user() instanceof Doctor` checked in code, same pattern
`TaskInstanceQrController::scan()` already uses — no `permission:`
middleware at all). Both additionally enforce `PatientScreeningGate::ensureClear()`
before returning any data — the user's own explicit requirement while
reporting this bug: a patient who hasn't been lab-screened yet, or came
back flagged, must not be readable here either, the same gate already
blocking payment and task-starting. `SectionedForm.vue`'s
`onPatientDecoded()` now calls the new route name
(`patient-registrations.scan-for-case-sheet`); the Flutter equivalent is
covered in `flutter_app/README.md`.

Starting a task itself is untouched by any of this — that stays exactly
as staff/admin-only as it always was (`TaskStarter`, gated by the
`task_progress,start` permission via the pending-task QR flow); this scan
is a read-only lookup for autofilling case-sheet fields, never a way to
begin a case.

**Verified via curl against the local dev server**: a doctor scanning a
`screening_status = 'clear'` registration gets the full record back
(age/sex/address/occupation included); scanning a `pending` one gets a
422 with the exact `PatientScreeningGate` message; a staff token on the
new route gets 403; a staff token on the old `patients,view` route is
unaffected (still 200) — confirming the fix is additive, not a
loosening of the existing staff-facing route. `php -l` on every touched
file, `npm run build` clean.

## Payments: filtering, client-side screening confirmation, and quick-digit parity (2026-08-29)

Three related asks on the general "الدفعات" payments list/form
(`/records/payments`, `/payments` — the front-desk trio's own payment
flow, separate from the reception-desk ticket-QR payment screen):

**Filtering.** `Api\PaymentController::index()` and web
`PaymentController::index()` both gained `from`/`to` (a date range on
`paid_at` — the only date this table has) and `source`
(`appointment`|`registration`, via `whereNotNull` on the matching FK).
No doctor filter exists — `payments` has no direct doctor column
(`appointment_id`/`patient_registration_id` only); no paid/unpaid filter
either — a `Payment` row already *is* a paid transaction, that state
lives on `PatientRegistration`, not here. `Payments/Index.vue` gained
matching date/source inputs alongside the existing search box, all
threaded through `router.get()`/`filters` the same way search already
was. Flutter's `PaymentListScreen` gained a filter icon opening a modal
bottom sheet (date-range pickers + source dropdown); `paymentListProvider`
switched from a bare `String? search` family key to a `PaymentFilters`
record type (`records_providers.dart`) — Dart records get structural
equality for free, which is exactly what a Riverpod family key needs.

**Client-side screening confirmation.** `Payments/Create.vue` already had
a QR scanner (added 2026-08-26) but never read `screening_status` from
the resolved registration — a non-clear patient only found out via
`PatientScreeningGate`'s generic flash-error banner *after* filling in
an amount and submitting. Now both the scan path and the search path
(`PatientRegistrationController::search()` was only selecting
`id, name, phone` — added `screening_status`) show an immediate red
"لا يمكن الدفع" banner instead of the found-patient card, and the
amount/paid-by/submit section is hidden entirely for a blocked
selection. `PatientScreeningGate` still enforces this server-side
regardless — this is purely earlier, clearer feedback, not a new gate.
Flutter's `PaymentFormScreen` had no scanner at all before this (patient
linkage was a plain list-picker, and a code comment explicitly
documented "this manual-entry form doesn't gate on screening status
anyway") — added a "مسح رمز المريض" button (new `QrScanMode.paymentPatientLink`,
reusing the existing staff-gated `patient-registrations/scan` endpoint,
since this whole screen is staff-only) plus the identical blocked-banner
treatment, shared between the scan path and the existing list-picker
path via one `_applyRegistration()` helper.

**Quick-digit amount buttons.** Already present in web `Payments/Create.vue`
and the reception-desk Flutter `PatientRegistrationPaymentScreen`
(both added 2026-08-26); missing from Flutter's general `PaymentFormScreen`,
which had a plain `TextFormField`. Added the identical "0"/"00"/"000"
append buttons + "مسح" clear button for consistency across every amount
field in the app.

Verified: `php -l` on every touched PHP file, `npm run build` clean,
`flutter analyze` clean on every touched Dart file.

## Web registration ticket: full-width logo, bigger table text (2026-08-29)

Web twin of the Flutter thermal-ticket fix above (`flutter_app/README.md`'s
matching entry), by request ("نفس الإعدادات للويب" — same treatment for
the web): `resources/views/print/patient-registration-ticket.blade.php`
(the desk-reprint ticket reached from `PatientRegistrationController::print()`
via a browser print dialog — a separate rendering path from the Flutter
ESC/POS raster ticket, sharing no code with it) had the same two gaps.

Logo was capped at the shared `print/layout.blade.php` letterhead's
`height: 80px` — small and fixed regardless of the ticket's own
420px-wide box. Scoped to this view only (the same established pattern
this file's own top comment already documents — `layout.blade.php`'s
shared rules stay untouched for the doctor roster/card, which weren't
asked to change): `.letterhead img { width: 100%; max-width: 420px; height: auto; }`
inside this file's own `<style>` block, so the logo now spans the
ticket's full width, aspect-ratio preserved, without affecting any other
print view that reuses the same shared layout.

Header text (`h1`/`h2` — university/clinic/college name) was **already**
sourced live from `ClinicSetting::current()` here (`{{ $settings->university_name ?: $settings->clinic_name }}`/
`{{ $settings->college_name }}`) — no change needed; this was the one
piece of "بقية المعلومات من الإعدادات" the web side had already gotten
right before the Flutter side did.

Patient-info was already a real `<table>` here too (unlike the Flutter
tickets' stacked `Text` rows, fixed separately in the entry above) —
only its font size needed the same readability bump: 16px → 19px table
text, 15px → 16px muted caption text (this view's own scoped override,
`.reg-ticket table`/`.reg-ticket .muted` — the shared layout's default
13px table size is untouched for every other print view).

Verified: Blade syntax reviewed by direct read (no PHP logic changed,
CSS-only); not re-verified via a live print in this session (no
physical printer access) — the reception desk can confirm on next
reprint.

## Orthodontics: removed Student Name/Supervised by/Referral Date/Referred from (2026-08-29)

By request — "نفسها معلومات الطبيب" (the same as the doctor's own
info): the doctor filling this sheet already *is* the student, and
their identity is already the record's `doctor_id`, so a separate
free-text "Student Name" field only ever duplicated it; "Supervised
by"/"Referral Date"/"Referred from" were removed alongside it (the
user named all four specifically). `group_name` ("Group") stays — not
named, not touched.

Removed the four fields from `App\Support\OrthodonticsForm::sections()`
entirely, retitling what's left of that section to "Group" (a
"Student / Referral" card holding only a Group field would've read as
broken, not simplified). This is a **single-source-of-truth fix, not a
per-client one**: both `SectionedForm.vue` (web) and Flutter's
`DynamicSectionForm` render whatever `sections()` returns — Flutter
fetches it live from `GET /api/v1/case-sheet-forms/orthodontics-records`
(`Api\CaseSheetFormController::show()`, confirmed calling
`OrthodonticsForm::sections()` directly, no separate cached copy
anywhere) rather than bundling it at build time, so this change is
already live on both platforms the moment it's deployed — no Codemagic
rebuild needed, unlike every other Flutter-side entry in this file.

Per "اجعلها تلقائية" (make them automatic): `student_name` and
`referral_date` are still real, populated columns — just no longer
client-supplied. Both `OrthodonticsRecordController::prepare()` (web,
now taking a `bool $isCreate` parameter) and
`Api\OrthodonticsRecordController::store()` set them once, at creation
only (never touched on update, matching every other auto-defaulted
field this session — `Payment.paid_at`, etc.): `student_name` from
`Doctor::find($validated['doctor_id'])->name`, `referral_date` from
`now()->toDateString()`. `supervised_by`/`referred_from` have no
equivalent automatic source, so they're simply gone from both
controllers' accepted input — matching how `Payment.paid_by` was
dropped for the identical reason. The API controller's validation
rules dropped these four keys outright (rather than leaving them
accepted-but-unused) since it lists its rules explicitly instead of
generating them from `sections()` the way the web controller does.

Confirmed no print view breaks: `print/case-sheet.blade.php` (the only
Blade template referencing any of these four column names) already
prefers a separately-passed `$doctorName` over `$sheet->student_name`,
falling back to the latter only if the former is absent — either path
still resolves correctly now that `student_name` is doctor-derived
rather than manually typed.

Verified: `php -l` on both touched controllers.

## Periodontal Chart: removed "Student / Case" section, confirmed supervisor gating (2026-08-29)

Same request pattern as the Orthodontics entry above — "معلومات الطبيب
نفسها معلومات الطالب" (the doctor's info is the same as the student's)
— but this time explicitly "ازل جميع معلومات student/case" (remove
*all* Student/Case info) and, unlike Orthodontics, no "اجعلها تلقائية"
was asked for — so no auto-fill replacement this time, the four columns
(`student_name`, `student_group`, `case_start_date`, `mentor_name`)
simply stop being collected.

Removed the whole "Student / Case" section from
`App\Support\PeriodontalChartForm::sections()`. Unlike Orthodontics,
this controller pair's validation is **not** fully generated from
`sections()` — both `PeriodontalChartController::validateRecord()` (web)
and `Api\PeriodontalChartController::validateRecord()` list an explicit
`$rules` array (the API one entirely explicit, covering many columns
`sections()` doesn't even render — a much larger legacy field set),
so removing the layout entries alone wouldn't have removed them from
either controller's accepted input. Deleted the four matching rule
lines from both explicitly.

**The second half of the request — "بالنسبة لمعلومات المشرف اجعلها
فقط للمشرف او المدير او من له صلاحية" (the supervisor's info should be
for the supervisor/manager/authorized person only) — was already true**,
confirmed by re-reading `CaseSheetSupervisorFields::fieldsFor('periodontal-charts')`
directly rather than trusting memory: `senior_doctor_name`,
`approval_date`, and `clinical_notes` (the three fields under
"Treatment Plan & Approval" that actually read as *supervisor*
sign-off, as opposed to `treatment_plan`/`treatment_plan_date`, the
doctor's own plan) are already in that list, and both the web `form()`
method and Flutter's generic `fieldDisabled()` mechanism already gate
on it identically to every other resource — no code change needed
here, just verification.

**Follow-up, same day**: the `senior_signature` gap flagged above was
then requested — added `['key' => 'senior_signature', 'label' =>
'Senior Signature', 'type' => 'text', 'width' => 'half']` to the
"Treatment Plan & Approval" section, right after `approval_date`. No
controller changes needed on either side: the column was already
fillable (`PeriodontalChart::$fillable`), already exposed
(`PeriodontalChartResource`), and already validated
(`Api\PeriodontalChartController`'s explicit `'senior_signature' =>
['nullable', 'string']`) — only `Api\PeriodontalChartController` lists
its rules explicitly; the *web* controller generates unlisted fields'
rules dynamically from `sections()`, so adding the layout entry alone
was enough there too (no rule was missing to begin with, since
`senior_signature` was never explicitly listed in either controller,
just absent from the layout that feeds the web controller's dynamic
generation). Already registered in `CaseSheetSupervisorFields` from
before, so it's supervisor-only-editable from the moment it appeared —
no separate permission change needed.

Confirmed no print view breaks: same `print/case-sheet.blade.php`
already covered in the Orthodontics entry above — its
`$doctorName ?? ($sheet->student_name ?? '')` fallback continues to
resolve correctly with `student_name` now permanently null instead of
manually typed.

Verified: `php -l` on all three touched files.

## Prevention Record: removed Student Name, registered the pre-existing Signature fields as supervisor-only — plus a generic access-control fix (2026-08-29)

Same "قارنها مع dentalclinic وعالج معلومات الطالب والمشرف او المدير"
(compare against the original app and address the student/supervisor
info) request pattern as the two entries above, but Prevention's own
layout (`App\Support\PreventionForm`) turned out shaped differently from
both Orthodontics and Periodontal Chart, so it needed its own read
rather than assuming the same fix applied:

- **`patient_group`/`visit`** (also visible in the user's screenshot,
  labeled "Group"/"Visit") are genuinely patient-related fields from the
  original app — not student/doctor-redundant like Orthodontics'/
  Periodontal's similarly-named fields — confirmed by reading
  `PreventionForm::sections()` directly rather than pattern-matching on
  the prior two fixes. Left untouched.
- **`student_name`** (labeled "Student Name") *is* redundant with the
  doctor's own identity, same as the other two resources — removed from
  the "Patient Information" section. Both `PreventionRecordController`
  and `Api\PreventionRecordController` validate the whole `patient_data`
  group as one opaque `['nullable', 'string']` JSON blob (unlike
  Periodontal Chart's explicit per-column rule lists), so no controller
  change was needed — removing the layout entry alone stops it being
  collected.
- **A self-caught documentation error, corrected**: the 2026-08-28
  docblock on `App\Support\CaseSheetSupervisorFields` claimed Prevention
  "had neither" a notes field nor a senior-signature equivalent before
  `supervisor_notes`/`supervisor_signature` were added — which is wrong.
  Prevention's own "Signature" section already ports the original app's
  `senior_name`/`signature_date` pair (visible in the user's second
  screenshot as "Signature"), missed on the earlier read because both
  live as subkeys of the `patient_data` JSON blob rather than real
  top-level columns like every other resource's supervisor fields.
  Corrected the docblock and registered
  `['senior_name', 'signature_date', 'supervisor_notes',
  'supervisor_signature']` for `prevention-records` in
  `CaseSheetSupervisorFields::fieldsFor()` — both the doctor-facing
  senior sign-off *and* staff's own separate notes field are now
  supervisor-only, kept as two distinct sections (not consolidated, per
  the user's screenshots showing both) since `supervisor_notes` is
  genuine added value, not a duplicate.

**This surfaced a real, generic gap**: `EnforceCaseSheetAccess::changedFields()`
only ever diffed whole top-level request keys against the stored record,
to tell a supervisor's actual edit apart from the web form's habit of
resubmitting every field's current value on every save (see that
method's own docblock). That works for a real column, but Prevention's
`senior_name`/`signature_date` are subkeys of the `patient_data` JSON
blob (a `group`-mechanism field, see `SectionedForm.vue`) — the client
always posts the *whole* blob as one JSON string under the `patient_data`
key, so comparing the column name itself against `$supervisorFields`
could never match a bare subkey name like `senior_name`. Registering
those two fields without fixing this would have made every legitimate
supervisor edit to them 403 as if it touched the whole blob (rule 3
would even let a *doctor* freely overwrite them, since
`array_intersect` against the wrong key never matched either).

Fixed generically in `changedFields()`: when both the stored and
submitted values for a request key decode as JSON arrays, diff their
decoded entries instead and report differing *subkey* names, rather
than the outer column name. Deliberately **not** distinguishing a JSON
object from a JSON list (no `array_is_list()` check) — a first-ever edit
to a still-empty blob decodes as `'{}'` server-side but the client may
send either `'{}'` or `'[]'`, and PHP's `json_decode(..., true)` can't
tell the two apart (both come back as `[]`), so excluding lists broke
that exact first-edit case in testing before shipping. Diffing subkeys
for any JSON-decodable array is safe everywhere else too: a plain array-
cast column's numeric list indices (e.g. `tooth_data`) never coincide
with a real supervisor-field name, so the allow-list check behaves
identically either way, just at finer granularity when it happens to be
a grouped field. This benefits any future resource with a similar
grouped supervisor field, not just Prevention.

Confirmed no print-view breakage: `print/case-sheet.blade.php`'s
`$doctorName ?? ($sheet->student_name ?? '')` fallback (shared across
resources, covered in the Orthodontics/Periodontal entries above) reads
a top-level `student_name` *column* that several other resources still
have — unrelated to Prevention's `patient_data.student_name` *subkey*,
which was never a real column and isn't referenced there.

Like the Orthodontics/Periodontal fixes, this is a backend-only change —
`*Form::sections()` and `CaseSheetSupervisorFields` are both fetched
live by Flutter at runtime (`Api\CaseSheetFormController::show()`, no
caching — see the Orthodontics entry above for the full explanation), so
it takes effect on web and mobile immediately on deploy, no Codemagic
rebuild needed.

Verified: `php -l` on `PreventionForm.php`, `CaseSheetSupervisorFields.php`,
and `EnforceCaseSheetAccess.php`.

## Supervisor-only fields were fully editable on a doctor's own case-sheet page (2026-08-29)

Follow-up to the Prevention entry above, from a live Flutter screenshot:
on a doctor's own Operative/Orthodontics/Oral Medicine sheet, every field
`CaseSheetSupervisorFields` registers (`الطبيب المشرف`/`توقيع المشرف`/
`ملاحظات إضافية` on Operative, "Supervisor Notes"/"Supervisor Signature"
on Orthodontics and Oral Medicine, and by extension every other
resource's equivalent) rendered as a perfectly ordinary, fully-editable
text field — not disabled, not hidden, no visual difference from any
field the doctor is actually meant to fill in. First instinct was to
remove these from the doctor's view entirely; the user then clarified
the real requirement: **keep them visible** (so a doctor can read the
supervisor's notes/grade/signature once given), **just make them
impossible to edit** from the doctor's own page.

**Root cause**: both `SectionedForm.vue`'s and `DynamicSectionForm`'s
`fieldDisabled()` computed the lock as `readonly && !supervisorEditableFields
.includes(field.key)` — a field was only ever locked *because of*
`readonly` mode (the staff supervisor-preview screen). A doctor editing
their own record always has `readonly === false`, so this expression is
`false` for every field regardless of key, supervisor-registered or not
— there was no rule at all saying "this specific field is off-limits to
you regardless of your own read/write mode." The 403 added on the server
side (`EnforceCaseSheetAccess`'s rule 3) was already correctly rejecting
an actual save if the doctor changed one of these — but nothing on
screen suggested the field wasn't theirs to touch, which is exactly what
was reported.

**Fix**: gave the client a second, independent list to compare against —
the registry's full, *unconditional* list of supervisor fields for a
resource (as opposed to `supervisorEditableFields`, which is only ever
non-empty for the one viewer currently allowed to edit them). Added
`'supervisorFields' => CaseSheetSupervisorFields::fieldsFor($resource)`
to all 8 web controllers' `form()` responses and to
`Api\CaseSheetFormController::show()` (Flutter's one schema endpoint,
fetched by every viewer regardless of role — so no change was needed to
`Api\CaseSheetController::open()`'s per-viewer response). `fieldDisabled()`
(both `SectionedForm.vue` and `DynamicSectionForm`) now checks that list
first: a field in it is locked unless this viewer is the one who may
edit it, full stop — independent of `readonly`. Every other field keeps
the exact prior behavior. `stageFieldDisabled()` (the Prosthodontics/
Complete Denture stage-evaluation table) got the identical restructuring
for its synthesized `stage_{key}_{part}` keys.

Net effect: a doctor now sees the supervisor's notes/signature/grade —
readable the moment a supervisor fills them in — but the input is
visibly disabled, matching the read-only styling already used elsewhere
in these forms, and can never be typed into. A supervisor previewing the
same sheet is completely unaffected — their own editable subset renders
exactly as before.

Verified: `php -l` on all 9 touched PHP files, `flutter analyze` (no
issues), and `npm run build` (web assets compiled clean).

## Operative: treatment plan notes are also supervisor-only (2026-08-29)

Follow-up to the entry directly above, from another live screenshot of
the same "خطة العلاج والاعتماد" (Treatment Plan & Approval) section: the
user confirmed that its very first field, `treatment_plan_notes`
("ملاحظات خطة العلاج"), is also meant for the supervisor only — not
just `senior_doctor_name`/`senior_signature`/`notes`, which were already
registered. Added to `CaseSheetSupervisorFields::fieldsFor('dental-charts')`;
no other code change needed, since every mechanism this depends on
(`fieldDisabled()`'s canonical-list check on both clients,
`EnforceCaseSheetAccess`'s enforcement) is already fully generic from the
fix above — adding a field to this one list is enough to lock it
everywhere.

Deliberately **not** applied to `periodontal-charts`' own similarly-
named `treatment_plan` field — that one was separately confirmed (see
the Periodontal Chart entry above) to be the *doctor's* own plan, not
the supervisor's. Checked per-resource rather than assumed identical,
since the two original layouts differ here.

Verified: `php -l`.

## Surgery: "Senior doctor" auto-fills from whoever started the task (2026-08-29)

By request, from a live screenshot of Surgery's "Approval" section:
"Senior doctor يتم اختياره بصورة تلقائية لاسم المشرف او من يملك صلاحية
لبدء المهمة" (Senior doctor should be auto-selected as the name of the
supervisor/whoever has permission to start the task) — `senior_doctor_name`
is a supervisor-only field (`App\Support\CaseSheetSupervisorFields`), so
a doctor never fills it in themselves; it always arrived blank at
creation, left for a supervisor to type from scratch later.

Real, already-tracked data exists for exactly this: `task_instances.assigned_by`
records the staff `User` who actually started/assigned that task instance
(`TaskStarter::start()` and both `TaskInstanceController::store()`
methods already set it from the authenticated staff principal at start
time — confirmed by reading all three call sites, not assumed) — the
literal "whoever has permission to start the task" the request describes.
Added `resolveSeniorDoctorName()` to both `SurgeryController` (web) and
`Api\SurgeryController`, called from `store()` only (mirrors the
Orthodontics `student_name`/`referral_date` auto-fill precedent: creation-
time default, never overwritten on update): when the new record carries a
`task_instances_id`, looks up that instance's `assignedBy?->full_name`
and uses it as the default; falls back to whatever was submitted (blank,
today) if there's no linked instance or no `assigned_by` on it.

The field stays editable for a supervisor afterward (it was already
unlocked for them, and remains visible-but-locked for the doctor per the
entries above) — this only changes what a supervisor sees as the
starting value, in case the person who actually approves later differs
from whoever started the task, rather than removing their ability to
correct it.

Verified: `php -l` on both controllers.

## Task Progress now respects a Senior/HR's department-role assignments (2026-08-29)

By request ("بالنسبة للصلاحيات اضف كما في dentalclinic عند اضافة صلاحيات
للاقسام والمراحل باختيار مرحلة معينه اوقسم معين للمستخدمين" — for
permissions, add [behavior] like in dentalclinic: when granting
department/stage permissions, a specific stage or department gets
selected for the user), confirmed through several rounds of clarifying
questions down to a precise scope: the "أدوار الأقسام" (Department
Roles) assignment screen — where an admin already picks a user +
department + stage + Senior/HR role, see `DepartmentRoles/Index.vue` and
`App\Http\Controllers\DepartmentRoleAssignmentController` — already
existed and was already fully wired (CRUD, activity log, the works).
What was actually missing, confirmed via direct comparison against the
original's `ajax/get_department_tasks.php`: **holding one of these role
assignments didn't restrict anything anywhere** — a Senior/HR could see
every department's tasks on the "تقدم المهام" (Task Progress) screen
(web *and* Flutter, which share one implementation — see below) exactly
like an unrestricted admin, whereas the original scopes that Senior/HR's
task list down to only the department(s) their `department_role_assignments`
rows cover.

Confirmed the current app already has an *unrelated* but structurally
identical restriction mechanism doing exactly this kind of scoping for a
different, independent original-app feature: `App\Services\ScopeHelper`
(ported from `includes/scope_helper.php`, driven by the *separate*
`user_allowed_departments`/`user_allowed_stages` tables filled in from
the Permissions screen's "نطاق الوصول" tab) is already called by both
`TaskProgressFilters::build()` (the stage picker) and
`TaskProgressGroupSummary::build()` (the department tabs) — the exact
two places this needed to hook into, already there, already shared
between the web `TaskProgressController` and
`Api\TaskProgressController` (Flutter's twin, per its own docblock).
So rather than threading a second, parallel restriction check through
both services, `ScopeHelper::allowedDepartmentIds()`/`allowedStageIds()`
gained a fallback source: when a user has no explicit `user_allowed_*`
rows (the common case — the two mechanisms are independent in the
original, a department-role assignment never touches that table), fall
back to their **active** `App\Models\DepartmentRoleAssignment` rows'
department/stage ids instead of treating them as unrestricted. An
explicit scope assignment still wins outright if one exists — this is
additive, not a replacement.

Net effect, with **zero changes needed to either `TaskProgress*` service,
either controller, or any Vue/Flutter file** — the existing scoping calls
just now see real ids where they used to always see "unrestricted":
assigning someone Senior or HR for a department+stage via the existing
Department Roles screen immediately restricts their Task Progress view
(web and Flutter both) to just that department/stage, with no
Codemagic rebuild needed since this is a pure server-side filter over
data the Flutter client already knew how to render.

Deliberately scoped to *only* Task Progress, not the other three
original call sites the research into `hasDepartmentRole()`/
`canManageDepartment()` turned up (the Orthodontics treatment-plan
field-lock, the admin dashboard's Senior/HR view switch, and the HR
presence widget) — confirmed directly with the user this first pass is
Task Progress only; the others remain unbuilt.

Verified: `php -l` on `ScopeHelper.php`.

## Oral Medicine: removed Student Name, locked Staff signature/Date to supervisors (2026-08-29)

By request, from a live screenshot of the "Student Visits" section:
"ازل student name وبقية الحقول الموجود بالصورة خاصة بالمشرف او
المسؤول ولايمكن للطبيب او الطالب التعديل عليها" (remove Student name,
and the rest of the fields in the picture belong to the supervisor/
manager and must not be editable by the doctor or student) — read as
two things: drop `student_name` entirely (same redundant-with-the-
doctor's-identity reasoning as every other resource this session), and
register the section's remaining two fields, `staff_signature`/`date`,
as supervisor-only. The screenshot's other section ("Investigations,
Diagnosis, and Treatment Plan") was left untouched — that's the
doctor's own clinical work, not a candidate here.

`App\Support\OralMedicineForm`'s "Student Visits" section already
carried a comment anticipating this exact split ("Real columns,
distinct from 'Student Visits' staff_signature above... see
CaseSheetSupervisorFields" on the neighboring "Supervisor" section, from
2026-08-28) — it just hadn't been registered yet. No controller change
needed: `student_visits` is one opaque JSON-blob column validated as a
plain nullable string on both web and API (`OralMedicineForm::groupColumns()`),
so removing `student_name`'s layout entry alone stops it being
collected, exactly like Prevention's `student_name` removal earlier
today.

Registered `['staff_signature', 'date', 'supervisor_notes', 'supervisor_signature']`
for `oral-medicine-charts` in `CaseSheetSupervisorFields` (previously
shared `['supervisor_notes', 'supervisor_signature']` with
`orthodontics-records` — split into its own arm). Both new entries are
grouped subkeys (inside `student_visits`), so this relies on the same
generic `EnforceCaseSheetAccess::changedFields()` grouped-diffing and
`fieldDisabled()`/canonical-`supervisorFields` machinery built earlier
today for Prevention/dental-charts — no further code changes needed
anywhere for it to actually lock the fields (visible, disabled) on a
doctor's own page while staying editable for a supervisor.

Confirmed no print-view breakage: no Blade view references
`student_visits` at all.

Verified: `php -l` on both touched files.

## Orthodontics: removed the redundant Group field, locked Diagnosis/Treatment Plan to supervisors, and a real changedFields() bug fix (2026-08-29)

Three-part request from a live screenshot set: "عالج الحقول الغير مدعومة
ازل حقل group... من حقل التشخيص الى اخر حقل خاصة بالمشرفين او من
يملكون صلاحية ولايمكن للاطباء التعديل عليها" (handle the unsupported
fields, remove the Group field, and from the Diagnosis field to the
last one belong to the supervisor/authorized person and a doctor may
not edit them).

**"Group" removed.** `group_name` — a lone top-level field in its own
"Group" section — was explicitly kept during the earlier "Student Name/
Supervised by/Referral Date/Referred from" removal ("the user asked for
these four specifically, not it"), but is redundant for the same reason
and removed now in this follow-up. Web validation generated this rule
dynamically from `sections()` (no change needed); the API controller
(`Api\OrthodonticsRecordController::validateRecord()`) had it explicit,
so that one rule line was deleted there too.

**Diagnosis/Treatment plan/Stages of treatment/Appliance type & Design
locked to supervisors.** These four (`examination_data` subkeys
`diagnosis`/`treatment_plan`/`treatment_stages`/`appliance_designs`)
are exactly the four fields the *original* app's own
`hasDepartmentRole()` gates in `doctor/orthodontics.php` (editable only
by an admin or a doctor holding a department-role for the task's
department — see the Department Roles research earlier today).
Registered them in `CaseSheetSupervisorFields` at this port's simpler,
already-established any-staff granularity instead of reintroducing the
original's separate department-role mechanism at the individual-field
level — consistent with every other resource's supervisor-only fields
this session, and confirmed the right call since the user's own phrasing
mirrored that simpler pattern ("المشرفين او من يملكون صلاحية"), not a
department-specific one.

**A real second bug, found while wiring the above up**: `treatment_stages`/
`appliance_designs` are array-valued (`{index: {info, quadrants}}`
repeater rows), not scalars. `EnforceCaseSheetAccess::changedFields()`'s
grouped-subkey diff (added earlier today for Prevention) compared values
via a plain `(string)` cast — but PHP casts *any* array to the literal
string `"Array"` (with a warning), so two completely different array
values always compared equal. Left as-is, this would have meant rule 3
(a doctor may never *change* a supervisor field) silently never fired
for these two — the client-side lock would show, but a crafted request
could bypass it entirely server-side, since `changedFields()` would
never report them as changed. Fixed with a new `differs()` helper: an
array on either side is compared via `json_encode()` instead of a
string cast; every other (scalar) comparison keeps the original,
deliberate string-cast behavior unchanged.

**"عالج الحقول الغير مدعومة" (handle the unsupported fields)** — the
same screenshots showed `teeth_squares_grid` ("Number of teeth") and
`quadrant_repeater` ("Stages of treatment"/"Appliance type & Design")
still rendering as "غير مدعوم في التطبيق بعد" on Flutter. Both now have
real widgets — see the matching `flutter_app/README.md` entry for detail
— which also means a supervisor can now actually exercise the new lock
on Flutter (edit these fields there), not just view them frozen at
whatever the doctor already typed before the fields existed as
controls.

Verified: `php -l` on all four touched PHP files.

## Prevention: auto-fill Date, remove Group, and drop the duplicated Nutritional Assessment fields (2026-08-29)

By request, from three live screenshots of the Prevention Record: "ازل
التاريخ واجعله بصورة تلقائية يتم اختياره ازل المجموعة، كيس شيت
prevention ازل patient name age class لانها مكررة" (remove Date and
make it automatically selected, remove Group; Prevention case sheet:
remove patient name/age/class because they're duplicated).

**Patient Information's `date`** — removed as a manual field, now set
automatically at creation to today's date (`patient_data.date`), same
"auto, once, at create, never overwritten on update" convention as
Orthodontics' `referral_date`. Unlike that earlier case, `date` lives
inside the opaque `patient_data` JSON blob rather than a real column, so
both `PreventionRecordController::prepare()` (gained an `$isCreate`
flag, previously shared identically between `store()`/`update()`) and
`Api\PreventionRecordController::store()` (gained a small
`withDefaultDate()` helper) now decode `patient_data`, inject `date`,
and re-encode, only when creating.

**Patient Information's `patient_group`** — removed outright, no
auto-fill (no equivalent automatic source, matching how Orthodontics'
`supervised_by`/`referred_from` were simply dropped for the same
reason). Note this reverses this session's own earlier read of this
exact field ("patient_group/visit are genuinely patient-related, not
student-redundant... left untouched") — the user's current, explicit
instruction to remove it takes precedence over that earlier read;
`visit` itself is untouched, still not part of this removal.

**Nutritional Assessment's `nutritional_patient_name`/`nutritional_age`/
`nutritional_class`** — removed; each duplicated a field already
collected in Patient Information (`child_name`/`patient_age`) — the
first field's own `help` text even said as much ("the original defaults
this to the child's name when left blank"), a known redundancy flagged
but deliberately left out of scope in an earlier pass, now addressed.
`nutritional_gender`/`nutritional_group` stay — not mentioned in this
request, and structurally distinct enough (gender/group of the
*assessment* context, not simply a repeated name/age) not to assume
redundant by extension.

No print-view breakage: no Blade view references any of these five
subkeys.

Verified: `php -l` on `PreventionForm.php` and both controllers.

## Removed "Group" wherever it still remained, and locked Prosthodontics' Diagnosis/Grade to supervisors (2026-08-29)

By request, from three screenshots (Prosthodontics' "Diagnosis and
starting" section, its "Student / Case" section, and a repeat of
Prevention's Nutritional Assessment): "ازل group من كل الكيس شيت وازل
كذلك student name وgrade/mark diagnosis and starting من صلاحية المشرف
او المسؤول فقط" (remove Group from every case sheet, and also remove
Student Name; Grade/Mark and Diagnosis and starting are for the
supervisor/authorized person's permission only).

**Audited all 8 `*Form.php` layouts for every remaining "Group"/
`student_name` field** (several had already been removed earlier this
session — Orthodontics, Periodontal Chart, Prevention's top-level
`patient_group`, Oral Medicine). Found and removed the rest:

- `prosthodontics-records`: `student_name`/`group_name` ("Student /
  Case" section, confirmed via the screenshot).
- `complete-denture-records`: the identical `student_name`/`group_name`
  pair in its own "Student / Case" section — not shown in a screenshot
  this time, but removed for the same "من كل الكيس شيت" (every case
  sheet) reason, reading the original layout directly to confirm it
  really is the same redundant pair rather than assuming from the name
  alone.
- `prevention-records`: `nutritional_group` — deliberately *kept* in an
  earlier pass today ("not mentioned in this request"), now removed
  under this follow-up's explicit global scope.
- `surgeries`' `grade_group` ("Grade / Group") was **deliberately left
  alone** — confirmed with the user first, since it's one combined
  free-text column storing Grade and Group together in the original
  schema; removing it outright would have also destroyed the ability to
  record Grade, which was never asked for.

Both API controllers for Prosthodontics/Complete Denture had explicit
`student_name`/`group_name` validation rules (web generates these
dynamically from `sections()`, so only the API side needed a rule-line
deletion) — same asymmetry seen with Periodontal Chart earlier.

**`prosthodontics-records`' `diagnosis_starting`/`diagnosis_grade`**
registered supervisor-only, joining `diagnosis_instructor_signature`
(already covered via the existing `stageFields()` mechanism).
`diagnosis_date` wasn't named in the request and stays doctor-editable.
Deliberately **not** extended to `complete-denture-records`' own
"Diagnosis and starting" section — read that resource's layout directly
rather than assuming identical structure, and found it isn't:
`diagnosis_grade`/`diagnosis_date` don't exist there at all (only
`diagnosis_starting`/`diagnosis_instructor_signature`), and extending
the lock to it wasn't requested for that resource anyway.

No print-view breakage: `student_name`/`group_name` remain real columns
on both models (just no longer collected via the form), and
`print/case-sheet.blade.php`'s `student_name` fallback still resolves
correctly either way.

Verified: `php -l` on all five touched PHP files.

## Stages of treatment / Appliance type & Design: renumber rows after removal (2026-08-29)

By request: "Stage of treatment appliance type and design اجعل يعمل نفس
dentalclinic ديناميك teeth numbering" (make Stages of treatment/
Appliance type & Design work the same as dentalclinic — dynamic teeth
numbering). Researched the original's actual `orthodontics.php` JS
before touching anything, rather than guessing what "dynamic" meant.

**The FDI tooth-numbering grid itself was already correct** — the
original uses the exact same fixed quadrant grid (UR8-1/UL1-8/LL1-8/
LR8-1, permanent teeth only) for every quadrant picker in the app,
`QuadrantTeeth.vue`/`QuadrantTeethField` already match it. "Dynamic"
actually refers to the original's `addTreatmentStage()`/
`addApplianceDesign()`/`removeTreatmentStage()`/`removeApplianceDesign()`
(rows added/removed at runtime) plus, critically,
`renumberTreatmentStages()`/`renumberApplianceDesigns()`: after removing
a row, the original physically renames every remaining row's field
id/name/data-attributes to stay contiguous (1..N, no gaps) — e.g.
removing stage 2 out of 1/2/3 turns the old stage 3 into the new stage
2, not a gap.

Both `QuadrantRepeater.vue` (already had add/remove, built earlier this
project) and its new Flutter twin `QuadrantRepeaterField` (built
yesterday) had this exact gap: `removeRow()`/`_removeRow()` just deleted
the given index, leaving a hole — harmless for the stored data itself,
but every row past the hole kept displaying its *old* "Stage N" label
under its new position, unlike the original. Fixed identically in both:
`removeRow()` now filters out the removed key and reassigns the
remaining rows to fresh sequential indices (1..N) in their existing
order.

Flutter needed one more fix Vue didn't: `QuadrantRepeaterField` keeps a
`TextEditingController` per row, keyed by position (`info_$i`) — after
renumbering, a given key can now belong to a *different* row's data,
which would otherwise show stale cached text instead of that row's real
(shifted) value. Vue's `:value` binding is fully reactive so it has no
equivalent problem. Fixed by disposing all controllers and clearing the
map on removal, letting them be recreated fresh from the renumbered
data on the next build.

Verified: `flutter analyze` (no issues) and `npm run build` (web assets
compiled clean).

## Password reset: replaced the emailed link with a 5-minute one-time code (2026-08-29)

By request: "استبدل otp بدلا من الرابط واجعل لايتجاوز 5 دقائق الرابط
حاليا يحوي مجموعة من الثغرات عند ضغط الرابط يمكن تغيير الايميل ويعمل
الرابط على الرغم من مضي اكثر من يوم" (replace with OTP instead of the
link, make it not exceed 5 minutes — the link currently has several
vulnerabilities: after clicking it the email can be changed, and it
still works after more than a day).

**Investigated both claimed vulnerabilities before changing anything**,
per this project's standing "no guessing" rule:

- **"Email can be changed after clicking the link"** — confirmed real at
  the UI level (`ResetPassword.vue`/`DoctorResetPassword.vue`'s email
  field was a normal editable input, not read-only), but **not actually
  exploitable**: `NewPasswordController::store()`/`DoctorPasswordResetController::update()`
  both used `Password::reset()`, which looks the user up by *whatever
  email was submitted* and checks the token against `password_reset_tokens`
  keyed by that same email — retyping a different address just makes the
  token fail to match a different row, it can never redirect the reset to
  someone else's account. Fixed anyway as a UI-clarity improvement (the
  field is now read-only), not because it was a real hole.
- **"Link still works after more than a day"** — the 60-minute expiry
  (`config/auth.php`) *is* enforced, but only when the new password is
  actually submitted; `NewPasswordController::create()`/`DoctorPasswordResetController::reset()`
  (the page-load `GET` route) never validated anything, so an old link's
  *page* always opened regardless of age. Confirmed with the user this
  was the actual observation (the page opening, not a successful reset)
  — not a real bug, expected default Laravel behavior for this
  particular flow shape.

**The OTP replacement itself was still wanted regardless** (better fit
for the Flutter client especially — a code can be typed directly in-app,
where a link had to hand off to a browser), scoped to both account types
(staff `users` guard and `doctor` guard) on request.

Deliberately **not** reusing Laravel's `Password` facade/broker at all —
its token is a 40-character string meant for a URL, not manual entry,
and there's no supported way to make it short without replacing the
whole mechanism anyway. New, self-contained pieces instead:

- **`password_reset_otps`** (migration) — `email`, `guard` (`users`/
  `doctors`, mirrors config/auth.php's two existing broker names — both
  account types share this one table exactly like they already shared
  `password_reset_tokens`), `otp` (hashed), `expires_at`. Primary key
  `(email, guard)` — one outstanding code per address per guard.
- **`App\Services\OtpPasswordResetBroker`** — `send()` (6-digit
  `random_int`, hashed via `Hash::make`, throttled to one new code per
  60 seconds per address — same number as the old brokers' `throttle`
  setting, just enforced manually now), `verify()` (hash-checks against
  the stored code, rejects if past `expires_at`), `forget()` (deletes
  the row once the password is actually changed — codes are single-use).
- **`App\Notifications\OtpPasswordReset`** — one notification for both
  guards (the content never needed to differ by account type the way
  the old link's target route did), replacing `Illuminate\Auth\Notifications\ResetPassword`
  (staff, framework default) and the now-deleted `App\Notifications\DoctorResetPassword`.
  `App\Models\Doctor::sendPasswordResetNotification()` (the override that
  routed to that deleted class) removed too — dead code once nothing
  calls `Password::broker('doctors')` any more.

**Every "forgot password" surface rewritten to match**: `PasswordResetLinkController`/
`NewPasswordController` (staff web), `DoctorPasswordResetController`
(doctor web), `Api\PasswordResetController` (Flutter/API — gained a real
`reset()` endpoint; the old version only ever sent the link and relied
on the web page to finish the job, since a link could always be opened
in a browser — a typed code has nowhere else to go, so this needed to
become a genuine native completion step, not just a send-only mirror).
The reset-password **GET routes dropped their `{token}` parameter**
entirely (`routes/auth.php`, `routes/web.php`) — a code is typed, not
clicked into, so there's nothing to carry in the URL beyond `email` (kept
only to prefill the now-read-only field).

**Vue**: `AuthField.vue` gained a `readonly` prop (used for both reset
pages' email field). `ResetPassword.vue`/`DoctorResetPassword.vue` lost
their hidden `token` field and gained a 6-digit `otp` field plus a
"resend code" link back to the request page; `ForgotPassword.vue`/
`DoctorForgotPassword.vue` just reworded "link" to "code".

**Flutter**: `AuthRepository.sendPasswordResetLink()` renamed to
`sendPasswordResetCode()` (same endpoint, new meaning) plus a new
`resetPasswordWithOtp()` hitting the new API endpoint.
`LoginScreen._showForgotPasswordDialog()` became a real 2-step dialog
(request code → enter code + new password) instead of a single "enter
email, then go check a browser" step — the natural in-app completion the
old link-based version never had.

Updated the stock Breeze `tests/Feature/Auth/PasswordResetTest.php`
(still testing the old link/token shape) to match the new flow. Could
not get a green local run to confirm — `RefreshDatabase` fails against
this project's SQLite test config with an unrelated, pre-existing
issue (`database/schema_import.sql`'s `SET FOREIGN_KEY_CHECKS=0` isn't
valid SQLite syntax, breaking every `RefreshDatabase` test in this
environment, not just this one) — but the rewritten assertions match
the actual controller behavior field-for-field.

Verified: `php -l` on every touched/new PHP file, `flutter analyze` (no
issues), `npm run build` (web assets compiled clean). Not verified
end-to-end against a real mailbox in this session.

## OTP password-reset email wasn't sending in production — found and fixed same day (2026-08-29)

Reported immediately after the entry above went live: "عند ارسال هل
نسيت كلمة السر لايقوم بارسال اي بريد بعد تحديث التطبيق" (when
submitting "forgot password", no email is sent at all). Investigated
before guessing at a fix, since the neutral-response design of this
endpoint (see the entry above — never reveals whether an email matched
an account) meant "no email arrived" could just as easily mean "wrong/
unregistered address was tested" as "something is actually broken."

**Real bug found**: `OtpPasswordResetBroker::send()` called
`$notifiable->notify(new OtpPasswordReset($code))` directly, instead of
going through `App\Services\Notifier::send()` like every other
notification in this app (`TaskAssigned` via `TaskStarter`, etc.).
Delivery here is synchronous (neither notification implements
`ShouldQueue` — confirmed directly, not assumed), so a transport-level
hiccup (SMTP, TLS, whatever) would throw an exception straight through
`sendResetLink()`/`email()` uncaught — the whole HTTP request fails
instead of the neutral "sent" response coming back, which looks
identical to "no email arrived" from the client, and **nothing was
logged either way**, making the two real possibilities (a genuine
send failure vs. a wrong/unregistered test address) indistinguishable
after the fact.

Fixed by routing through `Notifier::send()`, which wraps the same call
in a try/catch and logs failures (`Log::warning('Notification failed', ...)`)
— matching every other notification's error-handling convention in this
app instead of being the one exception to it. This also picks up
`Notifier`'s `enable_notifications` clinic-setting gate for free, same
as every other notification; deliberately **not** also gating on the
mail-specific `enable_email` toggle the way `TaskAssigned::via()` does,
since a password-reset code is core account-recovery, not a
routine notification an admin should be able to silence.

Also added a server-side-only debug log (`Api\PasswordResetController::sendResetLink()`)
for the "address doesn't match any account" branch — never reflected in
the response (the anti-enumeration guarantee is unchanged), but now
distinguishable from an actual send failure by checking
`storage/logs/laravel.log`, which previously logged nothing for either
case.

Verified: `php -l` on both touched files. Still not verified against a
real mailbox — the underlying root cause (an uncaught exception vs. a
non-existent test address) can only be confirmed by checking the
production log the next time this is tested, which this fix now
actually populates either way.

## OTP email still silent after the logging fix — two more gaps closed (2026-08-30)

Tested live from an iPhone after the entry above shipped: the app
showed the normal success message, but `storage/logs/laravel.log`
stayed **completely empty** — no warning, no debug entry, nothing.
Ruled out step by step with the user rather than guessing: not in
spam/junk; `ClinicSetting.enable_notifications` confirmed **on** in the
admin panel (so `Notifier::send()`'s own gate wasn't silently
swallowing it, as first suspected). That left exactly one remaining
code path that could produce total silence:

**Gap #1 — the resend throttle logged nothing at all.**
`OtpPasswordResetBroker::send()`'s "already issued a code in the last
60 seconds" branch was a bare `return;` — no log line existed for it
at all, unlike the "unknown email" and `Notifier::send()`-failure
branches either side of it, which already logged something. A
same-minute repeat test (very likely, across several rounds of
"try again" during this exact debugging session) would silently no-op
here with zero trace, indistinguishable from a real delivery failure.
Added a log line to this branch so it's no longer a silent gap.

**Gap #2 — everything was logged at `debug` level.**
Realized while adding gap #1's fix: every diagnostic log added so far
today (this entry's fix, and the two from the entry above) used
`Log::debug()`. If production's `.env` sets `LOG_LEVEL` above `debug`
(common in production to cut noise — `config/logging.php`'s own
fallback is `debug`, but that's only the *default when unset*, not
proof of what this server's `.env` actually has, which isn't in the
repo to check), every one of those calls would be **silently dropped
before ever reaching the log file** — reproducing the exact "log stays
empty no matter which branch actually ran" symptom entirely on its
own, independent of the real underlying cause. `Notifier::send()`'s
own failure log already uses `Log::warning()` — matching that level
for all three new diagnostic lines instead of assuming `debug` would
be captured.

With both gaps closed, the next test is conclusive one way or another:
either a log line finally appears (revealing which of the four possible
paths actually ran), or the log stays empty and `LOG_LEVEL` itself
needs checking directly in production's `.env` — at which point the
mystery moves from "which code path" to "is anything from this app
being logged at all," a strictly narrower question.

Verified: `php -l` on both touched files.

## The actual OTP delivery bug, found and fixed: a raw DB string handed to `diffInSeconds()` (2026-08-30)

The real root cause of everything in the two entries above, tracked down
via a live production debugging session (cPanel Terminal access + two
temporary diagnostic routes, both removed once resolved) rather than
another guess:

**`OtpPasswordResetBroker::send()`'s resend-throttle check was
permanently, unconditionally active for any address that had ever
requested a code even once** — `now()->diffInSeconds($existing->created_at)`
passed the **raw database string** (e.g. `"2026-08-29 18:45:42"`)
straight to `diffInSeconds()` instead of an explicit `Carbon` instance.
Confirmed live: a `password_reset_otps` row created during the very
first round of testing yesterday was still being evaluated as "issued
within the last 60 seconds" twelve-plus hours later, on every single
request, from both `php artisan tinker` (CLI) and the real production
web server — meaning the throttle branch's `return;` (added in the
entry above, specifically to close its *logging* gap) had actually been
firing on **every** attempt since the first, silently no-op'ing before
ever reaching the code-generation/`updateOrInsert()`/`Notifier::send()`
lines. `verify()`'s `now()->greaterThan($row->expires_at)` had the
identical unsafe pattern, found by inspection once this was known to be
a real risk, not because it had separately misbehaved yet. Both fixed
by wrapping the raw string in `Carbon::parse()` before comparing.

**How this was actually tracked down**, since it's a useful record of
what didn't work and why: the two earlier entries' logging fixes turned
out to be necessary but not sufficient — `Log::warning()` calls
compiled correctly but production's `.env` has `LOG_LEVEL=error`
(discovered via `grep -E '^LOG_' .env` in cPanel Terminal), so
`warning`-level entries were silently dropped before ever reaching
`storage/logs/laravel.log`, same as the `debug()` calls before them.
With logging itself unable to help, the investigation moved to cPanel's
Terminal directly: confirmed the test address really was a registered
`Doctor` (`Doctor::where('email', ...)->first()` in `tinker`); confirmed
raw `Mail::raw()` delivers correctly (ruling out SMTP/mail config);
confirmed `Notifier::send()` called *directly* (bypassing the broker's
DB/throttle layer entirely) also delivers correctly, with the OTP email
arriving with the exact hardcoded test code — which, in hindsight, was
the first real clue: everything downstream of the throttle check worked
whenever that check was bypassed. Two temporary, unauthenticated
diagnostic routes (`/api/v1/diag-2026-08-30`, `/api/v1/diag-2026-08-30-send`,
both removed in this same fix) then confirmed the real web server sees
the identical database, the identical matched doctor, and — calling the
real `OtpPasswordResetBroker::send()` in that exact web context — the
identical no-op-with-no-exception result as `tinker`, ruling out every
CLI-vs-web environment theory (different `.env`, OPcache, config-cache
staleness, timezone mismatch) that had been the working hypothesis up
to that point. The throttle math (before/after timestamps, both
captured via the diagnostic routes) was the piece that finally exposed
the real bug: a 12-hour-plus gap being treated as under 60 seconds could
only mean the diff calculation itself was broken, not the environment
running it.

Verified: `php -l` on `OtpPasswordResetBroker.php` and `routes/api.php`
(after removing both temporary diagnostic routes). Not yet confirmed
against the real Flutter app as of this commit — the user will retest
once this deploys, and this entry should gain a dated follow-up
confirming (or, if something else remains, continuing) once that
happens, per this project's standing rule against claiming something
works before it's actually been seen to.

**Follow-up, same day**: the `Carbon::parse()` fix above turned out to
fix only half the bug — confirmed live (`grep`-ed the deployed file to
rule out a bad deploy first, then re-verified via the exact same
before/curl/after terminal sequence) that the throttle was still
permanently active after that fix shipped. The real remaining issue:
`diffInSeconds()` in the Carbon version this app uses returns a
**signed** value — negative when the compared date is in the past
relative to `now()`, which every stored `created_at` always is by the
time this check runs again on a later request. A negative number is
always `< THROTTLE_SECONDS`, so the throttle fired unconditionally
regardless of real elapsed time, independent of whether the string had
been parsed correctly. Replaced the diff entirely with
`Carbon::parse($existing->created_at)->addSeconds(self::THROTTLE_SECONDS)->isFuture()`
— an unambiguous "is the cooldown window still ahead of us" check with
no sign convention to get backwards, rather than trying to remember
which direction a diff library considers positive this version.
`verify()`'s own `now()->greaterThan(...)` needed no equivalent change
— `greaterThan()` is a plain boolean comparison, not a diff, so it
never had this half of the problem; the earlier `Carbon::parse()` wrap
was sufficient there.

Verified: `php -l`.

**Confirmed working, same day**: a real request through the actual
Flutter app produced a fresh, randomly-generated code (not a leftover
hardcoded test value) arriving by email within about a minute — the
full pipeline (throttle check → code generation → database write →
`Notifier::send()` → SMTP delivery) genuinely works end-to-end now.
Closes out this entire investigation, across three commits over one
day: the first two (`Notifier::send()` routing, then logging/log-level
fixes) were real, worthwhile improvements to this app's error handling
and observability, but the actual reported symptom — no email ever
arriving — was caused entirely by the throttle bug fixed in this
entry's two commits, which the earlier two could never have caught on
their own.

## Surgery: removed several redundant fields, and Medical History's Yes/No dropdowns became radio buttons (2026-08-30)

Three related requests from live screenshots of the Surgery case sheet:

**"Case" section — "ازل student name group/grade date start time
status staff signature"**: removed `student_name`, `grade_group`,
`surgery_date_field` ("Date"), `start_time`, `status`, and
`staff_signature`, leaving only `surgery_type` in that section. Note on
`grade_group`: the day before, the user explicitly chose to *keep* it
("اتركه كما هو حالياً") after being told it's one combined Grade+Group
column and removing it would also drop Grade tracking — this is a
direct, later instruction overriding that earlier call, not a
contradiction to resolve; complied as asked. Both web and API
controllers had explicit (not dynamically-generated) validation rules
for these fields — `status`/`duration_minutes`/`start_time` on the web
side, all of them plus `anesthesia_type` on the API side — all deleted
alongside the layout entries rather than left as orphaned-but-harmless
`nullable` rules.

**"Anesthesia type duration remove thim"**: removed `anesthesia_type`
and `duration_minutes` from the Surgical Procedure section.

**"حول القائمة المنسدلة الى جيك بوكس للسرعة والسهولة" (convert the
dropdown to a faster tap-to-select control)**: every Medical History
Yes/No field (13 generated from the `MEDICAL_HISTORY` constant, plus
`mh_hospitalization`/`mh_smoking`/`mh_allergies`/`mh_drugs`) switched
`type` from `select` (a dropdown — tap, wait for the picker, tap "Yes"/
"No") to `radio` — both options already visible inline with one tap,
matching this app's own existing convention for a mutually-exclusive
Yes/No choice (e.g. Prevention's dental-behaviour questions). Pure
layout-metadata change reusing the existing `radio` widget on both web
and Flutter — no new component needed, `options` unchanged
(`self::YN`). Neither controller's validation needed to change: the
web side's dynamic rule generator has no special case for `select` vs
`radio` (both fall through to the same `default => ['nullable', 'string']`
arm), and the API side validates every field explicitly regardless of
its layout `type`.

No print-view breakage: grepped `resources/views` for
`surgery_date_field`/`anesthesia_type`/`duration_minutes` — no matches.

Verified: `php -l` on `SurgeryForm.php` and both controllers.

## Auto-captured case-sheet signatures + a "ready to complete" hint on Task Progress (2026-08-30)

Replaced every free-typed "signature" field across all 8 case-sheet
resources with a real, server-captured signature: the client only ever
sends a sentinel (`__SIGN__`, `App\Support\CaseSheetSignatures::SENTINEL`)
by tapping "توقيع" — the actual value stamped into the column
(`"{signer's name} — {Y-m-d H:i}"`) is resolved server-side from
`$request->user()` at save time and is then **immutable**: once a
signature field has a value, `CaseSheetSignatures::applyPending()` always
re-asserts the stored value over whatever the client sends afterward,
whether a resubmit of the same form or deliberate tampering. Before this,
every one of these fields was a plain `text` input anyone with write
access to the record (including, in several cases, the doctor whose work
the signature is meant to approve) could type any name into.

**New field type, `'signature'`**, added end-to-end (web `SectionedForm.vue`,
Flutter `DynamicSectionForm`'s `_SignatureField`/`_StageSignatureField`):
renders a "توقيع" button when empty, a "سيُسجَّل التوقيع باسمك عند
الحفظ" + إلغاء pending state once tapped (nothing is sent until the form
is actually saved), or the stamped read-only text once signed — never an
editable input again. New shared PHP helper, `App\Support\CaseSheetSignatures`,
is the single source of truth for which fields on each resource are a
signature (`fieldsFor()`), applies the sentinel/immutability logic
(`applyPending()`, called from all 16 web+API store()/update() controllers),
and answers "are all of this resource's signatures filled in" (`allSigned()`/
`allSignedForInstance()`).

Exact field list, decided with the user via two clarifying questions
(which signature(s) constitute "done" for the two stage-based sheets, and
where the completion hint should surface):

- `dental-charts`, `surgeries`, `periodontal-charts`: `senior_signature`.
- `orthodontics-records`: `supervisor_signature`.
- `prevention-records`: `senior_name` (a subkey of the `patient_data`
  JSON blob — this resource has no separate `senior_signature` column,
  so `senior_name` itself plays that role) + `supervisor_signature`.
- `oral-medicine-charts`: `staff_signature` (a subkey of the
  `student_visits` JSON blob) + `supervisor_signature`.
- `prosthodontics-records`/`complete-denture-records`: **all 10** —
  `diagnosis_instructor_signature` plus every `stage_{name}_signature`
  (9 stages each, the 9th named `rpd` for prosthodontics vs `cd` for
  complete denture) — the user's own framing: "all signatures complete"
  is what should surface the completion hint, not any single stage.
  These 9 aren't part of `sections()` at all (they're the separate
  "Stages and evaluation" table, `stages()`), so `CaseSheetSignatures`
  handles them as flat field specs alongside `diagnosis_instructor_signature`
  rather than through the grouped-subkey path.

A grouped signature (`senior_name`, `staff_signature`) needed its own
code path (`CaseSheetSignatures::applyGrouped()`): the client always
posts a grouped column's *whole* JSON blob as one string (same fact
`EnforceCaseSheetAccess::changedFields()`'s doc comment already
establishes), so the sentinel/immutability check has to decode the blob,
patch just that one subkey, and re-encode — not treat the column itself
as the signature value.

**Completion stays a separate, explicit action** — signing off does
**not** auto-complete anything. Per the user's own framing ("عند اكمال
التواقيع يظهر هل تؤشرها انه قد اكتملت" — once every signature is done,
*ask* whether to mark it complete), `TaskProgressGroupSummary::buildDoctorRow()`
now computes `CaseSheetSignatures::allSignedForInstance()` per assigned
task instance (resolving the resource once per task via the already
-eager-loaded `caseSheetType`, not per instance, to avoid an N+1) and
exposes it as `all_signed` — surfaced only on the Task Progress screen
(chosen over the case-sheet page or the resource's own list, both offered
as options) as a "✓ كل التواقيع جاهزة" badge plus a highlighted "تأشير
كمكتملة" button. The existing `TaskInstanceGrader::complete()` action is
completely unchanged; this is purely a visibility hint on top of it.
Since `TaskProgressGroupSummary` already backs both the web page and
`Api\TaskProgressController::group()`, the Flutter task-progress-admin
screen got the same `all_signed` field in its JSON with no separate API
work needed — its own matching badge (same day, after a live screenshot
showed the gap) is documented in `flutter_app/README.md`.

Verified: `php -l` on `CaseSheetSignatures.php`, `CaseSheetResolver.php`,
all 8 `*Form.php` layouts, all 16 touched controllers, and
`TaskProgressGroupSummary.php`; `flutter analyze` on `case_sheet_field.dart`
and `dynamic_section_form.dart` (no issues); `npm run build` (succeeded).

## A stage can't be signed off until its own Grade and Date are filled in (2026-08-30)

Same-day follow-up, from a live screenshot of Prosthodontics' "Stages and
evaluation" table: "يجب ان يملئ حقل الدرجة والتاريخ حتى يوقع" (Grade and
Date must be filled before signing). Scoped to exactly the 9 per-stage
`stage_{name}_signature` fields (Prosthodontics/Complete Denture) — not
`diagnosis_instructor_signature`, which has no such requirement asked of
it and, on `complete-denture-records`, no `diagnosis_date`/`diagnosis_grade`
fields to require in the first place; not the other resources' single
`senior_signature`/`supervisor_signature` either, since none of those
were shown or named.

**Enforced twice, same pattern as everywhere else in this app that has a
client-side convenience check**: `CaseSheetSignatures::stageSpecs()` now
tags each stage's signature spec with `'requires' => ["stage_{name}_date",
"stage_{name}_grade"]`; `applyFlat()`'s sentinel branch only stamps a
signature once every `requires` key already has a value (in the request
or on the existing record) via the new `requirementsMet()` — a direct API
call sending the sentinel without a grade/date gets silently dropped,
same as any other tampering attempt. Client-side, `SectionedForm.vue`
gets a `stageReadyToSign(stageKey)` helper disabling the "توقيع" button
(with a "أكمل الدرجة والتاريخ أولاً" hint) until both are filled in the
live form state.

Verified: `php -l` on `CaseSheetSignatures.php`. `npm run build`
(succeeded). Flutter's matching fix is in `flutter_app/README.md`.

## Flutter permissions admin: access-scope restriction (2026-08-30)

Closes the gap this README's own "Phase 3 admin: permissions" entry
(2026-08-21) left open by explicit design: `Api\UserPermissionController`
now exposes `App\Services\ScopeHelper`'s four-dimension access-scope
restriction (departments/stages/education types/academic sessions) to
the Flutter client — the same feature the web `Permissions/Edit` page
has had since the "Academic-session scope added to permissions"
(2026-08-21) entry wired `ScopeHelper` up in the first place.

`show()` gained `scope_options` (the four option lists, same shape as
the web page's `scopeOptions` prop) and `scope` (the account's current
selection per dimension — `null` means unrestricted, `ScopeHelper`'s own
"zero rows" convention, not "nothing selected"); `update()` gained a
`scope` field validated the same nullable-vs-array way as the web
controller (`scope.departments`, `.stages`, `.education_types`,
`.academic_sessions`, each `nullable|array` with `exists:` on every id),
then calls the same four `ScopeHelper::setAllowed*()` methods the web
controller calls. No new backend logic — this is the API controller
catching up to a capability `ScopeHelper` and the web controller already
had.

See `flutter_app/README.md`'s matching entry ("Permissions admin:
access-scope restriction", 2026-08-30) for the Flutter-side build (four
new `_ScopeDimensionTile`s on the permission edit screen) and its live
verification — this session started XAMPP's Apache + MySQL itself
(neither was running), ran `flutter run -d chrome`, and confirmed the
restrict/clear round-trip against the real `user_allowed_departments`
table via `tinker`, not just the refetched UI state.

## Flutter case-sheet printing: two small JSON-parity gaps closed (2026-08-30)

`Api\CaseSheetPrintController::show()` — the JSON mirror of the web's
printable case sheets — already existed, but had drifted from what
`CaseSheetPrintController` (web)'s Blade printout has always included:
the odontogram block and the identification-strip's `student_name`/
`grade_group` fallbacks. Neither had ever been needed by a JSON consumer
until the Flutter client actually started rendering a full print
document (see `flutter_app/README.md`'s matching "Case-sheet printing"
entry). Closed by adding one `CaseSheetPrintRenderer::dentalChart()`
call (already used by the web controller) and the same
`$sheet->student_name`/`$sheet->grade_group` fallbacks the Blade view
reads directly — no new rendering logic, just two fields the endpoint
had simply never returned.

## Case-sheet printing: a real odontogram instead of a text table (2026-08-31)

By request: the printed dental chart should match `dental_clinics2`'s
own print pages, which draw an actual per-tooth SVG odontogram
(`operative_print_html.php`'s `renderToothSvg()` — a "flower" of five
polygon surface zones per tooth, coloured by status, with red-X/orange-
ring/black-ring overlays for extracted/retained_root/crown), not the
text table (`"Tooth 11: Present — Top: Cavity"`) this print view had
instead. The web app already has this exact geometry ported once
already, for the on-screen editor — `Components/ToothOdontogram.vue`'s
`SURFACE_POINTS`, itself read directly out of the original's own SVG —
so this reuses that geometry rather than re-deriving it.

- **`App\Support\CaseSheetPrintRenderer`** gained public
  `SURFACE_POINTS`/`SURFACE_COLORS`/`ROOT_COLORS`/`TOOTH_LEVEL_FILL`/
  `TOOTH_LEVEL_OPACITY`/`UPPER_ARCH`/`LOWER_ARCH` constants — the same
  values `ToothOdontogram.vue` and the Flutter app's
  `odontogram_vocabulary.dart` already carry, now available to PHP too.
- **`dentalChart()` changed shape**: it used to pre-flatten each tooth
  into a formatted label string (`'status' => 'Present'`, `'surfaces' =>
  'Top: Cavity, Center: Filling'`) for the old text table. A real
  graphical renderer needs the *raw* `tooth_status`/`polygons` values to
  feed the same surface→colour lookup the on-screen editor uses, so it
  now returns those instead. This is a breaking shape change to the
  `dental_chart` field both print surfaces consume (the Blade view here,
  and the Flutter PDF — see `flutter_app/README.md`'s matching entry) —
  both were updated in the same pass, so nothing was left reading the old
  shape.
- **`resources/views/print/case-sheet.blade.php`**: the odontogram block
  is now inline SVG generated per tooth from a `@php` closure (Blade has
  no component system worth building for something this small and
  print-page-specific), drawing the full 32-tooth arch — every tooth, not
  just the marked ones, matching what the on-screen chart and the
  original both show — with a compact notes table underneath for any
  tooth that actually has one. Also fixed the section's title, which
  printed "المخطط السني" (Arabic) even though this printout is English
  throughout, matching the original's own English print pages — now
  "Dental Chart".

Verified via `tinker`, rendering the Blade view directly against a real
`dental_charts` record (7 marked teeth, including one `non_vital` and one
`missing` tooth): confirmed 32 tooth SVGs in the output, the `non_vital`
tooth's dark-red tooth-level fill, and the `missing` tooth's reduced
opacity, all at the correct positions in the rendered HTML — not run
through an actual browser, by request (this session's emulator/browser
verification was skipped for this pass). `php -l` clean.

## Case-sheet printing: circled-tooth graphic for the other 3 marked sheets (2026-08-31)

Asked directly whether the odontogram work above covered all 8 printable
sheets — it didn't; only `dental-charts` has a full per-surface chart in
the original. Checked the original's other seven print pages directly:
three more (`surgery_print_html.php`, `complete_denture_print_html.php`,
`prosthodontics_print_html.php`) draw a simpler graphic for a handful of
their `teeth`-type fields — a plain circle around each selected tooth's
number — which this rebuild was still printing as a comma list. The
remaining four sheets print exactly like their own originals already do
(periodontal's measurement table, or plain text with no graphic at all
for orthodontics/prevention/oral-medicine) — confirmed by reading each
print page, not assumed.

- **`App\Support\CaseSheetPrint::SHEETS`** gained an optional
  `toothMarkerCharts` config entry per sheet — which field(s) get the
  circled-graphic treatment, and (for complete-denture's `teeth_to_extract`)
  a fallback field, matching the original's own `$teethToExtract =
  $lastToothExtractedTeeth` fallback when the primary field is empty.
  `prosthodontics-records` gets two (`missing_teeth`/`caries_teeth`),
  `surgeries` and `complete-denture-records` one each.
- **A real cross-format data problem, found before it shipped**: this
  app's own tooth-picker (`QuadrantTeeth.vue`) stores codes like `UR8`,
  but a live query against the real `surgeries` table showed its 16 real
  rows — imported from the original database, predating that picker —
  hold `selected_teeth` in the *original* surgery page's own bespoke
  `U1`–`U16`/`L1`–`L16` scheme instead (e.g. `"U1,U9,L1,L9"`). Matching
  those directly against the canonical `UR/UL/LR/LL` form would have
  silently rendered every legacy-imported surgery sheet's chart
  completely blank. `CaseSheetPrintRenderer::normalizeToothCode()` now
  accepts all three formats actually in play (this app's own quadrant
  codes, surgery's legacy `U`/`L` scheme, and a raw FDI two-digit tooth
  number — the original's `complete_denture_print_html.php` accepts that
  third form too, via its own `convertQuadrantCodesToToothNumbers()`) and
  normalizes every one to the same canonical form before either print
  surface ever sees it.
- `sections()` gained an `$excludeKeys` parameter so a field promoted to
  its own graphical chart doesn't also print as a plain-text cell in its
  normal section — both controllers pass the configured field (and
  fallback field) keys through.

Verified against real data end-to-end, not synthetic: `tinker` against
the real `surgeries` row #109 (the legacy `"U1,U9,L1,L9"` one) confirmed
`normalizeToothCode()` correctly resolves it to `UR1`/`UL1`/`LR1`/`LL1`
(all four central incisors — anatomically correct, since U1/L1 sit at the
midline next to U9/L9 in the original's own numbering); rendering the
full Blade view for that same record confirmed exactly 4 circled markers
in the output and that `selected_teeth` no longer also prints as plain
text in its section. Also confirmed via `curl` against the live API that
`tooth_marker_charts` appears correctly and the field is excluded from
`sections`. `php -l` clean.

## Project layout notes

- `database/schema_import.sql` — structure-only DDL extracted from the
  source `clinic_system2.sql` dump (all `INSERT` data stripped). The
  migration `2024_01_01_000000_import_clinic_schema.php` replays it via
  `DB::unprepared`, so the DB structure is byte-for-byte the same as the
  original app's — treat this file as a source asset, not something to
  hand-edit.
- Models in `app/Models/` mostly map 1:1 to existing tables and use
  `public $timestamps = false` where the source schema lacks a matching
  `updated_at` column.
- Web controllers live in `app/Http/Controllers/`; API controllers in
  `app/Http/Controllers/Api/`; API response shaping in
  `app/Http/Resources/`. These are deliberately separate from the Inertia
  web controllers (different response format, different validation
  granularity for PATCH-style partial updates), not code-shared.

## Explicitly out of scope (by request)

- **MikroTik backup integration** — the original PHP app's router-based
  off-site backup feature. Not being ported.

## Not yet built

- **Camera QR scanning UI** — the generate/scan/resolve API loop is built
  (see "QR check-in" above); no browser-camera scanner page (the original's
  `qr_scanner.html`) — that's expected to live in the Flutter client instead.
- `doctor_tasks`, `task_assignments`, `task_progress`, `doctor_task_progress`
  — imported for schema fidelity, no models/controllers (see "task system"
  above for why).
- `tooth_conditions` / `tooth_treatments` — have models (`ToothCondition`,
  `ToothTreatment`) and relations off `DentalChart`, but no dedicated
  controllers or routes; `dental_charts.tooth_data` (JSON) is the confirmed
  real write path (see "Dental Chart module" above), so these two are schema
  fidelity + read-via-relation only for now.

Each of these follows the same pattern established so far: Eloquent model →
web controller + Inertia Vue pages → matching API controller + Resource +
routes in `routes/api.php`.
