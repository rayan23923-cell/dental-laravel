# Supervisor Field Access Control & Password-Reset (OTP) Bug Hunt

Two related-by-timing but distinct threads from the 2026-08-28 → 08-31 dev
stretch.

The first: across almost every clinical case-sheet type (Operative,
Orthodontics, Periodontal Chart, Prevention, Oral Medicine, Prosthodontics,
Complete Denture, Surgery), a recurring class of field — student identity
(`student_name`, `group_name`), signatures, grades, and in a couple of
resources the diagnosis/treatment-plan itself — is meant to be filled in
only by a supervisor/senior doctor reviewing a student's work, never by the
student (the doctor account) whose case sheet it is. This wasn't designed
up front; it was rolled out case-sheet-type by case-sheet-type as the user
walked through live screenshots of each form, which is why the same class
of bug (a field visibly editable when it shouldn't be, a generic-diff
helper that didn't understand a new field shape) kept resurfacing across
different resources and had to be fixed generically rather than per-type.

The second, unrelated except in timing: the password-reset flow was
switched from an emailed link to a 5-minute one-time code, which then
triggered a multi-day production bug hunt to get the OTP email actually
delivering — a chain of red herrings (missing logging, log level, timezone
theories) before the real root cause surfaced: a raw database timestamp
string handed to a Carbon diff method.

## Supervisor-only field access control

### Infrastructure

- **`App\Support\CaseSheetSupervisorFields`** — a `match()` registry (same
  pattern as `CaseSheetResolver`/`CaseSheetPrint`) mapping each of the 8
  case-sheet resources to the field(s) only a supervisor may edit.
  `dental-charts`/`surgeries`/`periodontal-charts` reused existing
  `notes`/`senior_doctor_name`/`senior_signature` columns;
  `prosthodontics-records`/`complete-denture-records` reused their existing
  `diagnosis_instructor_signature` + 9 `stage_{key}_{signature,date,grade}`
  triples; `orthodontics-records`, `prevention-records`, and
  `oral-medicine-charts` had no such column at all, so two new nullable
  columns (`supervisor_notes`, `supervisor_signature`) were added to those
  three, plus a rendered "Supervisor" section in each layout.
- **`EnforceCaseSheetAccess`** middleware gained the enforcement rules: a
  staff write may only *change* a resource's registered supervisor
  field(s) (compared value-by-value against the stored record via
  `boundRecord()`/`changedFields()` — not just "keys present," since the
  form always resubmits every field); a doctor may never *change* those
  same fields on their own record (resubmitting the unchanged value is
  fine).
- **Client-side lock**: `SectionedForm.vue` (web) and Flutter's
  `DynamicSectionForm` compare each field against the resource's full,
  unconditional `supervisorFields` list (independent of `readonly` mode)
  to decide whether to disable it — see the "fully editable" bug below for
  why this needed its own list rather than reusing the readonly-only
  supervisor-editable list.

### Rollout by case-sheet type

| Resource | Removed (redundant with doctor identity) | Locked to supervisor |
|---|---|---|
| Orthodontics | Student Name, Supervised by, Referral Date, Referred from, Group | Diagnosis, Treatment plan, Stages of treatment, Appliance type & Design, `supervisor_notes`/`supervisor_signature` |
| Periodontal Chart | Student Name, Student Group, Case Start Date, Mentor Name | `senior_doctor_name`, `approval_date`, `clinical_notes`, `senior_signature` (already gated pre-2026-08-29; verified, then `senior_signature` added) |
| Prevention Record | Student Name, Group (`patient_group`, `nutritional_group`), Date (auto-filled instead), duplicated Nutritional Assessment name/age/class | `senior_name`, `signature_date` (subkeys of `patient_data`), `supervisor_notes`, `supervisor_signature` |
| Operative (dental-charts) | — | `senior_doctor_name`, `senior_signature`, `notes`, `treatment_plan_notes` |
| Oral Medicine | Student Name | `staff_signature`, `date` (subkeys of `student_visits`), `supervisor_notes`, `supervisor_signature` |
| Prosthodontics | Student Name, Group | `diagnosis_starting`, `diagnosis_grade`, `diagnosis_instructor_signature`, 9 stage signature/date/grade triples |
| Complete Denture | Student Name, Group | `diagnosis_instructor_signature` + its 9 stage triples (no `diagnosis_grade`/`diagnosis_date` exist on this resource) |
| Surgery | Student Name, `grade_group` was *kept* on explicit user request (combined Grade+Group column), Date, Start time, Status, Staff signature, Anesthesia type, Duration | `senior_doctor_name` (auto-fills from `task_instances.assigned_by`, still supervisor-editable after) |

`group_name`/`Group` fields were audited and removed across all 8 layouts
in a final sweep once the pattern was established. Auto-filled
replacements (`student_name` from the doctor's own name, `referral_date`/
Prevention's `date` from `now()`) are set once at record creation only,
never overwritten on update — the same convention used elsewhere in the
app (`Payment.paid_at`).

### Generic bugs surfaced along the way

**Grouped-field diffing (`changedFields()`) didn't understand JSON blobs.**
Several resources (Prevention's `patient_data`, Oral Medicine's
`student_visits`) pack their patient/signature fields as subkeys of one
JSON-blob column rather than real top-level columns — the client always
posts the whole blob as one string. The original `changedFields()` diffed
whole top-level keys, so it could never match a bare subkey name like
`senior_name` against the registered field list: a legitimate supervisor
edit would 403, and a doctor could freely overwrite the same subkeys
undetected (an empty allow-list intersection matches nothing either way).
Fixed generically: when both the stored and submitted values for a key
decode as JSON arrays, diff the decoded subkeys instead of the outer
column name. Deliberately not distinguishing a JSON object from a JSON
list, since PHP's `json_decode(..., true)` can't tell an empty `{}` from
an empty `[]` apart, and a first-ever edit to a still-empty blob needed to
work either way.

**Array-valued fields silently bypassed the doctor-write block.**
Orthodontics' `treatment_stages`/`appliance_designs` are repeater arrays,
not scalars. The diff's value comparison used a plain `(string)` cast,
but PHP casts *any* array to the literal string `"Array"` — so two
different array values always compared equal, meaning `changedFields()`
never reported them as changed and the doctor-side write block never
fired for these two fields, even though the client-side lock displayed
correctly. Fixed with a `differs()` helper: arrays compare via
`json_encode()`, scalars keep the original string-cast comparison.

**Resource-name resolution silently broke on every API route.** In the
initial rollout, `EnforceCaseSheetAccess` resolved a resource name via
`explode('.', $routeName, 2)[0]`, correct for a bare web route name
(`{resource}.{action}`) but wrong for every `routes/api.php` route, which
is wrapped as `api.{resource}.{action}`. Every API request silently read
`'api'` as the resource, which resolved to the registry's `default => []`
— zeroing the allow-list on *every* API request in both directions at
once: a staff request 403'd even writing its own allowed fields, and a
doctor could freely overwrite supervisor fields on their own record.
Fixed by reading the second-to-last dot-segment (robust to either
`{resource}.{action}` or `api.{resource}.{action}` shape, since the action
segment is always exactly one segment).

**API had no case-sheet enforcement at all before this rollout.** The
`EnforceCaseSheetAccess` middleware was wired into `routes/web.php` only;
`routes/api.php` had none, so any authenticated Sanctum principal (staff
or doctor) could read/write/delete any of the 8 case-sheet resources via
the mobile API regardless of ownership. Fixed by applying the same
middleware alias to the API route groups. This surfaced a second bug:
`CaseSheetAccess::doctor()` checked only the web session's `doctor` guard,
never populated over Sanctum, so every legitimate doctor API request was
misclassified as staff and limited to view-only — fixed by falling back
to `request()?->user()`.

**API validation/Resource gaps dropped fields silently.** `senior_signature`
was missing from `Api\DentalChartController`'s validation rules entirely
(only `notes`/`senior_doctor_name` were listed), so `$request->validate()`
silently stripped it on every staff save even though the column was
`$fillable` and the middleware allowed the write. `DentalChartResource`
had the matching read-side gap. The web equivalent never had this problem
since its rules are generated dynamically from the form layout; the API
side lists rules by hand.

**A doctor's `TaskInstance` write silently dropped new columns.**
`TaskInstance::$fillable` never listed the new
`paper_case_sheet_confirmed_by`/`_at` columns, so `confirmPaper()`'s
`update()` call returned a clean 200 with nothing actually written —
Eloquent drops non-fillable mass-assignment keys instead of throwing.
Caught only by checking the database directly rather than trusting the
200 status.

**Supervisor fields were fully editable on a doctor's own page.** The
client's `fieldDisabled()` computed the lock as
`readonly && !supervisorEditableFields.includes(field.key)` — a field was
only ever locked *because of* `readonly` (the staff preview mode). A
doctor editing their own record always has `readonly === false`, so every
supervisor field rendered as a perfectly ordinary editable input, with no
visual cue it wasn't theirs to touch (the server-side 403 was already
correct; nothing on screen reflected it). Fixed by giving the client a
second, independent list — the registry's full, unconditional
`supervisorFields` for the resource, as opposed to `supervisorEditableFields`
(non-empty only for the one viewer currently allowed to edit them).
`fieldDisabled()` now checks that list first: a field on it is locked
unless this viewer is the one who may edit it, full stop, independent of
`readonly`. Net effect: a doctor can read a supervisor's notes/signature
once entered, but the input stays visibly disabled and can never be typed
into.

**Row-removal left stale numbering.** Orthodontics' repeater rows (Stages
of treatment / Appliance type & Design) didn't renumber after a row was
removed, unlike the original app's `renumberTreatmentStages()`, leaving
labels out of sync with position. Fixed in both `QuadrantRepeater.vue` and
its Flutter twin by reassigning remaining rows to fresh sequential
indices on removal. Flutter needed an extra fix: its per-row
`TextEditingController`s were keyed by position, so after renumbering a
key could belong to a different row's data and show stale cached text —
fixed by disposing and recreating controllers fresh from the renumbered
data.

**Department-role scoping was missing from Task Progress.** A Senior/HR
role assignment (department + stage, via the existing Department Roles
screen) didn't actually restrict anything — a Senior/HR saw every
department's tasks on Task Progress exactly like an unrestricted admin.
Fixed by giving `ScopeHelper::allowedDepartmentIds()`/`allowedStageIds()`
a fallback: when a user has no explicit `user_allowed_*` scope rows, fall
back to their active `DepartmentRoleAssignment` rows instead of treating
them as unrestricted. Because `TaskProgressFilters`/`TaskProgressGroupSummary`
already called through `ScopeHelper`, this needed zero changes to either
Task Progress service, controller, or Vue/Flutter file — deliberately
scoped to Task Progress only, not the other three call sites research
turned up (Orthodontics field-lock, admin dashboard Senior/HR switch, HR
presence widget).

**Doctor's QR-scan autofill hit a staff-only permission gate.** The new
"مسح رمز المريض" patient-autofill button 403'd for every doctor, since it
reused the staff-only `patients,view`-gated `scan()` endpoint by mistake
— no doctor session or Sanctum token could ever pass that gate. Fixed
with new, doctor-only `scanForCaseSheet()` endpoints (web and API) rather
than loosening the staff-facing route, additionally enforcing
`PatientScreeningGate::ensureClear()` before returning any data.

## Password reset via OTP

**The switch.** Replaced the emailed reset link with a 6-digit,
5-minute-lifetime one-time code, for both account types (staff `users`
and `doctor` guards). Investigated the two claimed vulnerabilities before
changing anything: the reset-page email field being editable after
clicking the link was confirmed real at the UI level but not actually
exploitable (`Password::reset()` looks the user up by whatever email is
submitted, and the token only matches its own row); the "link still works
after a day" report turned out to be the page opening regardless of
age — the 60-minute expiry was enforced only on actual submission, not on
page load, which is expected default Laravel behavior for that flow
shape, not a real bug. The OTP switch was implemented anyway, since it
fits the Flutter client (type a code in-app) much better than a
browser-handoff link.

New pieces: `password_reset_otps` table (`email`, `guard`, hashed `otp`,
`expires_at`); `App\Services\OtpPasswordResetBroker` (`send()` — 6-digit
`random_int`, hashed, throttled to one new code per 60 seconds;
`verify()`; `forget()` — single-use); `App\Notifications\OtpPasswordReset`
replacing the framework's default `ResetPassword` notification and the
deleted `App\Notifications\DoctorResetPassword`. Every forgot-password
surface (web controllers for both guards, `Api\PasswordResetController`)
was rewritten to match; the API side gained a real `reset()` completion
endpoint since a typed code, unlike a link, has nowhere else to go.

### The delivery bug hunt (three commits over two days)

**Day 1 — not going through the standard notifier.**
`OtpPasswordResetBroker::send()` called `$notifiable->notify(...)`
directly instead of `App\Services\Notifier::send()`, the wrapper every
other notification in the app uses. Delivery is synchronous (no
`ShouldQueue`), so a transport-level failure threw straight through the
controller — the whole HTTP request failed instead of returning the
neutral "sent" response, and nothing was logged either way, making a real
send failure indistinguishable from a test against an unregistered
address. Fixed by routing through `Notifier::send()`, which wraps the
call in try/catch and logs failures.

**Day 2 — the log stayed completely empty even after that fix.**
Two more silent gaps found by elimination (not spam, `enable_notifications`
confirmed on): (1) the resend-throttle branch was a bare `return;` with no
log line at all — a same-minute repeat test during debugging would silently
no-op with zero trace; (2) every diagnostic log added so far used
`Log::debug()`, and production's `.env` could plausibly have `LOG_LEVEL`
above `debug` (the app's own config default is only a fallback, not proof
of the real server setting), which would silently drop every debug-level
line before it reached the file — reproducing the exact symptom
independent of the real cause. Both fixed (added the missing log line;
matched `Log::warning()`, the level already used by the working failure
branch).

**The actual root cause — a raw DB string handed to `diffInSeconds()`.**
Tracked down via a live production debugging session (cPanel Terminal +
two temporary diagnostic routes, both removed once resolved). Confirmed
`LOG_LEVEL=error` in production's real `.env` (via `grep`), meaning even
the `Log::warning()` calls from the day-2 fix were being dropped — so the
investigation moved to direct terminal probing: a registered doctor
confirmed via `tinker`; raw `Mail::raw()` confirmed SMTP itself worked;
calling `Notifier::send()` directly (bypassing the broker's DB/throttle
layer) also delivered correctly — the first real clue that everything
downstream of the throttle check was fine. The actual bug:
`now()->diffInSeconds($existing->created_at)` passed the **raw database
string** (e.g. `"2026-08-29 18:45:42"`) straight into `diffInSeconds()`
instead of an explicit Carbon instance. A `password_reset_otps` row from
the very first round of testing the day before was still being evaluated
as "issued within the last 60 seconds" twelve-plus hours later, on every
single request — the throttle's silent `return;` had been firing on
*every* attempt since the first. `verify()` had the identical unsafe
pattern by inspection, fixed alongside it, though it hadn't yet
misbehaved separately.

**Follow-up, same day — half the bug remained.** Wrapping the string in
`Carbon::parse()` fixed only half of it: `diffInSeconds()` in this app's
Carbon version returns a **signed** value, negative whenever the compared
date is in the past relative to `now()` — which every stored `created_at`
always is by the time the check runs again. A negative number is always
less than the throttle threshold, so the throttle still fired
unconditionally regardless of real elapsed time. Replaced the diff
entirely with
`Carbon::parse($existing->created_at)->addSeconds(self::THROTTLE_SECONDS)->isFuture()`
— an unambiguous "is the cooldown window still ahead of us" check with no
sign convention to get backwards. `verify()`'s `now()->greaterThan(...)`
needed no equivalent change, since it's a plain boolean comparison, not a
diff.

**Confirmed working, same day**: a real request through the Flutter app
produced a fresh, randomly-generated code arriving by email within about
a minute — the full pipeline (throttle → generation → DB write →
`Notifier::send()` → SMTP) genuinely works end-to-end. The first two
fixes (notifier routing, then logging/log-level) were real, worthwhile
improvements to the app's error handling and observability on their own,
but neither could have caught the actual reported symptom — the
throttle's inverted comparison was the entire cause of no email ever
arriving.

## Reference: project layout / scope

*(Preserved close to verbatim from the README — standing reference
material, not narrative.)*

### Project layout notes

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

### Explicitly out of scope (by request)

- **MikroTik backup integration** — the original PHP app's router-based
  off-site backup feature. Not being ported.

### Not yet built

- **Camera QR scanning UI** — the generate/scan/resolve API loop is built
  (see "QR check-in" in the main README); no browser-camera scanner page
  (the original's `qr_scanner.html`) — that's expected to live in the
  Flutter client instead.
- `doctor_tasks`, `task_assignments`, `task_progress`, `doctor_task_progress`
  — imported for schema fidelity, no models/controllers (see "The task
  system — which tables are actually used" in the main README).
- `tooth_conditions` / `tooth_treatments` — have models (`ToothCondition`,
  `ToothTreatment`) and relations off `DentalChart`, but no dedicated
  controllers or routes; `dental_charts.tooth_data` (JSON) is the confirmed
  real write path (see "Dental Chart module" in the main README), so these
  two are schema fidelity + read-via-relation only for now.

Each of these follows the same pattern established so far: Eloquent model →
web controller + Inertia Vue pages → matching API controller + Resource +
routes in `routes/api.php`.
