# Case sheets & clinical charting

A **case sheet** is the clinical record a doctor fills out for one patient
visit — one form per dental specialty (Operative, Periodontal, Surgery,
Prosthodontics, Complete Denture, Orthodontics, Prevention, Oral Medicine,
plus a newer Advanced Periodontal Chart and several satellite tables). Every
task a doctor works has a `case_sheet_type_id`, and opening that task opens
the matching sheet. The whole subsystem is mirrored across two clients — the
Laravel/Inertia/Vue web app (doctor + admin/supervisor) and the Flutter
mobile app (doctor + supervisor) — talking to the same Laravel backend and
MySQL schema, most of it imported from a legacy PHP app ("the original")
whose behavior this project deliberately reproduces field-for-field before
improving on it.

## Architecture: one generic engine, not twelve bespoke forms

With `periodontal_charts` alone at 163 fields, hand-building a dedicated
screen per specialty on both platforms wasn't a good use of time. Instead:

- **Web**: `resources/js/Pages/Specialty/{Index,Form}.vue` (legacy generic
  CRUD) and, for the fully "tailored" sheets, `SectionedForm.vue` render any
  sheet from a `sections()` array (`{key, label, type, options, group,
  required}`) that each sheet's `App\Support\*Form` class supplies, plus
  optional `stages` (a stage-evaluation table) and `chartGroups`/`chartField`
  (per-tooth charts). Adding a field to a sheet's `sections()` makes it
  appear everywhere automatically — on screen, in validation, and on print.
- **API**: `GET /api/v1/case-sheet-forms` and `GET
  /api/v1/case-sheet-forms/{resource}` (`App\Http\Controllers\Api\
  CaseSheetFormController`) serialize the same `sections()`/`stages`/
  `chartGroups` output as JSON — this is layout only; record values come
  from each resource's own REST endpoint.
- **Flutter**: one `DynamicSectionForm` widget
  (`flutter_app/lib/features/case_sheet_forms/presentation/
  dynamic_section_form.dart`) renders any of the 8+ sheets from that same
  schema, with a field-type switch mirroring `SectionedForm.vue`'s. New
  field types (`teeth_squares_grid`, `quadrant_repeater`, `signature`, etc.)
  get added once in this switch, not once per sheet.

A route-name collision worth knowing about: `Route::resource()` (web) and
`Route::apiResource()` (API) default to identical route names for the same
resource string, so registering both silently made the API's routes win
every named-route lookup app-wide — fixed by giving API routes distinct
names, but worth remembering before adding a 13th resource by hand.

## Opening a case sheet, task linkage, and drafts

Case sheets are never a standalone list in the original app — a task's
`case_sheet_type_id` determines which sheet opens for it, and the sheet then
loads/saves the record tied to that specific task instance. This is
implemented in `App\Http\Controllers\CaseSheetController` (web) and its API
counterpart:

- Maps each `type_code` to its sheet, including the original's own quirk
  that both `partial_denture` and `prosthodontics` route to the same
  Prosthodontics sheet, and falls back to Operative for an unknown type.
- Reuses the sheet already filled for that task instance if one exists,
  otherwise opens a blank one pre-linked to it via `task_instances_id`.
- Access matches the original: a doctor may only open their own instance
  (403 otherwise); staff need `task_progress.open_case_sheet`.

**Flutter parity (2026-08-27 onward)**: Flutter's case-sheet browsing used
to be a free-standing "browse my records" flow with no link back to a task
at all. `CaseSheetFormScreen` gained a `taskInstanceId` carried as a
`task_instances_id` query param on its go_router routes, wired from new
"نموذج سريري" buttons on `my_tasks_screen.dart`, `task_instance_detail_
screen.dart`, and the admin `task_progress_screen.dart`. A shared
`showQrDialog()` (`core/widgets/qr_dialog.dart`) replaced three near-
identical QR dialogs; an unstarted slot's QR is the *pending-task* QR (task
+ doctor, identical across every unclaimed slot), switching to the real
per-instance QR once started.

**Optional drafts for not-yet-started slots (2026-08-28)**: the original PHP
app's "start a sheet before starting the task" flow silently created a real
task instance — which would bypass this project's infectious-disease
screening gate. Instead, an unstarted slot's "نموذج سريري" button calls `GET
/api/v1/tasks/{task}/case-sheet-draft`, navigating with `?task_id=` rather
than `?task_instances_id=`. `CaseSheetFormScreen` gained a `taskId` param
mutually exclusive with `taskInstanceId`; a task_id-linked draft has no QR
action, since there's no task-instance QR to show yet.

**Case-sheet create's real blocker was `patient_id`, not a missing Patients
CRUD screen.** An earlier plan assumed the API needed a full Patients admin
module before Flutter could create records — re-checked against the actual
`validateRecord()` methods and found otherwise:

- 6 of 8 resources store patient identity as a plain string field, already
  normal and editable — no gap.
- `surgeries` and `periodontal-charts` store `patient_id` as a real
  `patients.id` int FK while their layout only asks for a `patient_name` (+
  phone). The web controllers already resolved this via a private
  `resolvePatientId()` (find-or-create by name+phone); the **API**
  controllers had none, so no API client could ever pass `store()`
  validation. Fixed by porting `resolvePatientId()` into
  `Api\SurgeryController` and `Api\PeriodontalChartController`, and relaxing
  `patient_id` from `required` to `nullable` integer.
- `periodontal-charts` separately hard-requires `chart_data` with no
  `sections()` entry — a genuinely unbuilt widget at the time, unrelated to
  `patient_id`.

**Gotcha — `dental_charts.visit_date` defaults to `current_timestamp()` at
the MySQL level** (found 2026-08-20, left unfixed by design). A `POST` with
no `visit_date` returns `"visit_date": null` immediately, but a subsequent
`GET` of the same row shows a real timestamp matching `created_at`. Root
cause is a MySQL-level `DEFAULT current_timestamp()` inherited verbatim from
the legacy schema import (`database/schema_import.sql`), not application
code — `treatment_plan_date` on the same table (no such column default)
behaves correctly, confirming it's a column-definition issue. `payments.
paid_at` was later found to carry the identical pattern. Not fixed —
altering a production column default is a schema-level decision left for a
future pass; other `datetime`/`timestamp` columns from the same import
should be treated as suspect until individually verified.

## The odontogram (tooth chart)

`dental_charts.tooth_data` is the real per-surface odontogram behind the
Operative sheet. It was initially missing entirely — the app only had
`QuadrantTeeth.vue`, a much simpler chip-picker for comma-list fields like
`non_vital_teeth`/`missing_teeth`/`crown_bridge_teeth`. The real odontogram
was rebuilt as `resources/js/Components/ToothOdontogram.vue`, reading the
original's own `operative.php` styles and JS (`updateToothVisualStatus()`,
`surfaceStatusOptions`, `rootStatusOptions`) directly rather than guessing:

- 32 teeth, each with 5 clickable surfaces in a "flower" target layout, or 3
  root surfaces once marked non-vital.
- 6 tooth-level statuses (present, non_vital, missing, extracted,
  retained_root, crown), 5 surface statuses, 4 root statuses — same colors
  as the original CSS (e.g. `.cavity{fill:#ffc107}`, `.root-canal{fill:
  #dc3545}`).
- Data shape: `{number, position, notes, status, toothStatus, polygons}`,
  sparse (only touched teeth stored).

**Gotcha — double-encoding.** `DentalChart::tooth_data` carries a real
Eloquent `'array'` cast (unlike the periodontal sheet's plain-text
`chart_data`). The first version manually `JSON.stringify()`'d the value
before posting, matching the periodontal pattern — which is exactly wrong
for a cast column, since Eloquent re-encodes whatever's assigned. Caught by
an actual round-trip test, fixed by posting the plain array and letting the
cast handle encoding. The same bug class recurred later on Oral Medicine's
JSON-blob columns (which have *no* cast, so they needed the opposite
treatment — manual encode/decode) and was avoided proactively on the
Advanced Periodontal Chart and Endodontics widgets by checking each
column's cast before writing serialization code.

**Editing modal.** The original's edit modal shows a live 140×140 SVG of
the tooth being edited, clickable per-surface — added to
`ToothOdontogram.vue`'s modal alongside the text/button surface list that
initially shipped alone.

**Mobile horizontal scroll bug**, hit twice on two different components:
`overflow-x-auto` alone doesn't force a flex row to overflow — without an
explicit width, the browser shrinks the row's children to fit instead. Fixed
by adding `w-max` on the row and `shrink-0` on every child button, plus
`-webkit-overflow-scrolling: touch` for iOS momentum. First fixed on
`ToothOdontogram.vue`, then found again (different root component, same
missing `overflow-x-auto` entirely) on the older `QuadrantTeeth.vue`, shared
by six sheets' `type: 'teeth'` fields.

**Real FDI quadrant tooth picker on Flutter (2026-08-29).** Every `type:
'teeth'` field had rendered as a plain comma-list text box on mobile. New
`QuadrantTeethField` (`case_sheet_forms/presentation/
quadrant_teeth_field.dart`) ports `QuadrantTeeth.vue` directly: same
quadrant order (UR 8→1, UL 1→8, LR 8→1, LL 1→8), same comma-separated
storage string (not JSON, so records stay cross-compatible with the PHP
app), wrapped in a horizontal scroll view. `readOnly` disables only each
button's `onTap`, not the whole widget via `IgnorePointer` — deliberately
avoiding a bug fixed one entry earlier (below).

**Gotcha — `IgnorePointer` also blocks scrolling.** The supervisor readonly
preview of the Operative sheet showed the odontogram's arch rows cropped
with no way to scroll. `IgnorePointer(ignoring: readonly)` removes the
*entire* subtree from hit testing, including any nested
`SingleChildScrollView`. Fixed by giving `ToothOdontogramField` and
`EndodonticsField` their own `readOnly` param that disables only the actual
edit affordances (tap handlers, `TextFormField.enabled`, chip/checkbox
`onSelected`/`onChanged`), leaving scroll views interactive. Web's Vue
equivalent never had this problem, since disabling individual `<button>`
elements doesn't block a parent's native scroll.

## Clinical specialty record types

Twelve tables were ported with full model/API/web CRUD:
`complete_denture_records`, `oral_medicine_charts`, `orthodontics_records`,
`periodontal_charts`, `prevention_records`, `prosthodontics_records`,
`surgeries` (+ children `surgery_follow_ups`/`surgery_images`/
`surgery_medications`), `treatment_plans`, `treatment_materials`. Each of
the 8 primary sheets was then rebuilt field-for-field to match the original
(replacing an earlier generic auto-labeled form), driven by an
`App\Support\*Form` class:

- **Periodontal chart** — 11 sections read from `periodontal_chart.php`
  (5,174 lines), with conditional display (Women Only section only for
  female gender, pregnancy-weeks only when pregnant). Its per-tooth chart —
  `resources/js/Components/PerioChart.vue` — is 32 teeth × 6 sites (3
  buccal + 3 palatal/lingual) across 3 chart groups (initial, post-hygiene,
  follow-up), with the JSON shape matching the original's
  `collectChartData()` output key-for-key. `patient_id` is an int FK behind
  a name-only field — resolved via find-or-create-by-name+phone.
- **Complete denture / Prosthodontics** — 8 and 7 sections respectively,
  sharing a 9-stage "Stages and evaluation" table (signature/date/grade per
  stage). Prosthodontics also mirrors selected teeth into a
  `tooth_chart_data` JSON blob alongside its own columns, matching the
  original's dual-write so records stay readable by it. **Date-cast
  gotcha**: Eloquent serializes `date`-cast columns as full ISO datetimes,
  which `<input type="date">` silently refuses to bind — every date field
  rendered blank on edit and then wiped on save, until normalized to
  `YYYY-MM-DD` when seeding the form. Affected every sheet's date fields.
- **Oral medicine** — structurally different: its columns are JSON blobs.
  Three (`jaws_teeth_relations`, `investigations_diagnosis`,
  `student_visits`) have flat scalar subkeys and use the generic `group`
  mechanism; six others (`history_of_complaint`, `past_medical_history`,
  `surgical_history`, `family_history`, `social_history`,
  `extraoral_intraoral_examination`) have nested/array shapes a flat group
  can't express and needed dedicated components
  (`ValueDetailsChecklist.vue`, `SymptomsChecklist.vue`,
  `HistoryOfComplaintSection.vue`, `SurgicalHistorySection.vue`,
  `FamilyHistorySection.vue`, `SocialHistorySection.vue`,
  `ExtraoralIntraoralExam.vue`) with manual JSON parse/stringify (none of
  these columns carry an Eloquent array cast). A first pass had guessed
  several of these shapes wrong from field names alone — corrected against
  real imported rows: `past_medical_history` is a 14-category
  `{value, details}` checklist; `family_history` is 8 plain fields with no
  value/details wrapper; `social_history` was missing two checkbox-array
  fields and had invented option values; `history_of_complaint` was missing
  its entire 28-item symptom checklist.
  - **Head pain-location diagrams**: not freehand drawing — the original
    only records one `{x, y, type}` point per click on four real reference
    images (frontal/posterior/right/left, copied to
    `public/images/head-diagrams/`). Rebuilt as
    `Components/HeadDiagramsBoard.vue`, symbols ported pixel-for-pixel
    (vertical hatching for mild, wavy for moderate, diagonal for severe,
    single letters for 7 named qualities), points stored in the image's
    *natural* pixel space so they line up across screen sizes.
    Flutter's port, `head_diagrams_board.dart` (2026-08-29), reuses the same
    symbol-drawing math translated to `CustomPainter`, and copies the same
    four JPEGs into `flutter_app/assets/images/head_diagrams/`.
- **Prevention** — no per-field columns at all; everything is packed into
  `patient_data`/`examination_data` JSON, re-nested by the controller on
  save/load. Only question 2 of its 10 dental-behaviour questions offers "I
  don't know".
- **Orthodontics** — split sheet: patient/referral half is real columns,
  clinical half is one `examination_data` blob. Three real widgets had been
  entirely missing: `teeth_squares` (a 4×16 "Number of Teeth" marking grid,
  `Components/TeethSquaresGrid.vue`), and `treatment_stages`/
  `appliance_designs` (repeating info+quadrant-picker rows,
  `Components/QuadrantRepeater.vue`). Several fields also had the wrong
  option values (invented `class_i`/`class_ii_div_1`/... instead of the
  real `class1`/`class2`/`class3`) or were plain text where the original
  uses checkbox groups/radios/quadrant pickers — all corrected against the
  markup directly.
- **Surgery** — 9 sections including a 17-row yes/no medical-history
  checklist. A second date/time round-trip bug: MySQL returns `TIME` as
  `HH:MM:SS`, which `<input type="time">` round-trips unchanged, but
  validation (`date_format:H:i`) rejected it on edit even though create
  worked — fixed by accepting both formats.
- **Satellite tables** (surgery follow-ups/images/medications, treatment
  plans/materials) are repeating rows attached to a parent, not standalone
  sheets — each leads with a parent picker instead of a raw integer input.
  `surgery_images.image_path` is a real file upload with preview/cleanup;
  an edit without a new file keeps the existing stored path.
- **Endodontics** (`endodontics_data` on the Operative sheet) — an entire
  section that didn't exist: tooth no., canal count, diagnosis, and 3
  visits with canal tables, gated behind an iOS-style toggle (`.ios-toggle`,
  exact 51×31px track / 27×27px knob / `#34c759`, copied from the
  original's CSS). Built as `IosToggle.vue`, `EndodonticsCanalTable.vue`,
  `EndodonticsSection.vue`, wired as a new `endodontics` field type. Ported
  to Flutter later (`EndodonticsField`) with one deliberate correction: the
  web toggle's "enabled" state is a `computed` derived from
  `Object.keys(modelValue).length > 0`, which snaps back off immediately on
  a never-touched record (its own setter re-emits `{}`, so the getter
  recomputes `false`) — a dormant bug found but left unfixed on web (out of
  scope); the Flutter widget deliberately keeps "enabled" as real local
  state instead of deriving it from map emptiness, avoiding the bug rather
  than reproducing it.

**Generic engine internals worth knowing**: `SectionedForm.vue`'s `group`
subkey mechanism works for both scalar and object-valued subkeys with no
special-casing in `submit()`. Boolean-typed fields need normalizing to
`'1'`/`'0'` strings before the edit form is built — a `tinyint`-cast column
arrives in Inertia props as a real JS boolean, which never matches either
option string, silently discarding the saved state on the `<select>`.

**Partial-update validation bug** (found via the Flutter schema/save flow,
not code review): 11 API controllers built partial-update validation with
`$rules[$field][0] = 'sometimes';`, which unconditionally overwrites a
rule's first element — for any field whose rule starts with `'nullable'`,
this silently deletes it. Laravel's global `ConvertEmptyStringsToNull`
middleware then turns an empty string into `null` before validation, which
fails the bare `string` rule. Any client re-saving a form with an optional
field left blank hit this. Fixed across all 11 controllers to only replace
the first element when it isn't already `nullable`, otherwise prepend
`sometimes` and keep `nullable` too.

## Signatures & sign-off gating

**Auto-captured signatures (2026-08-30).** Every free-typed "signature"
field across all 8 case-sheet resources was replaced with a real captured
signature: the client sends only a sentinel (`__SIGN__`,
`App\Support\CaseSheetSignatures::SENTINEL`), and the actual value
(`"{signer's name} — {Y-m-d H:i}"`) is resolved server-side from the
authenticated user at save time and is then **immutable** —
`CaseSheetSignatures::applyPending()` always re-asserts the stored value
over anything the client sends afterward. Previously any writer, including
the doctor whose own work the signature approves, could type any name in.

New field type `'signature'`, end-to-end: web `SectionedForm.vue`, Flutter
`_SignatureField`/`_StageSignatureField` in `dynamic_section_form.dart`. All
show a "توقيع" button when empty, a pending "will be recorded on save" state
with an undo, or the stamped read-only text once signed. `App\Support\
CaseSheetSignatures` is the single source of truth for which fields on each
resource are signatures (`senior_signature` on dental-charts/surgeries/
periodontal-charts; `supervisor_signature` on orthodontics; grouped
subkeys like `senior_name`/`staff_signature` on prevention/oral-medicine;
all 10 stage + diagnosis signatures on prosthodontics/complete-denture) and
answers "are all of this resource's signatures filled in"
(`allSigned()`/`allSignedForInstance()`). Grouped signatures needed their
own `applyGrouped()` path since the client always posts a grouped column's
whole JSON blob as one string.

**`all_signed` badge.** Signing off does **not** auto-complete a task —
completion stays an explicit separate action. `TaskProgressGroupSummary::
buildDoctorRow()` computes `allSignedForInstance()` per task and exposes it
as `all_signed`, surfaced only on Task Progress as a "✓ كل التواقيع جاهزة"
badge plus a highlighted complete button. Since the same summary service
backs both the web page and `Api\TaskProgressController::group()`, Flutter's
task-progress screen got the field with zero extra API work — its own
matching green pill (`TaskSlotCard.allSigned` in `task_progress_group.dart`,
rendered in `task_progress_screen.dart`) was added the same day after a
screenshot showed the gap; purely a visibility hint, `_completeTask()`
unchanged.

**A stage can't be signed off until its Grade and Date are filled in.**
Scoped to exactly the 9 per-stage `stage_{name}_signature` fields on
Prosthodontics/Complete Denture, not the single `senior_signature`/
`supervisor_signature` fields elsewhere. Enforced twice: server-side,
`CaseSheetSignatures::stageSpecs()` tags each stage with `'requires' =>
["stage_{name}_date", "stage_{name}_grade"]`, and the sentinel is silently
dropped if those aren't already present — a direct API call can't bypass
it. Client-side, both platforms disable the "توقيع" button until both
fields are filled (`stageReadyToSign()` on web; on Flutter, `_StageRow` had
to become a `StatefulWidget` since neither sibling field previously
notified it of a change, leaving `_StageSignatureField` reading stale
values).

## Supervisor-only fields

Certain fields (grades, senior signatures, diagnosis/treatment-plan notes)
are meant to be supervisor/staff-only, editable by everyone else only in
appearance. `App\Support\CaseSheetSupervisorFields` is the registry
(`fieldsFor()`, `stageFields()`).

**Bug — supervisor fields were fully editable on a doctor's own page
(Flutter, 2026-08-29).** `fieldDisabled()` only locked a field because of
`widget.readonly` (true only on the staff preview screen) — a doctor's own
`supervisorEditableFields` is always `[]`, so the disabling check evaluated
false for every field on their own screen regardless of whether it was
supervisor-registered. Fixed by adding an unconditional `supervisorFields`
list to the schema response (as opposed to the per-viewer
`supervisorEditableFields`): a field in that list is locked for everyone
except whoever is currently allowed to edit it, independent of `readonly`.
A doctor can now read a supervisor's notes/grade/signature the moment
they're filled in, but never edit them.

A related backend bug found live via curl: `EnforceCaseSheetAccess`'s
API-vs-web route-name parsing zeroed every resource's supervisor-field list
on the API at all times, so a staff save of even its own allowed fields
always 403'd while a doctor could freely overwrite them.

Registered supervisor-only fields include Operative's `treatment_plan_notes`
and Orthodontics' `diagnosis`/`treatment_plan`/`treatment_stages`/
`appliance_designs` — the latter meant Flutter needed real edit widgets for
Stages of treatment/Appliance type & Design (previously an "unsupported"
placeholder) before a supervisor could actually use their new editing
rights; built as `TeethSquaresGridField`/`QuadrantRepeaterField`.

## Case-sheet printing

The original app had nine standalone `*_print_html.php` pages (34–150 KB
each) that had drifted from each other (different margins/font sizes; two
of nine had no QR block at all). This app has **one document**:
`resources/views/print/case-sheet.blade.php`, generated from the same
`App\Support\*Form::sections()` definitions the on-screen sheets already
use, via `App\Support\CaseSheetPrintRenderer` and a `App\Support\
CaseSheetPrint` registry (model, layout, title, department line per sheet —
copied verbatim from each original print page, including Oral Medicine's
quirk of printing its department inside the letterhead rather than as a
sub-header). Formatting rules (booleans as Yes/No, selects print their
label not stored value, empty fields still print their label so a
supervisor has a row to write on) were taken from what the originals
actually emit. `GET /api/v1/case-sheet-prints/{resource}/{record}` returns
the identical document as JSON so the Flutter client renders the same
layout without reimplementing formatting rules.

**Periodontal grids render server-side deliberately**, diverging from the
original — its own server-side `renderDentalChart()` is a dead stub, and
the real grid is built in JavaScript at print time, which fails if `Ctrl+P`
fires before the script runs. `CaseSheetPrintRenderer::charts()` emits the
same 32-tooth, 3-buccal/3-lingual grid as static server-rendered HTML.

**A real odontogram, not a text table (2026-08-31).** The printed dental
chart originally used a text table (`"Tooth 11: Present — Top: Cavity"`);
rebuilt to draw an actual per-tooth SVG matching the original's
`renderToothSvg()` "flower" of 5 colored surface polygons, reusing the
exact `SURFACE_POINTS`/`SURFACE_COLORS`/etc. constants
`ToothOdontogram.vue` already established (now duplicated onto
`CaseSheetPrintRenderer` and Flutter's `odontogram_vocabulary.dart`).
`dentalChart()`'s return shape changed from pre-flattened label strings to
raw `tooth_status`/`polygons` — a breaking shape change updated on both
print surfaces (Blade and Flutter PDF) in the same pass.

**Circled-tooth graphic for 3 more sheets (2026-08-31).** Surgery,
Complete Denture, and Prosthodontics draw a simpler graphic in the
original — a plain circle around each selected tooth's number. Configured
via a new `toothMarkerCharts` entry per sheet in `CaseSheetPrint::SHEETS`.
**Real cross-format data problem found before shipping**: `surgeries.
selected_teeth` for 16 legacy-imported rows uses the *original* app's own
`U1`–`U16`/`L1`–`L16` numbering, not this app's `UR8`-style quadrant codes
— matching directly would have rendered every legacy surgery sheet's chart
blank. `CaseSheetPrintRenderer::normalizeToothCode()` now accepts all three
real-world formats (this app's quadrant codes, surgery's legacy U/L scheme,
and raw FDI numbers) and normalizes before either print surface sees them.

**Prosthodontics' decorative anatomical arch (2026-08-31).** A large
hand-illustrated 32-tooth SVG, ported verbatim from the original and tinted
by the same missing/carious data the circled markers already show —
redundant with them but part of matching the original. **Real CSS bug**:
the artwork's paths already carry inline `style="fill:..."` attributes,
which always outrank a class selector in a `<style>` block regardless of
source order — the generated tint rules were syntactically correct,
present in the output, and completely invisible until `!important` was
added to every declaration. The kind of bug a "does the HTML contain this
string" check cannot catch.

**Flutter JSON parity gaps (2026-08-30).** The API's print mirror had
drifted from the web Blade view — missing the odontogram block and the
`student_name`/`grade_group` identification-strip fallbacks — closed by
adding the same calls the web controller already made.

**The anatomical arch moved into the live editable form too (2026-09-02).**
By request ("كيس شيت الطالب لا يظهر مخطط الاسنان svg اريد اظهاره") — until
now the arch above only ever rendered in the *printed* document; a student
filling the sheet never saw it. Added a "Dental Arch" card right after
"B- Intraoral Examination" (where `missing_teeth`/`caries_teeth` are
entered) on both platforms, live-reactive to those same two fields as the
student taps teeth — no new backend, no new columns, same
`missing_teeth`/`caries_teeth` data the print path already reads.

Web: new `Components/ProsthodonticsDentalArch.vue`, embedded in
`SectionedForm.vue` behind `resource === 'prosthodontics-records'`
(matching `Api\CaseSheetPrintController`'s own scoping for the `dental_arch`
key). Flutter: `_ProsthodonticsDentalArchPreview` added to
`dynamic_section_form.dart`, gated the same way via a new `resource` prop
threaded through from `case_sheet_form_screen.dart`.

Both compute the tint **by direct string substitution on each path's own
`style="..."` attribute** — the same technique
`buildProsthodonticsDentalArchSvg` (Flutter's print SVG builder, reused
as-is here) already used, and for the same reason the Blade partial needs
`!important`: every path in this artwork carries its own inline style.
Vue's version was tried as a generated `<style>` block first (mirroring the
Blade partial almost verbatim) but that was found live to vanish from the
rendered DOM outright — Vue's SFC compiler treats *any* `<style>` tag
found in the file as one of the file's own top-level blocks and strips it,
even one written inside `<template>`, nested inside an `<svg>`. Switched to
the string-substitution approach instead, which also sidesteps a subtler
problem the `<style>`-block approach would have had anyway: the single
whole-tooth outline carries **two** classes (`tooth-11 tooth-11-parent`),
so a `.tooth-11` rule and a `.tooth-11-parent` rule both legitimately match
it — which one wins becomes a `!important`-tie broken by declaration order,
not by which one is "meant" for that element. String substitution never
faces this, since it targets each `<path>` by its own distinguishing class
combination directly.

**Live-reactivity needed one small state-ownership change on Flutter.**
Every other field widget in `dynamic_section_form.dart` calls only its own
local `setState` when a value changes (the parent form only rebuilds on its
own actions), which is correct for fields with no sibling depending on
their value — but `missing_teeth`/`caries_teeth` now have exactly that
sibling. `_QuadrantTeethFieldWidgetState`'s `onChanged` was changed to call
the *parent* `DynamicSectionFormState`'s `setState` instead, so tapping a
tooth also rebuilds the new preview card. Web needed no equivalent change —
`form` is already one shared reactive object (`useForm()`), so a computed
property watching `form.missing_teeth`/`form.caries_teeth` updates on its
own.

Verified live on both platforms: the full 32-tooth artwork renders
completely (182 paths + 32 number labels — confirmed by count, after an
early draft of the Vue version shipped with roughly a third of the teeth
missing, an accidental manual-transcription error caught before commit by
comparing path/text counts against the source Blade partial), and tapping
a tooth in the missing-teeth picker visibly greys it out in the preview
immediately, before saving.

## Periodontal Plaque Index

A genuinely new feature (2026-08-31), not a print-fidelity port: the
original has a completely separate per-visit "Plaque Index" chart (5
visits — `visit2`–`visit5`, `followup` — each a curved-tooth diagram of 4
quadrant surfaces per tooth with a live percentage) that this app had never
captured on either platform. It deliberately keeps the original's 5-visit
model rather than folding into this app's existing 3-stage BOP/PPD/CAL
convention — both now coexist in `chart_data` under separate top-level keys
(`perioChart` vs. `dentalCharts`).

- **`App\Support\PlaqueChart`** — visit list, tooth-shape vocabulary (FDI
  number → molar/premolar/canine/incisor with real curved-outline path
  data copied from the original's `toothShapes`), and `visitData()`, which
  recomputes the plaque-index percentage at render time (an extracted
  tooth's surfaces never count toward the total).
- **Web editor** — `Components/PlaqueChart.vue`, initially a checkbox grid,
  then rewritten (2026-08-31, after a production report that no SVG was
  showing) into a real tappable diagram: each of 32 teeth per visit is its
  own small `<svg>` with the curved tooth outline as a `<clipPath>` and 4
  quadrant `<polygon>` triangles (green `#4caf50` at 0.7 opacity when
  marked) — clicking a triangle toggles that surface directly.
- **Web print** — `resources/views/print/partials/periodontal-plaque-
  chart.blade.php`, real inline SVG per tooth clipped to its curved outline.
- **Extraction syncing** — marking a tooth extracted via its number label
  (not a separate control, matching the original) now syncs across all 5
  visits in one update (only the `extracted` flag, not each visit's own
  surface marks), and further syncs visually into the BOP/PPD/CAL grid
  tables (`PerioChart.vue` gained an `extractedTeeth` prop; extracted teeth
  render greyed with a red " ✕" tooth-number cell) — a one-way,
  display-only sync since the grid never had its own extraction control to
  sync back from.
- **Flutter** — `Periodontal "Plaque Index": a genuinely new feature, not a
  print port` entry ports the same feature; its on-screen editor
  deliberately uses plain checkboxes rather than the tappable diagram (same
  tradeoff reasoning as web's initial checkbox version).

## Advanced Periodontal Chart

A brand-new case-sheet type (2026-08-31) with no legacy counterpart,
modeled functionally on periodontalchart-online.com's own charting tool
(screenshotted by the user, not copied): patient info, an Initial
Exam/Re-evaluation toggle, a 32-tooth × 6-site probing grid (Mobility,
Implant, Furcation, Bleeding on Probing, Plaque, Gingival Margin, Probing
Depth, Attachment Level — "192 sites" = 32 teeth × 2 zones × 3 sites), and a
tooth-row diagram with a gumline. The line art is this app's own (extracted
from an anatomical reference asset the user commissioned specifically to
avoid any copyright question), not the reference site's illustrations —
confirmed as copyright-safe since the layout *concept* (two arch rows, a
gumline, a metric grid) is a generic charting convention no tool owns.

**Structure**: a real DB table via migration (the first case-sheet table in
the whole project with a real `Schema::create` rather than a legacy-import
row) — `App\Models\AdvancedPeriodontalChart`, `App\Support\
AdvancedPeriodontalChartForm` (just patient info + notes/signature —
the big grid isn't a `sections()` field, same pattern as Plaque Index),
matching web/API controllers copied from `PeriodontalChartController`'s
plumbing. The grid itself lives in `chart_data.advancedChart`
(`{teeth: {'18': {mobility, implant, furcation, buccal: {bop, plaque, gm,
pd, al}, lingual: {...}}, ...}}`, sparse). A boolean schema flag
(`advancedPerioChart`) drives both platforms' generic chart-submit
machinery with zero changes needed to either's payload spreading — the same
"new sibling key rides along automatically" property Plaque Index
established. Print was deliberately **not** built at launch (the generic
renderer only knows `sections()`, so a print button would show patient info
only) — suppressed on both platforms rather than shipping an incomplete
printout.

The feature then went through 11 more same-day revisions, each driven by a
live comparison against the reference site (inspected in a browser tool —
DOM, computed styles, and CSS read directly rather than guessed) or a
user-supplied static reference asset. The throughline: get the artwork,
layout, and interaction model to genuinely match real dental charting
conventions, verified live rather than assumed, catching several
subtly-wrong ports along the way.

- **Real artwork, not decoration** (rev. 2): the reference asset's 32 teeth
  reduce to 8 unique per-position crown/root shapes per arch (mirrored
  across the midline) plus one shared implant-fixture graphic — extracted
  and cross-checked byte-for-byte via a Node script against the source
  file (all 37 tooth paths + 4 implant paths matched exactly). The
  implant graphic now actually reads each tooth's `implant` flag instead of
  being purely decorative.
- **Layout churn** (rev. 2 → rev. 5): first built with a `table-fixed` +
  percentage-width `<colgroup>` to guarantee zero horizontal scroll — then
  reversed by explicit request, since shrinking 48 site-columns to fit any
  viewport made cells ~7px on a phone, below any usable tap target.
  Reverted to fixed-pixel cells inside a scrollable wrapper, matching how
  `PerioChart.vue`/`PlaqueChart.vue` already work elsewhere in the app.
  Row structure was also tightened to match the reference site's own
  logic: Mobility/Implant once per arch; BOP/Plaque/GM/PD/AL/Furcation
  twice per arch (buccal + lingual aspects).
- **Upper-arch orientation bug** (rev. 4): the extracted path data is
  authored crown-up/root-down (the lower jaw's natural orientation); the
  reference counters this on upper-arch teeth with a `scale(1,-1)`
  transform that got silently dropped during extraction. Fixed via a
  `toothTransform(isUpper, idx)` helper, solving algebraically for a
  reflection that keeps both arches' vertical extents in the same
  screen-y range rather than eyeballing a number.
- **Real measured pixel dimensions, and two live bugs** (rev. 6): read
  directly off the reference's DOM via `getBoundingClientRect()`/
  `getComputedStyle()` rather than estimated — a site-cell input is
  exactly **15px** wide, each row **20px** tall, the label column **130px**
  at 14px font (this app used 140px given longer combined label strings).
  Two bugs found live while resizing: (1) `w-full` on single-value/Note
  inputs inside an `auto`-layout table created a circular sizing
  dependency, falling back to the `<input>`'s HTML default (`size="20"`,
  ~170px) and inflating every sibling column — fixed with an explicit
  `w-[45px]`. (2) Under this app's RTL (Arabic) layout, the data table's
  columns reverse visually while the SVG graphic's internal coordinates
  stay absolute (tooth 18 always draws at `x=0`), so the graphic and its
  data columns pointed at opposite ends of the row — fixed by forcing
  `dir="ltr"` on each arch wrapper, since FDI tooth order is a fixed
  international convention that shouldn't flip with UI language (matching
  reasoning the Flutter side had already established elsewhere).
- **The crown must never disappear** (rev. 7): toggling Implant had been
  swapping the *whole* tooth drawing; the reference's own CSS only hides
  root/canal/furcation/detail on implant-mode, never the crown — real
  anatomy backs this too (an implant replaces the root, not a still-visible
  crown/restoration). Fixed by moving the crown path outside the
  conditional entirely.
- **Extraction + Furcation as tap-to-cycle** (rev. 8), read from the
  reference's live DOM/CSS: tapping a tooth's own number toggles
  `extracted` (reusing the same interaction/data convention Plaque Index
  established); an extracted tooth dims to 35% opacity with a red-cross
  overlay and all 6 of its site metrics lock, shrinking the "192 sites"
  stats denominator by 6 per extracted tooth. Furcation became a
  tap-to-cycle grade (`0→1→2→3→0`, confirmed by clicking through the
  reference's own button and reading `dataset.grade`) instead of a free
  number field, and additionally locks (display: none) for an implant
  tooth, since a fixture has no natural furcation — while the other 5 site
  metrics deliberately stay active for an implant, since peri-implant
  tissue is still probed/bled/plaque-scored normally.
- **Real furcation icons + a GM/PD "pocket" overlay on the graphic**
  (rev. 9), reverse-engineered by diffing the reference's live SVG
  before/after entering values (not inferred from screenshots): furcation
  grade 0 has no icon, grade 1 a hollow ring, grade 2 ring + filled
  half-circle, grade 3 a full filled disc — reused verbatim as plain
  geometric iconography (not the copyright-sensitive tooth art). For
  GM/PD: a positive GM value moves its marker away from baseline by
  `value × 6.45px` (the reference's own measured px/mm ratio,
  `POCKET_SCALE`), negative moves the opposite direction (recession); PD
  is measured *from the GM line*, not the fixed baseline (`pd_y = gm_y +
  pd × scale`, confirmed by testing PD alone, then GM alone, then both
  together); Attachment Level has **no** visual representation on the
  reference's own graphic at all (confirmed by exact SVG length
  before/after), only in summary stats.
- **Furcation is one field per tooth, not one per site, drawn on the tooth
  itself** (rev. 10): the reference's buccal furcation button carries a
  `single-button` class its mesial/distal-palatal buttons don't — one
  grade per tooth per aspect, not 3 site positions. More importantly, the
  grade draws directly on the tooth's own SVG group (a ring/half-circle/
  full-disc appended into it), not just in the table cell — ported as a
  `FURCATION_MARKER` shape placed in the same per-tooth `<g>` as the
  GM/PD overlay.
- **Y-direction bug for the furcation marker and GM** (rev. 11): this
  component's local tooth-coordinate space and the reference's raw SVG
  y-axis run in *opposite* directions; revisions 9 and 10 had copied the
  reference's raw arithmetic sign without accounting for that, silently
  placing the furcation marker coronal (into the crown) instead of apical
  (into the root, correct anatomy) and inverting GM's direction too.
  Root direction was pinned down unambiguously by probing an unambiguous
  value (`pd = 10`, which can only mean "deeper into the sulcus") and
  reading which way y moved. A bug only a directional/anatomical check
  could catch — matching raw numeric values (as earlier revisions'
  verification had done) was not sufficient.
- **mm-ruler gridlines + a PD ≥4mm highlight** (rev. 12): the reference
  draws 17 unclassed `<line>` elements per quadrant (1.25px stroke, spaced
  exactly 6.45px apart = 1mm, spanning the full row width) as a visual
  ruler over the root region — ported as `mmGridlineYs()`, appended *after*
  the tooth `<g>` loop so they paint over the vector root fills (the
  reference gets this for free since its teeth are a background raster
  image). Also added: a PD value ≥4 turns red (`pd-high` class,
  `color: red !important`) — the exact threshold confirmed by testing each
  value individually rather than trusting the page's own legend text.
  A broader page survey at this point turned up several standalone
  features (Classification/PRA risk panel, Overview/Analysis/Interval
  charts, 3D view, QR export, print calibration) explicitly noted as
  candidates for a future separately-scoped request rather than folded in
  here.

Verification for nearly all of these revisions was done via `tinker`/`curl`/
`npm run build` per this session's "no browser" default, except revisions
6 through 9 and 12, which were explicitly verified live in a browser tool
against the real running page (temporary doctor accounts created and
deleted per session) because the user asked for a direct comparison against
the reference site rather than a code-level judgment call.
