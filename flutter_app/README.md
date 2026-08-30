# Dental Clinic — Flutter Client (Plan)

Mobile client (Android + iOS) for the teaching-clinic system, consuming the
`/api/v1` Laravel API already built in `dental_laravel/`. This document is
the implementation plan — grounded in the real, already-shipped API surface
(read directly from `routes/api.php` and the actual controllers, not
guessed), not a wishlist.

**Current state**: `flutter create` scaffold only, plus `pubspec.yaml`
dependencies chosen and verified (`flutter pub get` resolves clean,
`flutter analyze` reports no issues). No feature code yet — this README is
the plan for what comes next, per request.

## 1. Who this app is for

Two personas use the web app today; this plan treats them differently
rather than porting every admin screen 1:1:

- **Doctor** (dental student) — the primary mobile user. Task list, filling
  in case sheets, QR check-in, viewing progress. This is genuinely a
  mobile workflow (walking between clinic chairs, scanning a patient's QR).
- **Staff / Admin** — manages doctors, groups, permissions, clinic
  settings, backups. This is a desk-bound, data-entry-heavy workflow the
  existing Inertia web app already serves well.

**Recommendation**: Phase 1–2 build the full doctor experience. Admin
screens are Phase 3, lower priority — the API for them already exists (per
the standing "every module needs an API" rule), so nothing blocks building
them later; this is a sequencing call, not a scope cut.

## 2. Architecture

```
lib/
  main.dart
  app.dart                      # MaterialApp.router + ProviderScope
  core/
    network/
      api_client.dart           # Dio instance: base URL, bearer token interceptor, 401 handler
      api_exception.dart        # typed error wrapping Laravel's {message, errors} validation shape
    storage/
      token_storage.dart        # flutter_secure_storage wrapper
    router/
      app_router.dart           # go_router: route table, auth guard redirect
    theme/
      app_theme.dart            # a fixed Instagram-style light+dark theme (§7) — no
                                 # longer fetched from clinic-settings, see §7 for why
  features/
    auth/            (data/domain/presentation split per feature)
    tasks/
    task_instances/
    case_sheets/                # see section 4 — one dynamic renderer, not 12 screens
    patients/
    doctors/                    # admin, Phase 3
    appointments/
    payments/
    qr/
    clinic_settings/            # admin, Phase 3
    backup/                     # admin, Phase 3
    tv_board/                   # public kiosk view, optional
  l10n/                         # Arabic (primary) + English
```

Each feature folder: `data/` (repository calling `ApiClient`), `domain/`
(plain Dart models with `fromJson`/`toJson`, matching the API Resources'
real field names — no `freezed`/build_runner; the model shapes are stable
and hand-written models are one less build step for a team new to Flutter),
`presentation/` (Riverpod providers + screens/widgets).

**Why this stack** (each choice justified against the alternative, not
picked by default):
| Package | Role | Why this one |
|---|---|---|
| `dio` | HTTP client | Interceptors for the bearer token and centralized 401→logout, which the plain `http` package needs hand-rolled per-call |
| `flutter_riverpod` | State management | Compile-safe provider graph, testable without a `BuildContext`, less ceremony than Bloc for a team-of-one-plus-Claude codebase |
| `go_router` | Routing | Declarative routes + deep link support — needed for "scan a QR, land directly on that task instance" |
| `flutter_secure_storage` | Token persistence | Keychain/Keystore-backed, not plain SharedPreferences, for a bearer token that authorizes clinical data |
| `mobile_scanner` | QR scanning | Actively maintained, CameraX-based on Android; mirrors the web app's own QR check-in feature (`TaskInstanceQrController`) |
| `cached_network_image` | Images | Doctor photos, clinic/university logos — avoids re-fetching on every rebuild |
| `image_picker` | File uploads | Doctor profile photo, surgery images — matches the web app's existing upload fields |

## 3. Auth

Two login endpoints, already built and unchanged by this plan:

| Endpoint | Body | Returns |
|---|---|---|
| `POST /api/v1/login` | `email`, `password`, `device_name` | `{ token, user }` (`UserResource`: id, full_name, username, email, phone, role, status, profile_image) |
| `POST /api/v1/doctor/login` | `username`, `password`, `device_name` | `{ token, doctor }` (`DoctorResource`: id, name, username, email, phone, profile_image_url, education_type, stage, academic_session) |

`device_name` should be a real device identifier (e.g. `package_info_plus`
+ `Platform.operatingSystem`) so a doctor can see/revoke individual device
sessions later — the API already supports multiple named tokens per user
via Sanctum, nothing to add server-side.

A single login screen with a segmented toggle ("طالب / موظف") picks which
endpoint to call — matches the web app's own `/login` vs `/doctor-login`
split. Token stored via `flutter_secure_storage`; `Dio` interceptor attaches
`Authorization: Bearer <token>` to every request after login and redirects
to the login screen on a `401` response (expired/revoked token).

## 4. Case sheets — the one architectural decision worth getting right

The web app has **12 clinical specialty forms** (Periodontal, Complete
Denture, Prosthodontics, Oral Medicine, Prevention, Orthodontics, Surgery,
Operative/Dental Chart, plus 4 satellite tables). Building 12 hand-crafted
Flutter screens would duplicate exactly the mistake the web app *stopped*
making: `SectionedForm.vue` + `App\Support\*Form::sections()` on the web
side replaced 12 bespoke Vue pages with one generic renderer driven by a
PHP-side layout description (see `dental_laravel/README.md`, "Web forms —
one generic form, not 12 bespoke ones").

**The API didn't expose that layout at first** — a Flutter client only saw
the raw stored columns (via the 12 REST resources already listed below),
not the section/field/type/options metadata that drives the web form. Two
real options considered at the time (Phase B is now built — see §6):

- **Phase A (ships fast, done first)**: read-only case sheet screens,
  built from `GET /api/v1/case-sheet-prints/{resource}/{record}` — this
  endpoint already exists and returns a print-ready document model
  (`Api\CaseSheetPrintController`, backed by the same
  `CaseSheetPrintRenderer` the web print page uses). A doctor can review
  any case sheet on their phone from day one, no new backend work.
- **Phase B (recommended before writing 12 edit screens)**: add one new
  endpoint, e.g. `GET /api/v1/case-sheet-forms/{resource}`, that calls the
  same `App\Support\*Form::sections()` each web page already calls and
  returns it as JSON (field key, label, type, options, width, group — the
  exact array `SectionedForm.vue` already consumes, just serialized).
  Then build **one** `DynamicSectionForm` Flutter widget that renders any
  of the 12 sheets from that schema, mirroring the field-type switch
  `SectionedForm.vue` already has (text/textarea/select/radio/checkboxes/
  teeth-picker/etc.) — new field types (like this session's
  `teeth_squares_grid` or `quadrant_repeater`) get added once, not per
  sheet. This is a small, well-scoped backend addition (one controller
  method reusing existing `sections()` calls) that avoids a 12x front-end
  effort.

Editing case sheets is therefore **Phase 2**, gated on the small Phase B
backend addition — flagged explicitly so it isn't accidentally started as
12 separate hand-built screens.

## 5. Full API surface (as built today)

Grounded directly in `routes/api.php` — every route listed actually exists
and is reachable behind `auth:sanctum` (except login and the public
TV board).

| Area | Endpoints | Phase |
|---|---|---|
| Auth | `POST /login`, `POST /doctor/login`, `POST /logout`, `GET /me` | 1 |
| Task instances (doctor's own work) | `GET /my-task-instances` (`?status=`), `GET/POST/PUT/DELETE /task-instances/{id}`, `GET /task-instances/{id}/qr`, `POST /task-instances/scan` | 1 |
| Tasks (catalogue) | `GET/POST/PUT/DELETE /tasks` | 1 (read), 3 (write, admin) |
| Case sheet prints | `GET /case-sheet-prints`, `GET /case-sheet-prints/{resource}/{record}` | 1 (Phase A above) |
| Case sheets (12 specialty tables) | full REST per table: `complete-denture-records`, `oral-medicine-charts`, `orthodontics-records`, `periodontal-charts`, `prevention-records`, `prosthodontics-records`, `surgeries` (+ `surgery-follow-ups`/`-images`/`-medications`), `treatment-plans`, `treatment-materials` | 1 read, 2 write (Phase B) |
| Dental charts (odontogram) | full REST `dental-charts` | 2 (needs the tooth-chart widget, see §4) |
| Patients | full REST `patients` | 2 |
| Appointments / Payments | full REST `appointments`, `payments` | 2 |
| Lookups | `GET /education-types`, `/stages`, `/departments` | 1 (dropdowns) |
| Academic sessions | full REST `academic-sessions` (`show` includes a `stats` block) | 3 |
| Case sheet types | full REST `case-sheet-types` (no `show`) | 3 |
| Groups | full REST `groups`, `/groups-available-doctors`, add/remove doctors | 3 |
| Doctors | full REST `doctors`, `/{id}/progress`, import/export/template | 3 |
| Clinic settings | `GET/PUT /clinic-settings` | 1 (read, for theme/branding), 3 (edit) |
| Backup | `GET/POST /backup`, `PUT /backup/auto` | 3 |
| Activity log | `GET /activity-logs` | 3 |
| Permissions | `GET/PUT /permissions/{user}` | 3 |
| TV board | `GET /tv-board` (public, no auth) | optional — kiosk/tablet use, not a phone feature |

## 6. Phase breakdown

**Phase 1 — Doctor core (read-first)**
- Auth (both login types), secure token storage, auto-logout on 401.
- A fixed light+dark app theme (originally clinic-settings-driven, redesigned
  to an Instagram-style identity — see §7).
- "My tasks" list (`/my-task-instances`, status filter/tabs).
- Task instance detail + QR: display own QR (`/task-instances/{id}/qr`),
  scan another (`/task-instances/scan`) — mirrors the web app's QR feature
  built this session (`SectionedForm.vue`'s QR modal).
- Case sheet **viewing** via `/case-sheet-prints/{resource}/{record}`
  (Phase A from §4) — read-only, but a doctor can review any sheet on
  their phone immediately.
- Profile screen (`/me`, photo via `image_picker` + existing doctor
  profile-photo upload endpoint).

**Phase 2 — Doctor editing**
- Backend: the one `case-sheet-forms` schema endpoint (§4, Phase B).
- `DynamicSectionForm` widget + the field-type widgets it needs
  (text/select/radio/checkboxes/textarea first; teeth-picker and the
  JSON-blob composite widgets — history/PMH/social-history/etc. from Oral
  Medicine, teeth-squares-grid and quadrant-repeater from Orthodontics —
  incrementally after).
- Dental chart (odontogram) as its own screen — genuinely a custom widget
  (tap-to-mark tooth surfaces), not expressible generically; port the same
  visual model as `ToothOdontogram.vue`.
- Create-new for the case sheets whose `store()` doesn't need a widget this
  app hasn't built yet (7 of 8 — see §9, "Case sheet create").
- Patients, appointments, payments CRUD — no longer a prerequisite for case
  sheet creation (an earlier version of this plan assumed it was; see §9)
  but still useful as their own standalone staff-facing modules later.

**Phase 3 — Admin (optional on mobile, API already exists for all of it)**
- Doctors management, groups, academic sessions, case sheet types.
- Permissions matrix (`/permissions/{user}`) — a genuinely awkward UI on a
  phone (11 modules × 4 permissions in the web version); consider whether
  this stays web-only even after Phase 3, and note that decision here
  rather than silently dropping it.
- Clinic settings edit, backup trigger/status.
- Activity log viewer.

**Not planned (explicitly, matching the web app's own documented gaps)**:
freehand canvas drawing (pain-diagram strokes, drawn signatures) and
offline-first sync — both out of scope on the web side too (see
`dental_laravel/README.md`), no reason to build them mobile-first.

## 7. Visual design — Instagram-style theme (2026-08-20)

Requested: redesign the app's colours, theme and shapes to match
Instagram's own design. Replaced the original clinic-settings-driven
palette (`ThemePalette.php`'s 4 themes, fetched at runtime so the mobile
app matched whatever theme the web dashboard had selected) with a fixed
light+dark identity modeled on Instagram's real, well-known UI colours —
a deliberate pivot, not an extension of the old system: the two designs
don't share a vocabulary (Instagram's isn't one of the 4 web palettes,
and doesn't have a "clinic sets it centrally" concept at all), so
`core/theme/app_theme.dart` was rewritten rather than adding a 5th
palette entry.

**Colours** (`InstagramColors`, each traced to a specific real Instagram UI
element, not derived from a seed): `#0095F6` action blue (buttons, links,
focus rings, selected chips — the same blue in both light and dark mode,
as in the real app), `#ED4956` error/red, true black `#000000` for the
dark-mode background (Instagram's dark mode is black, not dark grey),
`#262626` near-black body text in light mode, `#8E8E8E` secondary/muted
text in both modes, `#DBDBDB`/`#262626` hairline borders (light/dark).
`ColorScheme` is built by hand (not `ColorScheme.fromSeed`) so every token
maps to one of these real colours instead of an algorithmically-derived
shade that would drift from them. The brand gradient (`InstagramColors.
gradient`, the orange→pink→purple story-ring/wordmark colours) is defined
but not applied anywhere yet — kept for a future accent use (e.g. an
avatar ring), matching how sparingly the real app itself spends it rather
than making it a UI-wide colour.

**Shape**: flat, hairline-bordered cards (`elevation: 0` — Instagram's own
UI has no drop-shadow elevation anywhere), subtly rounded 8px corners on
buttons/fields/cards/chips (not Material's default pill shape), filled
input fields with a light/dark grey fill and no visible border until
focused (blue) or errored (red).

**Mode switching**: `MaterialApp.router` now sets both `theme:`
(`instagramLightTheme`) and `darkTheme:` (`instagramDarkTheme`) with
`themeMode: ThemeMode.system` — follows the OS/browser colour-scheme
preference, the same behaviour Instagram's own app has, replacing the
single `Provider<ThemeData>` that used to `watch` a fetched clinic
setting. `clinicSettingsProvider`/`ClinicSettingsRepository` are
unchanged and still fetch branding data (clinic name, logo) for later use
— only their theme-selection role was removed.

Verified visually via the same CDP-driven screenshot method as every
other slice: dark mode (this environment's default) confirmed clean on
both the login screen and the post-login task list/detail chrome — true
black background, Instagram-blue buttons and selected filter chips,
hairline-bordered flat cards, no elevation shadows anywhere. Light mode
was confirmed via `Emulation.setEmulatedMedia` — visible correctly
mid-transition (white background, blue button, light-grey bordered
fields) before the emulated override reverted to the environment's actual
dark preference, a CDP/canvaskit interaction rather than an app issue;
the theme construction itself is two straightforward, independently
correct `ThemeData` objects with no runtime branching to hide a bug in.
`flutter analyze`/`flutter test` clean.

## 8. Localization & RTL

Arabic is the primary language throughout the web app's UI text (this
plan's own screens should match: "تسجيل الدخول", "مهامي", etc.), English
secondary. `flutter_localizations` + `intl` are already in `pubspec.yaml`;
`MaterialApp.router` gets `locale: Locale('ar')` and Flutter's built-in RTL
handling takes care of directionality automatically for Material widgets.

## 9. What's already done vs. next action

Done (this session):
- [x] `flutter create` scaffold at `dental_laravel/flutter_app/`.
- [x] `pubspec.yaml` dependencies chosen and pinned (see table in §2).
- [x] `flutter pub get` — resolves clean, no version conflicts.
- [x] `flutter analyze` — no issues on the generated scaffold.

**Phase 1 items 1–4 — done (2026-08-20), verified against the live API**:
`core/config/app_config.dart`, `core/network/api_client.dart` +
`api_exception.dart`, `core/storage/token_storage.dart`, the full
`features/auth/` slice (both login types, session restore, logout),
`features/clinic_settings/` (theme fetch), `core/theme/app_theme.dart`
(mirrors `ThemePalette.php`'s 4 themes and "R G B" token format exactly),
`core/router/app_router.dart`, and a placeholder `features/home/`.
`flutter analyze` and `flutter test` both clean.

Verified live, not just compiled — `flutter run -d chrome` against the
real running Laravel API (XAMPP), driven via the Chrome DevTools Protocol
(mouse/keyboard input + screenshots, since this environment has no GUI
interaction): doctor login (a test account created via
`php artisan tinker`, since none is seeded) → home screen shows the real
`name`/`accountType` from the API response; staff login
(`admin@clinic.test`) → home shows `full_name`; logout → returns to
`/login` and does not auto-restore the session on reload (token actually
cleared); a wrong password shows the API's real per-field validation
message inline under the credential field, not a snackbar. Also confirmed
the built Windows exe launches without crashing and the Android
cleartext-traffic exception is in place (untested on an actual emulator —
none was available in this environment).

**A real bug found and fixed during this verification**: the first version
of `routerProvider` was `Provider<GoRouter>((ref) { ref.watch(authControllerProvider); return GoRouter(...); })`
— watching the auth state directly, which rebuilds the *entire* `GoRouter`
(and every screen it holds) on every auth-state transition. This is
individually harmless-looking but breaks the one path where it fires most
often: a **failed login**. `AuthController` transitions
Unauthenticated → loading → error on every wrong-password attempt, which
was tearing down `LoginScreen`'s own `State` mid-flight — wiping both the
credentials the user had just typed and the inline validation error the
screen was in the middle of displaying (confirmed via screenshot: fields
went blank, no error shown, right after a failed submit). Fixed by
bridging Riverpod to go_router's `refreshListenable` instead (see the
`_AuthRefreshListenable` class in `app_router.dart`) — `redirect()` still
re-evaluates on every auth change, but `GoRouter` itself, and therefore
`LoginScreen`'s state, now survives the transition. Re-verified via the
same CDP-driven wrong-password flow: credentials and the inline error now
both stay visible correctly, and a full login/logout regression pass
confirmed nothing else broke.

**Phase 1 item 5 — done (2026-08-20), verified against the live API**:
`features/task_instances/` — "مهامي" (My Tasks) list with status filter
chips (all/pending/assigned/completed), a detail screen (department, case
sheet type, assigned/completion dates, grade, notes), status-update chips,
the task instance's own QR code, and a camera-based QR scan screen
(`mobile_scanner`) that resolves a scanned code via `POST
/task-instances/scan` and opens that instance's detail directly.
`HomeScreen` now branches on account type: a doctor's home *is*
`TaskListScreen` (since `/my-task-instances` is doctor-only server-side —
a staff token 403s it); staff still get the Phase-1 placeholder pending
Phase 3's admin screens. New `core/network/paginated.dart` — a generic
`Paginated<T>` wrapper for Laravel's `->paginate()->response()` envelope,
reusable by every future paginated list (patients, appointments, …), not
task instances alone. Android `CAMERA` permission +
`network_security_config` and iOS `NSCameraUsageDescription` added for the
scanner. `flutter analyze`/`flutter test` clean.

**A real, small backend gap found and fixed while grounding this feature**:
`TaskInstanceController::mine()`/`show()` already eager-load
`task.department` and `task.caseSheetType` — clearly *for* the mobile task
list, which needs to show which department/sheet a task belongs to — but
`App\Http\Resources\TaskInstanceResource`'s nested `task` array only ever
returned `{id, title}`, silently dropping both. Fixed additively (two new
optional keys, `relationLoaded()`-guarded so a caller that doesn't
eager-load them just doesn't get the keys, no other endpoint affected).

Verified live end-to-end via the same CDP-driven flow as the auth slice,
against a real task instance created via tinker for the test doctor
(`task_instances.id=382`, a real seeded `Task` — "كيس شيت" / "operative
dent" department): task list loads and shows the real title, department,
assigned date and status badge; opening it shows the full detail
including the correct Arabic case-sheet-type name ("ترميمية"); the QR
section fetches and renders a real PNG (bearer-token-gated bytes via
`ApiClient.getBytes`, not a plain `Image.network`); tapping "مكتملة"
(Completed) issues the real `PUT`, and the response's server-computed
`completion_date` (auto-stamped by `TaskInstanceController::update()`)
appears in the detail view immediately, with the list screen reflecting
the new status badge on return — confirming `invalidateTaskInstance()`'s
list+detail cache invalidation works correctly. QR *scanning* (camera
input) was not exercised in this pass — this environment's Chrome instance
has no camera device to feed `mobile_scanner`; the `scan()` API
round-trip itself was separately confirmed via curl (§ above, before this
slice).

**Phase 2 item 6 — the gating step — done (2026-08-20), verified live**:
the `/api/v1/case-sheet-forms` schema endpoint (built server-side this
pass — see `dental_laravel/README.md` "Case-sheet form schema endpoint")
and `features/case_sheet_forms/` — `DynamicSectionForm`, one widget
rendering any of the 8 case sheets from its schema, plus the entry-point
screens (`CaseSheetTypesScreen` → `CaseSheetRecordListScreen` →
`CaseSheetFormScreen`), reachable from a doctor's home app bar. Supports
text/textarea/number/decimal/date/time/select/radio/checkboxes/boolean/
`teeth` (as a plain comma-list field, not the original's visual FDI-cross
picker — that and the JSON-blob composite types, e.g. `history_complaint`
or `quadrant_repeater`, render a "not supported yet" placeholder with the
raw value visible instead of an editable control). New
`core/network/paginated.dart` (a generic `Paginated<T>` wrapper, reused by
the record-list screen). Scoped to **editing an existing record only** at
the time — `doctor_id` is required by every one of these 8 REST `store()`
endpoints and isn't in any `sections()` layout, so a "create new" screen
needed it from somewhere; the assumption at the time was that this
required a patient-picker backed by a whole Patients CRUD module (Phase 2
item 8, as originally scoped). That assumption turned out to be wrong for
`doctor_id` specifically (it's just the logged-in doctor, no picker
needed) and only partly right about `patient_id` (see "Case sheet create"
in §9 — corrected once actually verified against the code, not left
standing). Every one of these 8 controllers' `update()` validates with
`sometimes`, so a payload carrying only the `sections()` fields is always
a valid partial update — confirmed, not assumed (see the bug below).

**Group-preserving submit, not a naive rebuild**: for a JSON-blob column
with mixed supported/unsupported subkeys (Orthodontics'
`examination_data` has ~40 scalar/array subkeys this form edits, plus
`teeth_squares_grid` and two `quadrant_repeater`s it doesn't yet),
`buildSubmitPayload()` starts each group from a **copy of its original
decoded object** and only overwrites the subkeys backed by a supported
field — an unsupported subkey inside the same blob survives a save
untouched instead of being silently dropped because nothing in the UI
edited it. Verified directly, not just by design: saved a real
Orthodontics record after editing only its `diagnosis` textarea, then
confirmed via the API that the edit persisted **and** that two marker
strings buried inside the unsupported `treatment_stages`/
`appliance_designs` subkeys were still present afterward.

**A serious bug found via this live save — not code review, not a unit
test**: the very first save attempt failed with *"The patient sex field
must be a string"* on a field (`patient_sex: ""`) the form was sending
correctly. Root cause and fix live entirely server-side — see
`dental_laravel/README.md` "Case-sheet form schema endpoint" for the full
account: 11 API controllers' partial-update validation was unconditionally
overwriting each rule's first element with `'sometimes'`, silently
deleting `nullable` wherever it was present; combined with Laravel's
global `ConvertEmptyStringsToNull` middleware turning the empty string
into `null` before validation, any correctly-empty optional field failed.
Reproduced independent of Flutter with a bare `curl` request before
fixing, confirmed fixed the same way, then re-verified end-to-end through
the actual Flutter save button. This bug predates the Flutter work
entirely and would have affected the web app's own edit flows too, had
any of them gone through these specific 11 API endpoints rather than the
Inertia web controllers (which don't share this partial-update code path)
— caught here only because this was the first thing to actually exercise
a `PUT` with a blank optional field against them.

Verified live end-to-end (Chrome, CDP-driven, same method as the auth and
tasks slices): opened a real seeded Orthodontics record — every field type
rendered its real data correctly (multi-select checkboxes reflecting
several real selections at once, single-select radios, `teeth`-type
quadrant-code text fields, populated textareas); unsupported composite
fields (`teeth_squares_grid`, `quadrant_repeater`) showed the "not
supported yet" placeholder with real raw data visible, not a crash or
silent blank; edited and saved successfully after the bug fix, confirmed
both the edit and the untouched unsupported data via a follow-up API call.
Test data (a temporarily reassigned real record, `id=10`) restored to its
original owner and field values afterward.

**Phase 2 item 7 — done (2026-08-20), verified live**: the dental chart
(odontogram) — `features/dental_chart/`, wired into `DynamicSectionForm` as
the `dental_chart` field type (`OperativeForm`'s `tooth_data` field on the
`dental-charts` resource). Ported directly from
`resources/js/Components/ToothOdontogram.vue` (394 lines, read in full
before writing any Dart), not guessed:
- `domain/tooth_entry.dart` — `ToothEntry`/`ToothSurface`, matching the
  original's sparse-storage model exactly: only teeth with a non-default
  status/notes/surface appear in `tooth_data` at all.
- `domain/odontogram_vocabulary.dart` — the tooth-status (6), surface-status
  (5) and root-status (4) vocab, tooth-level fill/opacity overrides, and
  the FDI arch arrays, copied 1:1 from the Vue file's own constants so a
  chart round-trips identically between the web app and this one.
- `presentation/tooth_flower_painter.dart` — a `CustomPainter` porting the
  original's 5-polygon "flower" SVG icon (`SURFACE_POINTS`, the exact 0–30
  viewBox coordinates) plus its overlay marks (red X for extracted, orange
  ring for retained-root, black ring for crown), with a `hitTestSurface()`
  static helper so the modal's large preview can be tapped to highlight a
  surface.
- `presentation/tooth_odontogram_field.dart` — the interactive widget: two
  horizontally-scrollable arch rows of 16 tooth buttons each (matching the
  original's UPPER/LOWER layout and FDI ordering), a tap-opens a bottom
  sheet with a large live preview, 6 tooth-status chips, 5 surface-status
  rows (or 3 root-status rows once a tooth is marked non-vital — the
  flower icon itself always keeps its 5 polygon slots; roots are tracked
  separately and, matching the original exactly, are never given their own
  visual distinction on the icon), a treatment-status selector, and notes.
- `CaseSheetField.isSupported` extended with `'dental_chart'`;
  `DynamicSectionForm._coerce()` passes the field through as a real
  `List<dynamic>` (the API's `tooth_data` column is Eloquent-array-cast,
  arriving/departing as native JSON — no manual encode/decode needed,
  unlike the grouped-JSON-blob fields).

**Two real bugs found during live verification, both fixed**:

1. **`polygons` arrives as `[]` for an untouched tooth, not `{}`** — PHP's
   `json_encode` renders an empty associative array as a JSON array, so a
   real record's tooth entries (`GET /dental-charts/74`) came back with
   `"polygons": []` wherever nothing had been marked. `ToothEntry.fromJson`
   originally cast `json['polygons'] as Map<String, dynamic>?`, which
   throws on a `List`. Fixed with a small `_decodePolygons()` helper that
   only decodes when the value actually is a `Map`, otherwise returns `{}`
   — found by fetching a real record via `curl` before writing any UI code
   (the "no guessing" habit paid off here; a synthetic test fixture would
   likely have used `{}` and hidden this).
2. **`ToothFlowerPainter.shouldRepaint` silently dropped surface-colour
   updates.** The painter's `fillFor` parameter is a closure (it looks up
   per-surface colour from whichever `ToothEntry` is current); the first
   version of `shouldRepaint` compared every *other* field but not
   `fillFor` itself (closures aren't meaningfully comparable, which is
   exactly why it was left out) — so when only a surface's status changed,
   `shouldRepaint` returned `false` and Flutter's `RenderCustomPaint` kept
   the stale cached layer. Found live, not by inspection: tapping "تسوس"
   (cavity) on a tooth's top surface correctly updated the choice-chip and
   the small grid-button icon (a fresh `CustomPaint` each rebuild) but the
   large 140×140 modal preview stayed blank white. Fixed by making
   `shouldRepaint` unconditionally return `true` — these are a handful of
   tiny polygons repainted only on an actual `setState`, so the cost is
   negligible and there's no correct closure-based alternative. Re-verified
   the same interaction afterward: the preview's top triangle now turns
   amber immediately, confirmed across cavity (amber), non-vital
   (tooth-wide dark red + root-status rows swapping in), and extracted
   (grey fill + red X overlay) transitions, both in the modal preview and
   the outer grid button.

**A third, pre-existing, unrelated bug surfaced by the same verification**
(found, documented, deliberately **not** fixed this pass — see
`dental_laravel/README.md`, "`dental_charts.visit_date` defaults to
`current_timestamp()` at the MySQL level"): a brand-new `dental_charts` row
created with no `visit_date` shows `null` in the immediate create response
but `current_timestamp()` on every subsequent fetch, because the column
itself carries a MySQL-level `DEFAULT current_timestamp()` inherited from
the original `clinic_system2` schema — nothing to do with Flutter, the API
layer, or `DynamicSectionForm`'s date handling (a second field on the same
form, `treatment_plan_date`, has no such default and correctly stays blank
throughout). Flagged rather than silently altered because changing a
production table's column default is a schema-level decision outside a
mobile-feature pass's scope.

Verified live end-to-end via the established CDP-driven Chrome method
against real `dental_charts` records created via the API for this pass
(ids 88 and 89, both doctor-owned by a tinker-seeded test doctor, both
deleted afterward via `DELETE /dental-charts/{id}` and confirmed `204`):
patient-info section, the odontogram grid (both arches, correct FDI
order), the legend, the `teeth`-type quick-list fields, tooth-editor sheet
open/close, tooth-status switching (present → non-vital → extracted, with
each one's distinct visual: green check / dark-red fill / grey fill + red
X), surface-status editing with live-updating preview (post-fix),
non-vital's root-status rows replacing surface rows, notes and
treatment-status controls, closing the sheet, and a full form save —
confirmed via a follow-up `GET` that the exact edited `tooth_data` entry
(`number: "16"`, `toothStatus: "extracted"`, `polygons.top.status:
"cavity"`, everything else left at its default) round-tripped correctly.
`flutter analyze`/`flutter test` clean.

**Phase 2 item 8 — done (2026-08-21) for 7 of 8 resources, verified
live**: "create new case sheet". Before writing any code, re-checked the
premise this item was originally scoped under (§4/§6 above both said
"create new" needed Patients CRUD as a prerequisite) directly against
every one of the 8 API controllers' `validateRecord()`, rather than
building 3 CRUD modules on an unverified assumption — per the standing
"no guessing" rule, an assumption from an earlier session is still a
guess until it's re-checked against the current code. What that check
found:

- `doctor_id` is `required` on every one of the 8 `store()` endpoints and
  has no `sections()` entry at all — but it's simply the logged-in
  doctor's own id, no picker needed. `CaseSheetFormScreen` now reads it
  from `authControllerProvider` and injects it before every create `POST`,
  never shown as a field (this screen is only reachable from a doctor's
  own nav to begin with).
- `patient_id`/`patient_name` turned out to be **three different
  arrangements**, not one, discovered by reading each of the 8
  controllers' rules rather than assuming they matched:
  - 6 resources (`dental-charts`, `oral-medicine-charts`,
    `orthodontics-records`, `prevention-records`,
    `complete-denture-records`, `prosthodontics-records`) treat patient
    identity as a plain typed string, already a normal `sections()` field
    `DynamicSectionForm` handles today — nothing to build.
  - `surgeries` and `periodontal-charts` both store `patient_id` as a real
    `patients` table FK (an `integer`, `required`, absent from
    `sections()`) while their `sections()` layout only ever collects a
    `patient_name` (+ `patient_phone`) text field — a real gap. The **web**
    controllers for both already close this gap with a
    `resolvePatientId()` helper (find-or-create a `Patient` by
    name+phone), but only on the web side; the **API** controllers had no
    equivalent — `Api\SurgeryController::store()` would 422 on `patient_id`
    for literally any client that only ever collects a name, Flutter or
    otherwise. Fixed by porting `resolvePatientId()` into
    `Api\SurgeryController` verbatim (see `dental_laravel/README.md`,
    "Case sheet create — the real blocker was `patient_id`, not a Patients
    CRUD screen").
  - `periodontal-charts` additionally hard-requires `chart_data` (the
    per-tooth perio chart widget, `PerioChart.vue` on the web side) with
    no `sections()` entry — a genuinely unbuilt widget, not a form-wiring
    gap `resolvePatientId()` or a doctor_id default could close. Left out
    of create for now; `kCaseSheetCreatableResources` documents exactly
    why inline.
- `dental-charts` needs one more resource-specific default,
  `chart_type: 'permanent'` — the ported layout only ever exposes that one
  option (per the web controller's own doc comment), so it's injected the
  same way as `doctor_id` rather than shown as a picker with one choice.

Built: `CaseSheetRecordRepository.create()`; `CaseSheetFormScreen` now
handles `recordId == null` as create mode (empty starting record, `POST`
instead of `PUT`, navigates to the new record's edit view on success
instead of back to the list); `kCaseSheetCreatableResources` and
`caseSheetCreateDefaults()` in `case_sheet_form_schema.dart`; a `+` FAB on
`CaseSheetRecordListScreen`, shown only for the 7 creatable resources; a
new `/case-sheets/:resource/new` route. Also fixed, while in this screen:
the record-list and form app bars were showing the raw resource slug
(`"dental-charts"`) instead of the schema's real title — now use
`caseSheetFormSchemaProvider(resource)`'s `.title`, same source the form
screen already used.

Verified live end-to-end via the established CDP-driven Chrome method:
opened `surgeries` (empty for the test doctor), confirmed the `+` FAB
appears (and, separately, confirmed by code review that it's absent for
`periodontal-charts`), opened the blank create form, typed only a patient
name, saved, and confirmed via a follow-up `GET /surgeries` that the new
record carried the correct auto-filled `doctor_id` **and** a freshly
resolved `patient_id` pointing at a real, newly-created `Patient` row
matching the typed name — proving the `resolvePatientId()` port actually
works end-to-end through the API, not just against a unit test. The
in-app success snackbar and post-create navigation to the new record's own
edit view (re-fetched from the server, not just the locally-held form
state) were both confirmed on screen. Test record and its resolved
`Patient` row deleted afterward. `flutter analyze`/`flutter test` clean.

**Phase 3 item — done (2026-08-21), staff-only "records" module**:
patients/appointments/payments CRUD (`features/records/`), reachable from
staff's home screen (`/records` — the folder icon in the app bar, and a
button on the placeholder body). Genuinely staff-only, not a scope choice:
`patients` is `permission:patients,*`-gated server-side, which
`EnsureUserHasPermission` denies to a Doctor token outright (same
mechanism as `doctors` CRUD), so this whole feature is unreachable from a
doctor session by construction, not just by nav-icon convention like the
rest of Phase 3.

- `Patient` (name, phone, stage — a `/stages` dropdown; the treating
  `Doctor` field was deliberately left out of the form, `nullable` server-
  side and with no lightweight lookup endpoint to populate a picker from,
  unlike `stage_id` — deferred rather than built as a heavy admin-resource
  picker for a rarely-set field).
- `Appointment` (full name, a patient picker reusing `PatientListScreen`
  in a new `pickMode` rather than building a second list, a `/tasks`
  dropdown, date, two boolean switches). `doctor_id` here is genuinely
  `users.id` (staff), not `doctors.id` — a confirmed FK oddity in the
  source schema (`App\Models\Appointment`'s own doc comment) — silently
  filled with the logged-in staff user's own id, same auto-fill precedent
  as case-sheet creation's `doctor_id`, since there's no `/users` list
  endpoint in this API to build a real picker from (the web app's own
  form builds that dropdown straight from `User::all()` inside the
  Inertia controller — no API equivalent exists or was needed there).
- `Payment` (an appointment picker reusing `AppointmentListScreen`'s own
  new `pickMode`, amount, paid-by, paid-at).
- `RecordsRepository.tasks()` fetches every page rather than trusting a
  `per_page` override: `Api\TaskController::index()` hardcodes
  `paginate(15)`, ignoring any `per_page` query param — with 16 real task
  rows in this database, trusting the override would have silently
  dropped the 16th from the dropdown.

Verified live via the established CDP-driven Chrome method, logged in as
`admin@clinic.test` (staff): created a `Patient` end-to-end (form → save →
confirmed via `GET /patients?search=`); created an `Appointment` using the
in-app patient picker to select that same patient, a real task from the
dropdown, and a date, then confirmed via the API that `doctor_id` was
correctly auto-filled with the logged-in staff user's own id (`8`, not a
`Doctor` id); created a `Payment` using the in-app appointment picker,
confirmed linked to the right appointment. All three test records (and
the payment's `paid_at`, see below) deleted afterward.

**A CDP-testing-harness artifact, not an app bug — worth recording so a
future debugging pass doesn't chase it**: driving the app via a raw
`Page.navigate` to a same-origin `#/...` hash URL (this session's usual
shortcut for jumping straight to a route instead of tapping through) threw
`Bad state: Future already completed` immediately after leaving the
Appointment form via `Navigator.pop()`, then cascaded into a duplicate-
`GlobalKey` crash on the next hash jump — a corrupted `Navigator` state
that persisted until the whole `flutter run` process was restarted. Retried
the identical flow (Payments create, including its own appointment picker)
using **only** in-app taps end-to-end on a fresh app instance and it
worked cleanly with no crash — isolating the cause to `Page.navigate`
racing an in-flight `Navigator.pop()` transition (CDP forcing a same-
document navigation mid-animation), not to `PaymentFormScreen` or any
picker code. Confirmed, not assumed, by reproducing the working path
before writing this note.

**A third confirmed instance of the `current_timestamp()`-default MySQL
bug** (see `dental_laravel/README.md`, "`dental_charts.visit_date`
defaults to `current_timestamp()` at the MySQL level"): the test
`Payment` was saved with its "تاريخ الدفع" (paid-at) field left blank,
and came back from the API with a real timestamp instead of `null` —
same schema-level pattern as `visit_date`, on a different table
(`payments.paid_at`), not a new bug requiring its own investigation.

**Phase 2 item 10 — done (2026-08-21), periodontal chart create unblocked**:
ported `Components/PerioChart.vue` — the last thing standing between
`periodontal-charts` and the other 7 case-sheet resources getting a
working "create new" flow (see `kCaseSheetCreatableResources`, now
covering all 8). Two new domain classes,
`PerioChartGroupSchema`/`PerioChartTableSchema` (parsing the
`chartGroups`/`chartField` the schema endpoint already returned but
`CaseSheetFormSchema.fromJson` used to just drop), and
`features/perio_chart/presentation/` — `PerioChartTable` (one 32-tooth
BOP/PPD/CAL grid, a faithful port of the Vue component's per-tooth-block
layout: buccal row, tooth-number row, palatal/lingual row per arch, in
the same anatomical order the original uses) and `PerioChartGroupsField`
(renders every `chartGroups` entry — "Initial", "After Hygiene Phase",
"Follow-up", 8 tables total across the three — each as a collapsible
`ExpansionTile`, a deliberate mobile-screen adaptation since the web page
shows all of them open at once and 8 full tables stacked open on a phone
would be unusable). Wired into `DynamicSectionForm`: seeded from
`record[chartField]` (a JSON *string* column, unlike the dental chart's
array-cast `tooth_data` — decoded/encoded manually), rendered after every
`sections()` card since chart groups aren't `sections()` fields at all,
and serialized back as `{teeth: {}, ...groups}` on submit (the `teeth`
placeholder matches what the original web app always emits too, so a
chart saved here parses identically in the original PHP app). Backend:
ported `resolvePatientId()` into `Api\PeriodontalChartController` —
identical gap and identical fix to `Api\SurgeryController`'s (see "Case
sheet create" above) — and relaxed its `patient_id` rule from `required`
to `nullable` since it's resolved server-side now.

**Two real bugs found during live verification, both fixed**:

1. **BOP cells were invisible** — `_cell`'s unmarked state used
   `Theme.of(context).colorScheme.surface` with no border, which in this
   app's dark Instagram theme is the same near-black as the page behind
   it, so an empty BOP grid looked like blank space (PPD/CAL cells were
   fine — `TextFormField`'s `OutlineInputBorder` always draws a visible
   line regardless of fill colour). Found live: expanded a group and saw
   tooth numbers with nothing between them where the tap targets should
   be. Fixed by wrapping each BOP cell in a `Container` with an explicit
   `colorScheme.outline` border, matching PPD/CAL's visible-by-default
   cells. Re-verified: cells render with visible borders and tapping one
   turns it red with a `+` mark, same as the original's own bleeding
   toggle.
2. **The entire chart mirrored under the app's Arabic (RTL) locale** — a
   real, verified-by-data bug, not cosmetic: saving a tap on what looked
   like tooth 24's *first* site (the array's index 0) came back from the
   API as `"24":{"buccal":["","","+"]}` — index **2**, not 0. Root cause:
   neither `PerioChartTable`'s per-arch `Row`s nor
   `ToothOdontogramField`'s arch rows (the dental chart odontogram, built
   in an earlier pass — the identical bug, just never caught there since
   nobody had compared exact array positions before) ever set an explicit
   `Directionality`, so the app's ambient `Locale('ar')` → RTL silently
   reversed both the tooth order (18→28 displayed as 24→18→...→28, wildly
   out of order — not even a clean mirror, since FDI numbering itself
   isn't symmetric) and the 3-site sub-row within each tooth. FDI tooth
   order and mesial/distal site order are a fixed anatomical reading that
   must never flip with UI language — a genuinely dangerous bug for real
   clinical use, not just a display quirk, since a doctor tapping what
   they see as tooth 18 could have silently recorded data against tooth
   17, 21, or any other tooth depending on screen position. Fixed by
   wrapping each arch's `Row` (both files) in `Directionality(textDirection:
   TextDirection.ltr, ...)` — dental charts read left-to-right by fixed
   convention regardless of the surrounding UI's language. Re-verified
   thoroughly: both tables now read `18, 17, ..., 11, 21, ..., 28` and `48,
   ..., 41, 31, ..., 38` correctly; re-tapped the visually-first BOP site
   and confirmed via the API it now lands at array index 0, not 2; spot-
   checked the dental chart odontogram screen (a real record, not just the
   new perio chart) and confirmed its arch rows read correctly too.

Verified live end-to-end via the established CDP-driven Chrome method:
created a periodontal chart with only a patient name (no `patient_id`)
and confirmed it resolved to a real `Patient` row via the ported
`resolvePatientId()`; expanded "Periodontal Chart — Initial"; toggled a
BOP site and entered a PPD value; saved; confirmed via a follow-up API
call that `chart_data` held both values at their correct tooth number
*and* array position. Test record and its resolved `Patient` row deleted
afterward. `flutter analyze`/`flutter test` clean.

**Phase 3 — done (2026-08-21), first slice: doctors, tasks, education
types/stages/departments**. Requested explicitly mid-pass ("لاتنسى اضافة
انواع التعليم المراحل الاقسام المهام" — don't forget education types,
stages, departments, tasks) after doctors management was already under
way; folded in as the same pass rather than a separate one since all five
share the staff-only admin surface and several of the same lookups.

- **New `/admin` hub** (`features/admin/`) — staff-only, distinct from
  `/records` (`RecordsHubScreen` is front-desk operations; this is system
  administration), reachable from a second app-bar icon and a second
  button on staff's home placeholder.
- **Doctors** (`features/doctors_admin/`) — full CRUD against `/doctors`
  (name, username, email, phone, education-type/stage dropdowns,
  password — required on create, optional-blank-means-unchanged on edit,
  matching `Api\DoctorController::validateDoctor()` exactly). Profile-
  image upload deliberately **not** wired up: it's the one multipart field
  this resource accepts, and grepping the codebase first confirmed the
  "photo via `image_picker`" line in this README's own original Phase 1
  plan was never actually built — nothing to model a
  multipart/`_method`-spoofing flow on yet, so it's left as a real,
  explicit gap rather than guessed at.
- **Tasks** (`features/tasks_admin/`) — full CRUD against `/tasks`
  (`permission:tasks,*`, already existed), department/stage/case-sheet-
  type dropdowns plus required-per-doctor/required-count/grade/notes.
- **Education types, stages, departments** (`features/taxonomy_admin/`) —
  one shared `TaxonomyListScreen`/dialog-based form for all three rather
  than three near-duplicate screens, since the only real difference
  between them is which optional parent FK each carries (education types:
  none; stages: `education_type_id`; departments: both). Create/edit
  happens in an `AlertDialog`, not a separate route — each item is just a
  name and up to two dropdowns, too little content to justify a full-
  screen form.
- **A real, scoped backend gap, found and closed**: these three had only
  ever been *read*-only in the API (`Api\LookupController`, "Managed via
  the web admin UI, not writable here" — true until this pass).
  `LookupController` gained `store*`/`update*`/`destroy*` methods, a
  straight port of `EducationTypeController`/`StageController`/
  `DepartmentController`'s own web validation, and `routes/api.php` gates
  them identically to their web counterparts: `role:super_admin,admin`
  for education types (the web route carries no separate permission
  layer, confirmed by reading it rather than assumed), that plus
  `permission:stages,*`/`permission:departments,*` for the other two.
  Verified via `curl` as staff (create/update/delete all 201/200/204) and
  again with a Doctor token (403, confirming `role:` correctly denies a
  non-`User` principal even though `EnsureUserHasRole` doesn't
  `instanceof`-check the way `EnsureUserHasPermission` does — it just
  reads `$user->role`, which is `null` on a `Doctor` model and fails the
  `in_array` check safely).
- **A repository consolidation**: `core/data/lookup_repository.dart` — a
  shared `LookupRepository`/`LookupItem` for every read-only reference-
  data fetch (`education-types`, `stages`, `departments`, `case-sheet-
  types`, `tasks`), replacing what had become duplicated `stages()`/
  `tasks()` methods on `RecordsRepository` and `DoctorsAdminRepository`
  once a 3rd and 4th consumer needed the same data — not a
  speculative abstraction, a cleanup done only once actual reuse (not
  hypothetical reuse) had already happened twice over.

Verified live end-to-end via the established CDP-driven Chrome method,
logged in as staff: created and deleted an education type (confirmed the
list view's async refetch after delete — briefly looked stale in one
screenshot, resolved on the next, not a bug); created a stage with its
education-type dropdown and a department with *both* its dropdowns,
confirming the shared form's conditional-field logic renders correctly
for every combination; created a task exercising all three of its
dropdowns (department/stage/case-sheet-type) and its numeric fields;
created a doctor exercising both of its dropdowns and the password field.
Every create was confirmed server-side via `tinker`/`curl` before being
deleted. `flutter analyze`/`flutter test` clean throughout.

**Phase 3 item — done (2026-08-21), Groups admin**. Next item after
doctors/tasks/taxonomy in the tracked Phase 3 sequence.

- **New `features/groups_admin/`** — full CRUD against `/groups`
  (`Api\GroupController`, no dedicated Resource class server-side — it
  returns plain JSON via `response()->json(...)`, matching
  `LookupController`'s own convention rather than the `{data: ...}`
  envelope most of the rest of the API uses; the Flutter models parse that
  shape directly, no unwrapping needed).
- **Weekly slots**: each group carries a list of recurring `{day,
  start_time, end_time}` rows. `day` must be one of exactly 5 Arabic
  weekday strings, read directly from `resources/js/Pages/Groups/Index.vue`'s
  own `DAYS` constant (`الأحد`–`الخميس`, Sunday–Thursday — the regional
  work week) rather than translated/reformatted, since the column stores
  the string verbatim. The form's slot editor (`_SlotRow`) uses a day
  dropdown plus two `showTimePicker`-backed buttons per row.
- **Member management**: `GroupDetailScreen` lists current doctors with a
  per-row remove (`X` icon, `DELETE /groups/{id}/doctors` with a
  `doctor_ids` body — required extending `ApiClient.deleteJson()` with an
  optional `body` param, since `Dio.delete()` doesn't send one by
  default), and a FAB opening an "add doctors" dialog backed by
  `GET /groups/{id}/available-doctors?stage_id=`. "Available" means not
  already in a group for the group's academic session (matches
  `GroupController::availableDoctors()`'s own doc comment, confirmed via
  curl — doctors are correctly filtered by both session and stage).
- **routes/api.php note**: none of the `groups` routes carry any
  `role:`/`permission:` gate — pre-existing, confirmed by reading the
  route file, out of scope for this pass (not something this pass
  introduced or should silently "fix").

Verified live end-to-end via CDP-driven Chrome, logged in as staff:
created a test group with one weekly slot; discovered its initial stage
had zero available doctors, edited the stage to one that did (confirmed
via `tinker`), reopened the add-doctors dialog and confirmed the doctor
list updated accordingly; added a doctor, confirmed server-side via
`tinker` (`Group::doctors()` showed the new row); removed the same doctor
via the `X` icon, confirmed server-side (`doctors()->count()` back to 0).
Test group deleted and both test tokens revoked afterward.
`flutter analyze` clean. One non-bug noted during testing: after creating
"CDP Group Test," the first list screenshot appeared to be missing it —
it was actually present, just sorted alphabetically first (uppercase
Latin sorts before lowercase/Arabic under the DB's collation) and off the
visible scroll position, not a data or refresh bug.

**Phase 3 item — done (2026-08-21), Academic sessions admin**. Next item
after Groups in the tracked Phase 3 sequence.

- **One small backend addition**: `Api\AcademicSessionController` already
  had full CRUD (`index`/`show` with live stats/`store`/`update`/
  `destroy`) — read in full before building against it, not assumed —
  but was missing `setCurrent`, present on the web controller
  (`PUT /academic-sessions/{id}/set-current`) with no API equivalent.
  Ported directly (same transaction: clear every session's `is_current`,
  then set this one `is_current` + `is_active`), and added the matching
  `routes/api.php` route. The web controller's `select()` (which session
  a *browser* session is currently "viewing") was deliberately **not**
  ported — Sanctum is stateless, so it has no equivalent, matching
  `Api\AcademicSessionController`'s own pre-existing docblock ("No
  'selected session' concept here"). Confirmed via `curl`: no
  `role:`/`permission:` gate on any `academic-sessions` route, matching
  both the web route (also ungated beyond the outer staff-auth group) and
  the same pre-existing pattern already noted for `groups`.
- **New `features/academic_sessions_admin/`** — list (name, date range,
  groups/tasks counts, current/active/inactive status chip), create/edit
  form (name, start/end date via `showDatePicker`, active/current
  checkboxes — mirrors `AcademicSessions/Index.vue`'s modal form exactly),
  and a detail screen showing the five live stats
  (`doctors`/`groups`/`required_tasks`/`done_tasks`/`remaining_tasks`
  from `show()`) plus a "set current" action. Delete and "set current"
  are hidden for the already-current session, matching the web UI's own
  `v-if="!session.is_current"` guards.

Verified live end-to-end via CDP-driven Chrome, logged in as staff:
created a test session with a date range; set it current, confirmed
server-side via `tinker`, then reverted the real current session back via
`curl` (a live teaching clinic can only sensibly have one "current"
session, so this couldn't be left pointed at test data); deleted the test
session, confirmed gone via `tinker`. One non-bug hit twice during
testing, both instances consistent with Riverpod's documented
`autoDispose` behavior rather than a real staleness bug: (1) after the
`curl` revert changed which session was current, quickly popping and
re-pushing the list/detail routes in-app kept showing the pre-revert
state — `autoDispose` reuses a provider's cached value when a new
listener attaches before its dispose timer fires, so a fast
pop-then-push doesn't force a refetch; a full page reload confirmed the
real state was correct all along. (2) the standard post-delete
one-frame-stale screenshot already documented for education types
recurred identically here. `flutter analyze` clean throughout; the
Flutter session's own token and the `curl` test token were both revoked
afterward.

**Phase 3 item — done (2026-08-21), Case sheet types admin**. Next item
after Academic sessions in the tracked Phase 3 sequence.

- No backend changes needed — `Api\CaseSheetTypeController` already had
  full CRUD (`index` with `tasks_count`/`store`/`update`/`destroy`,
  `destroy` blocked with a 422 when any task still references the type),
  read in full before building against it. `icon`/`color`/`page_url`
  are deliberately not exposed in the new Flutter form either — the web
  form (`CaseSheetTypes/Index.vue`) never surfaces them, the controller
  just defaults `icon`/`color` on create and never touches `page_url` —
  matching that scope rather than adding fields the web admin itself
  doesn't manage.
- **New `features/case_sheet_types_admin/`** — list (name pair, code,
  task count, active/inactive chip) plus an `AlertDialog` create/edit
  form: `type_code` (create-only, shown read-only on edit, same
  `^[a-z0-9_]+$` validation as the server), `name_ar`, `name_en`,
  `description`, `is_active`. Dialog-based rather than a full route,
  same "too little content for a separate screen" call already made for
  taxonomy admin. Distinct from `LookupRepository.caseSheetTypes()`
  (same endpoint, but read-only, used elsewhere for the tasks-admin
  dropdown) — this repository owns the write side.

Verified live end-to-end via CDP-driven Chrome, logged in as staff:
created a test type with all fields, confirmed via `tinker`; edited it
(toggled `is_active` off), confirmed via `tinker`; deleted it, confirmed
gone via `tinker`. One layout quirk hit and worked around, not a bug in
the feature itself: with exactly 9 rows the last row's trailing icons sat
directly under the screen's fixed `FloatingActionButton` (Scaffold
doesn't reserve body space for a FAB by default), briefly blocking taps
on that row — resized the CDP browser viewport taller to clear it rather
than changing the widget, since every other list in the app has the same
FAB-over-scrollable-content structure and this only matters when a list
under test happens to end exactly at the FAB's screen position.
`flutter analyze` clean throughout; both test tokens revoked afterward.

**Phase 3 item — done (2026-08-21), Permissions admin**. Next item after
Case sheet types in the tracked Phase 3 sequence. Was flagged earlier in
this README as a scope question ("11 modules × 4 permissions is awkward
on a phone") — resolved by not porting the web app's grid layout at all:
a vertical list of `ExpansionTile`s (one per module, each showing an
`N/total` grant count in its collapsed header) reads fine on a phone
where a table wouldn't.

- **A real backend gap, found and closed**: `Api\UserPermissionController`
  had `show`/`update` (grants only) but no `index` — no way for a Flutter
  client to list which users have manageable permissions at all. Added,
  mirroring the web controller's `index()` exactly (`role != super_admin`,
  ordered by `full_name`).
- **Deliberately not ported**: the web controller's scope-restriction
  handling (`App\Services\ScopeHelper` — confining a user's own account to
  specific departments/stages/education types/academic sessions). That's
  a separate 4-dimension multi-select feature with no API surface at all
  yet (`show()` doesn't return it, `update()` doesn't accept it) — a
  bigger addition than this pass, called out explicitly rather than
  quietly skipped. `Api\UserPermissionController`'s docblock now says so.
- **New `features/permissions_admin/`** — a user list (`/permissions`)
  and an edit screen (`/permissions/{user}`) built from
  `PermissionMatrix::forUi()`'s exact module/action shape (each module
  keeps its own action set — `tasks` gets `assign`, `task_progress` gets
  `start`/`finish`/`open_case_sheet`/`view_all`, etc. — not a uniform
  grid). A single "حفظ" FAB, disabled until something changes, submits the
  full flat `grants` list in one `PUT`.
- **A real, unrelated RTL bug found and fixed while reading this screen's
  first live screenshot**: the module header's `"$granted / $total"`
  count string was rendering with the two numbers **swapped** — e.g. "1
  granted of 2" showed as "2 / 1". Root cause: inside the app's RTL
  (Arabic) ancestor, Unicode's bidi algorithm reorders two numbers joined
  only by a neutral separator (`/` or `→`), since neither number is
  anchored by a strong-direction character. Same root cause as the
  odontogram/periodontal-chart mirroring bug from earlier in this
  project, different symptom (a swapped label, not a misrecorded tooth
  site) — fixed the same way, wrapping the affected `Text` in
  `Directionality(textDirection: TextDirection.ltr, ...)`. Grepping the
  codebase for the same pattern (two LTR-ish values joined by `/` or `→`
  with no anchoring word) found it recurring in
  `academic_sessions_admin`'s date-range display (`"$start → $end"`,
  confirmed via a live screenshot showing the end date first) in both the
  list and detail screens — fixed identically. `group_detail_screen.dart`'s
  similar-looking `"$day — $start إلى $end"` was checked and left alone:
  the Arabic day name and `إلى` are themselves strong-RTL anchors, and it
  was already confirmed rendering correctly during the Groups pass.

Verified live end-to-end via CDP-driven Chrome, logged in as staff: user
list loaded all 3 non-`super_admin` accounts; opened one, confirmed every
module's grant count matched a `curl` baseline taken beforehand; expanded
a module, toggled a permission, saved, confirmed the exact new grant
server-side via `tinker`; reverted to the original 17-grant baseline via
`curl` (re-verified count and full list matched exactly) so the real
account wasn't left altered by the test. Re-verified the RTL fix live
after a full app restart (code changes need a restart, not just a
re-navigate, to take effect) — both the permission-count and the
academic-session date-range now render in the correct order.
`flutter analyze` clean throughout; test token revoked afterward.

**Phase 3 item — done (2026-08-21), Backup admin**. Next item after
Permissions in the tracked Phase 3 sequence. `Api\BackupController`
(`status`/`store`/`toggleAuto`) already existed — confirmed it's a plain
MySQL `mysqldump` (with a PHP-driven fallback), not the MikroTik feature
the standing "بدون نسخ اختياطي لمكروتك" instruction rules out; that SCP
upload step was already excluded when the web version was built (see
`App\Services\DatabaseBackupService`'s own docblock) — this Flutter screen
is safe to build on top of the same already-scoped-down feature.

- **New `features/backup_admin/`** — last-backup timestamp, an
  auto-backup switch, a "create now" button, and a list of recent backup
  files (name/size/date). No download action: the API itself only
  returns metadata (`Api\BackupController`'s docblock notes the raw
  `.sql` stays a web-only download), so there's nothing to wire up on
  the Flutter side either.
- Needed one `intl` import fix, not caught until `flutter analyze`:
  `package:intl/intl.dart` exports its own `TextDirection` (LTR/RTL/
  unknown, for bidi text detection) that collides with `dart:ui`'s
  `TextDirection` used by `Directionality`. Resolved with `hide
  TextDirection` on the `intl` import rather than prefixing every
  `DateFormat` reference.
- Proactively wrapped the file list's size/date subtitle in
  `Directionality(textDirection: TextDirection.ltr, ...)` before ever
  seeing it render — same bidi-reordering pattern just fixed in the
  Permissions/Academic-sessions pass (two LTR-ish values joined by a
  neutral separator, no strong-direction anchor).

Verified live end-to-end via CDP-driven Chrome, logged in as staff:
toggled auto-backup on, confirmed via `tinker`; created a backup, saw the
snackbar and the new file appear in the list with correct size/date
formatting; reverted the auto-backup toggle back to off afterward (an
ongoing-behavior setting, unlike the backup file itself, which was left
in place — creating one is a normal, low-risk action on this real dev
database, not test data that needed cleaning up). `flutter analyze`
clean throughout; test token revoked afterward.

**A real, found-not-fixed bug, same category as the standing
`visit_date`/`paid_at` one**: the backup screen's "last backup at"
timestamp and its file list's "modified at" timestamp disagreed by
exactly 3 hours in testing (`08:22` vs `11:22`) — `config('app.timezone')`
is `UTC` (so `last_backup_at`, written via `now()`, is a UTC value with no
timezone marker in its JSON string), while the backup file's `mtime`
comes from the filesystem in the host OS's local time (`AST`, UTC+3 on
this dev machine). Both the web page and this new Flutter screen inherit
the same mismatch, since both just display whatever the API returns —
this isn't something introduced by the Flutter port. Left unfixed
pending a decision on the right fix (change `app.timezone`? mark the
API's datetime strings with an explicit UTC suffix and convert
client-side? something else?) rather than picking one unilaterally in a
pass that was scoped to the Flutter screen, not backend timezone
handling.

**Phase 3 item — done (2026-08-21), Activity log viewer**. Next item
after Backup in the tracked Phase 3 sequence.

- **A real, small backend gap, found and closed**: `Api\ActivityLogController`
  had `module`/`action` filters but was missing `search` (username/
  description) relative to the web controller — added to match, straight
  port of the same `where(...)->orWhere(...)` clause.
- **New `features/activity_log/`** — search field, an action filter
  (all/create/update/delete, matching the web page's own fixed set — the
  underlying data has other values too, like `view`, which just falls
  through to a neutral grey chip rather than being excluded), and a
  manual "تحميل المزيد" (load more) button. This is the first screen in
  the app to actually exercise `Paginated.hasMore`: every other paginated
  list so far (`doctors_admin`, etc.) only ever showed page 1, fine there
  but not here — 370 rows across 13 pages in the live dev DB, confirmed
  via `curl` before building. Local `List<ActivityLogEntry>` state
  accumulates each loaded page rather than using a `FutureProvider`,
  which doesn't fit an appending-pages shape cleanly.
- **A real overflow bug, found on the first live screenshot and fixed**:
  putting the action chip *and* the date in `ListTile.trailing` (stacked
  in a `Column`) overflowed the tile's fixed trailing-slot height by
  2px — confirmed via the literal "BOTTOM OVERFLOWED BY 2.0 PIXELS" debug
  banner Flutter renders in place. Fixed by moving the date into
  `subtitle` instead (a second line under the module/description text,
  which sizes to its content rather than a fixed slot) and leaving only
  the chip in `trailing`.
- Needed the same `intl`/`Directionality` `TextDirection` collision fix
  already documented in the Backup pass (`hide TextDirection` on the
  `intl` import) — this screen also uses both.

Verified live end-to-end via CDP-driven Chrome, logged in as staff:
confirmed a text search against a real user ("hakam", zero matches)
matched a `curl` baseline exactly; the "إنشاء" (create) action filter
correctly narrowed the list and hid a `delete` row that had been visible
under "الكل"; confirmed via `curl` that the create-filtered set (29 rows)
fits on one page, so no "load more" button appearing there is correct,
not a missed case; switched to "الكل" (370 rows, 13 pages) and confirmed
"تحميل المزيد" fetched and appended page 2 correctly. `flutter analyze`
clean throughout; test token revoked afterward. No test data was created
for this pass — it's a read-only viewer over the log the earlier passes'
own test actions already populated.

**Phase 3 item — done (2026-08-21), Clinic settings edit**. The last item
in the tracked Phase 3 admin sequence — every module in that list is now
built. The biggest pass of the batch: this is the first (and so far only)
Flutter screen that uploads a file, and it surfaced four separate real
bugs, three fixed, one documented as a decision for later.

- **A real security leak, found and fixed**: `ClinicSetting`'s own
  docblock claimed MikroTik connection fields and `jwt_secret_key` were
  "deliberately excluded" — true only of `$fillable` (mass-assignment
  protection), never of serialization. Both `ClinicSettingController::
  edit()` (web, Inertia props) and the new `Api\ClinicSettingController::
  show()` spread `$settings->toArray()` unfiltered, so
  `mikrotik_ip`/`mikrotik_user`/`mikrotik_pass`/`mikrotik_ssh_port` and
  the JWT secret were actually reaching the browser/API response —
  confirmed via a live `curl` before touching any Flutter code. Fixed at
  the model level (added to `$hidden`, same mechanism already protecting
  `mail_password`), closing both call sites at once. Full details in
  `dental_laravel/README.md`.
- **A real CORS gap, found and fixed**: the clinic/university logo
  `<img>` failed to load in the live Flutter Web build with a genuine
  browser CORS rejection (confirmed via the exact browser console
  message, not assumed) — `/storage/*` is served by Apache directly from
  a symlink, bypassing Laravel's `api/*`-scoped CORS middleware entirely,
  unlike every `/api/v1/*` response (confirmed those already carry
  `Access-Control-Allow-Origin: *`). Native Android/iOS builds aren't
  affected (CORS is browser-only), but a real web deployment on a
  different origin than the API would hit the same thing, so this was
  fixed at the Apache config layer (`public/.htaccess`, mirroring the
  file's existing `/build/assets/` caching-header pattern) rather than
  left as a testing footnote.
- **Four more RTL bidi bugs, found and fixed** — same root cause as every
  other instance this session (a value mixing strong-LTR characters with
  bidi-neutral separators, rendered inside an RTL ancestor with no
  explicit direction), each confirmed live before fixing: `base_url`
  (stored `/dental_clinic` rendered `dental_clinic/`), the phone field
  (typed `0770-CDP-TEST` rendered `CDP-TEST-0770`), and the email/website
  fields (same shape, fixed proactively once the pattern was clear rather
  than waiting to hit them individually). Fixed by setting
  `textDirection: TextDirection.ltr` directly on those four
  `TextFormField`s — the first time this bug class needed fixing on an
  *editable* field rather than a `Text`; the underlying
  `TextEditingController.text` was never corrupted, only the on-screen
  rendering, confirmed by checking what actually got saved.
- **A real validation bug in this pass's own new code, found and fixed**:
  the first save attempt failed with "The enable notifications field must
  be true or false." Root cause: Laravel's `boolean` rule does a *strict*
  `in_array($value, [true, false, 0, 1, '0', '1'], true)` — the literal
  strings `"true"`/`"false"` (Dart's `bool.toString()`, and multipart
  bodies have no native boolean type) aren't in that list at all, only
  `"0"`/`"1"` are. Fixed in the repository's field-serialization step.
- **New infrastructure**: `ApiClient.postMultipart()` — every file-upload
  endpoint in this API needs POST + `_method: PUT` spoofing (PHP never
  populates `$_FILES` on a genuine PUT/PATCH, only POST — the web app's
  own `useForm().transform(...).post(...)` already relies on the same
  mechanism), and `FormData` always gets Dio's correct
  `multipart/form-data; boundary=...` header automatically (confirmed by
  reading `dio_mixin.dart` directly rather than assuming), overriding
  this client's JSON default with no extra `Options` needed.
- **New `features/clinic_settings_admin/`** — one long form (basic info +
  clinic logo, contact info, university/college + logo, currency/
  timezone/base_url, notification toggles), matching exactly the field
  set `Api\ClinicSettingController::update()` already validates.
  Deliberately excludes `theme` (the Flutter app uses a fixed theme, not
  the web app's selectable one, per §7) and the SMTP `mail_*` fields (a
  scope cut — editable mail credentials on a phone admin screen wasn't
  judged worth building this pass, and the API doesn't validate them
  either).

Verified live end-to-end via CDP-driven Chrome, logged in as staff, across
several rounds as each bug above was found and fixed in turn: confirmed
the CORS fix by re-checking the browser console showed no error and the
logo rendered; confirmed all four bidi fixes render in logical order;
picked a real file via `DOM.setFileInputFiles` (Chrome DevTools Protocol's
mechanism for scripting a file input — the OS-native picker dialog itself
can't be automated) and saved successfully once the boolean bug was
fixed; confirmed server-side via `tinker` that the logo's stored filename
and file size actually changed, and that the old file was deleted (the
controller's own cleanup step) — full multipart upload path proven
working, not just "no error was thrown". Test phone/email values were
reverted to their original `null` afterward via `curl`; the test logo
image could **not** be restored to its original binary (the update's own
cleanup deletes the old file before storing the new one, and no backup of
the original was taken before testing) — left as the small, low-stakes
placeholder image the test upload produced, noted here rather than
silently left unmentioned. `flutter analyze` clean throughout; all test
tokens revoked.

**`endodontics_data` on the Operative case sheet — done (2026-08-21)**.
The last remaining deferred item from earlier phases — with this, every
item this README had tracked as open is closed.

- Read `App\Support\OperativeForm.php` (`endodontics_data`, top-level
  field, `type: 'endodontics'`, no `group`), `resources/js/Components/
  EndodonticsSection.vue`, and `EndodonticsCanalTable.vue` directly before
  writing anything — the exact JSON shape (`tooth_no`, `canal_count`,
  `diagnosis[]`, `first_visit[]`, `first_visit_data.{canal}`,
  `second_visit_data.{canal}`, `technique[]`, `third_visit_data.{...}`,
  `signature`) is copied from those sources, not guessed, and confirmed
  again live against a real pre-existing record (id 79) that already had
  genuine data in every one of those keys from earlier web-app use.
- **New `features/endodontics/`** — `EndodonticsField` (the toggle +
  tooth/canal/diagnosis + three visits + signature) and
  `EndodonticsCanalTable` (the shared 10-canal table, used twice with
  different columns — `wl_xray/initial_length/initial_size/final_wl` for
  visit 1, `wl/size/rp` for visit 2). Wired into `DynamicSectionForm` the
  same way `dental_chart` already was: a new `_coerce` case (reusing the
  existing `_parseGroup` helper — the API returns this field
  already-decoded, matching `dental_chart`'s own pattern, not the
  string-encoded pattern the `group` columns use), a new field-type
  switch case, and added to `CaseSheetField.isSupported` — the value
  flows through `buildSubmitPayload()` with no special-casing needed,
  since it's an ungrouped field like `tooth_data`.
- **Matches the web component's own deliberate scope, not the original
  PHP app's**: no per-visit image-upload galleries, no canvas signature
  pad (a plain text field stands in, same as web) — confirmed these were
  never built on web either before treating their absence here as
  in-scope-and-done rather than a gap.
- **A real dormant bug found in the web Vue component while porting it,
  not reproduced here**: `EndodonticsSection.vue`'s enable toggle is a
  *computed* derived purely from `Object.keys(modelValue).length > 0`.
  Reading its own setter shows that turning the toggle on while the
  record is still `{}` re-emits `{}` (nothing in the setter adds a key),
  so the getter would recompute `false` immediately — the toggle would
  visually snap back off before a user could enter anything, for any
  record that had never been touched before. `EndodonticsField` avoids
  this by keeping "enabled" as genuine local `State` instead of deriving
  it from map emptiness on every rebuild — confirmed live that toggling
  on a brand-new record's section actually stays on and stays usable,
  unlike what reading the web component's own logic predicts it would do
  there.

Verified live end-to-end via CDP-driven Chrome, logged in as a doctor
(not staff — this is a doctor-only clinical form, unlike every other item
in this file so far): created a real Operative case sheet, toggled the
section on (confirmed it stayed on), filled every distinct part of the
form (tooth number, canal count, a diagnosis, a first-visit step, a
canal-table cell + its checkbox, a technique, both master-cone checks and
its notes field, the signature), saved, and confirmed every single value
via `tinker` matched exactly what was entered — the full nested JSON
shape round-tripped correctly through `ApiClient`'s plain JSON POST (no
multipart needed here, unlike clinic settings — this field's value is
just a nested `Map`, sent the same way `tooth_data`'s `List` already is).
Hit the project's already-documented `visit_date` NOT-NULL bug again
along the way (leaving that date field empty threw a real 500) — not a
new bug, the same one already on record from earlier in this project,
deliberately left unfixed; the test simply had to fill that field to get
past it, same as any real use of this form would. Also hit — and
diagnosed, not just excused — this session's now-familiar
"click-right-after-a-layout-shift needs a retry" CDP testing artifact: a
tooth-number type-in landed on nothing the instant after the toggle's
layout shift, producing a save with `endodontics_data` missing that one
key; a second, otherwise-identical attempt with a normal pause between
the toggle and the click saved `{"tooth_no": "36"}` correctly, confirmed
via `tinker` — isolated as a timing artifact rather than assumed, by
reproducing it, then reproducing the fix. Both test records deleted
afterward via `tinker`; the doctor test token revoked. `flutter analyze`
clean throughout.

Next action: none outstanding. Every item this README tracked as a "next
action" — the full Phase 3 admin list and this last deferred field — is
now built and verified. Any further work is new scope, not a backlog
item.

## 10. Installable builds — Windows `.msix` and Android `.apk` (2026-08-21)

Two new deliverables, requested directly (not from this README's backlog):
a branded, installable Windows desktop package, and a release Android APK
sideloadable on Android 8.1 (API 27) and up.

### Branding

- `assets/branding/app_logo.png` — the clinic's circular medallion logo
  (Dentistry College Teaching Hospital, Tikrit University), supplied by the
  user. Declared in `pubspec.yaml`'s `flutter: assets:`.
- `flutter_launcher_icons` (dev-only, Windows-scoped: `pubspec.yaml`'s
  `flutter_launcher_icons: windows:` block) regenerates
  `windows/runner/resources/app_icon.ico` from that logo —
  `dart run flutter_launcher_icons`. Deliberately scoped to Windows only;
  Android/iOS/web icons were not asked for and were left untouched (Android
  still ships Flutter's default launcher icon and the generic
  `dental_clinic_app` label — a separate ask if wanted later).
- `windows/runner/main.cpp`'s window title and `windows/runner/Runner.rc`'s
  version-info strings (`FileDescription`, `ProductName`, `CompanyName`,
  `LegalCopyright`) updated to real clinic branding — previously the
  generic `dental_clinic_app` placeholder the `flutter create` template
  leaves in place. `windows/CMakeLists.txt`'s `BINARY_NAME` was
  deliberately left as `dental_clinic_app` (it only affects the internal
  `.exe` filename, not anything user-facing once packaged — renaming it
  risks a CMake target-name mismatch for no visible benefit).

### Animated splash screen

`features/auth/presentation/splash_screen.dart` — was a bare
`CircularProgressIndicator` on a plain white `Scaffold`; rebuilt as a
`StatefulWidget` with three `AnimationController`s: a one-shot entrance
(logo scale + fade via `Curves.easeOutBack`, then the clinic name/subtitle
sliding up and fading in), a slow-repeating rotating gold sweep-gradient
ring behind the logo, and a gentle breathing glow (`BoxShadow` pulse) —
all on a navy gradient background chosen to match the logo's own
navy/gold palette rather than the app's Instagram-style in-app theme
(`core/theme/app_theme.dart`), since the splash is brand-first, not
UI-consistent-with-the-app-first. No new dependency — pure
`AnimationController`/`CurvedAnimation`/`AnimatedBuilder`, matching this
project's existing "no `freezed`, hand-written" minimalism. Still purely
reactive to `authControllerProvider` per the original docblock — it never
navigates itself.

### Windows `.msix` installer

No Inno Setup or NSIS installed on this machine (checked directly —
neither found under `Program Files`/`Program Files (x86)` — ruled out
rather than assumed). The `msix` package was used instead: it needs no
extra tool install because `makeappx.exe`/`signtool.exe` are already
present as part of the Windows 10 SDK bundled with the installed Visual
Studio 2022 Community
(`C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\`). Config lives
in `pubspec.yaml`'s `msix_config:` block (display name, publisher,
identity, the same clinic logo as the package logo). No `certificate_path`
set, so `msix:create` self-signs with an auto-generated test certificate —
installable via direct sideload-trust, not Store-ready; a real
organizational code-signing certificate would replace this before any
wider distribution.

Build sequence: `flutter build windows --release` →
`dart run msix:create` → `build\windows\x64\runner\Release\
dental_clinic_app.msix` (23.3 MB). Delivered to the user directly.
**Install note for a self-signed package**: Windows will show "Untrusted
package" on first open — the certificate has to be installed into the
local machine's Trusted People (or Trusted Root) store before "Install"
proceeds; this is expected for a self-signed test cert, not a build
defect.

**A real testing gap, disclosed rather than glossed over**: this
environment's screen-capture tooling (GDI `BitBlt`/`CopyFromScreen`, tried
via both direct capture and `PrintWindow` with `PW_RENDERFULLCONTENT`)
could not capture the Flutter window's actual D3D/ANGLE-composited client
area — every capture came back blank white for the content region, while
the native (non-GPU) title bar text and icon captured correctly. This
matches a known limitation of GDI screen capture against
DirectComposition surfaces in remote/virtual display sessions, not an app
crash — the `flutter run -d windows --debug` console log showed a clean
launch with zero runtime exceptions across two separate fresh runs, and
the title bar correctly showed the new title/icon. The splash animation's
actual on-screen appearance was **not** visually confirmed in this
session; a real monitor (or a screen-recording API that captures
GPU-composited content, e.g. Windows.Graphics.Capture) would be needed to
close that gap.

### Android release APK — Android 8.1 compatibility

Two real bugs found and fixed while producing a release (not debug) build
for the first time this project:

- **Missing `INTERNET` permission in release builds** — the Flutter
  template only grants `android.permission.INTERNET` via
  `android/app/src/debug/AndroidManifest.xml` and `src/profile/...`
  (added there for the hot-reload/DevTools connection), never in
  `src/main/AndroidManifest.xml`. Every debug/profile run worked by
  accident of that scaffolding; a release build — the only kind installable
  outside `flutter run` — would have had **no network access at all**,
  failing every single API call silently. Fixed by adding the permission
  to the main manifest unconditionally.
- **`network_security_config.xml` only allowlisted the Android emulator's
  `10.0.2.2` loopback alias**, not a real phone's reachable address. Since
  `targetSdkVersion` is 36, cleartext HTTP to any other host is blocked by
  default regardless of the *device's* Android version — this blocks a
  real Android 8.1 phone even though Android 8.1 itself predates that
  enforcement, because the enforcement is keyed to the app's target SDK,
  not the OS. Fixed by adding this dev machine's actual LAN IP
  (`192.168.1.155`, confirmed via `Get-NetIPAddress`, Wi-Fi adapter) as a
  second cleartext-permitted domain. Also confirmed directly (not assumed)
  that Apache is listening on `0.0.0.0:80` (not just loopback) and that an
  existing Windows Firewall rule ("Apache HTTP Server", Inbound/Allow,
  Private+Public profiles) already permits the traffic — no firewall
  changes needed.

Built with `flutter build apk --release --split-per-abi
--dart-define=API_BASE_URL=http://192.168.1.155/dental_laravel/public/api/v1`
— split per ABI because the universal APK (70.8 MB) exceeded this chat's
30 MB file-delivery limit. Confirmed via `aapt dump badging`: `sdkVersion:
'24'` (well under API 27, so installable on 8.1), `uses-permission:
android.permission.INTERNET` present. The app still ships Flutter's
default launcher icon and the generic `dental_clinic_app` label on
Android (branding pass was Windows-only, per the original request).

**Verified live on real hardware (2026-08-21)**, closing the gap above:
an actual Android device connected via `adb` turned out to be a real
Android 8.1.0 (API 27) unit — but **`armeabi-v7a`**, not `arm64-v8a` as
assumed when picking which split to send first. The `arm64-v8a` build
sent earlier would not have installed on this device at all; caught only
because `adb shell getprop ro.product.cpu.abi` was checked against the
actual connected hardware instead of assuming "Android 8.1-era phones are
arm64." The correct `armeabi-v7a` build was installed with
`adb install`, launched, and driven end-to-end via `adb shell input` +
`adb exec-out screencap`: login screen rendered correctly (RTL Arabic,
staff/student toggle), a real staff login (`admin@clinic.test`) round-
tripped to the Laravel API over the LAN IP and succeeded, and the full
Phase 3 admin menu (academic sessions, tasks, case sheet types,
permissions, backup, activity log, clinic settings, education types)
rendered correctly afterward — confirming the `INTERNET` permission and
`network_security_config` fixes above actually work on real hardware, not
just in static analysis. `adb logcat` showed zero exceptions from
`com.dentalclinic.dental_clinic_app` throughout (the only errors logged
during the session were unrelated Google Play Services cert warnings,
caused by this specific device's system clock being stuck at 2001-01-01 —
a device configuration issue, not an app bug).

**Doctor login also verified on the same device.** A throwaway test
doctor (`qa_doctor_test`, id 1965 — `App\Models\Doctor::create()` via
tinker, valid `education_type_id`/`stage_id` copied from a real existing
doctor record) logged in through the "طالب" toggle on the real device;
landed correctly on the doctor-specific home ("النماذج السريرية" — the 8
case-sheet-type list, distinct from staff's admin menu), confirming the
account-type branch in `HomeScreen` works on-device too, not just via
staff. `adb logcat` clean throughout. Cleanup after: the test doctor's
Sanctum token was revoked and the `Doctor` row deleted via tinker
immediately after — the device's locally-stored token is now stale and
will 401 → redirect to `/login` on its next request, which is expected
(no client-side logout was triggered from the server side, matching how a
real revoked-elsewhere session behaves).

## Phase 4A: self-profile & settings (2026-08-21)

New `features/profile/` — the first Flutter screen for a logged-in
doctor's or staff member's own account. Previously there was no such
screen at all: the home screen just printed the account's display name as
static text, and the API only had a read-only `GET /me` (see
`dental_laravel/README.md`'s "Phase 4A" entry for the new `PUT /me` /
`PUT /me/password` endpoints this screen calls).

- `data/profile_repository.dart` — reuses `ApiClient.postMultipart()`
  (the same `_method: PUT` spoofing pattern proven in
  `clinic_settings_admin`) for the info-update call (photo optional), and
  a plain `putJson` for the password-change call.
- `presentation/profile_screen.dart` — two separate `Form`s (edit-info,
  change-password), matching the web app's own two-form split rather than
  merging them into one. Avatar tap-to-pick via `image_picker`, same
  convention as `clinic_settings_admin`'s logo pickers. Email/phone fields
  forced `TextDirection.ltr` from the start this time (not found-then-fixed
  — every earlier phase's RTL bidi bug on this exact field shape was
  already on record, so it was avoided up front instead of re-discovered).
- New entry point: a person icon on `HomeScreen`'s app bar, for both the
  doctor and staff branches.
- `AuthController.updateAccount()` (new) — swaps the freshly-updated
  account straight into `AuthState` after a save, since the update
  endpoint's response already has everything needed; no redundant `/me`
  round-trip.
- `StaffAccount` gained `profileImageUrl` (parses the new
  `profile_image_url` key), matching `DoctorAccount`'s existing field —
  see the backend README entry for the `UserResource` fix this depends on.

**Verified live on the real Android 8.1 device** (`armeabi-v7a`, same one
used for every Phase-3/Windows/Android verification this session): logged
in as staff (`admin@clinic.test`), opened the profile screen, edited the
phone number and saved — confirmed via `tinker` the change actually
persisted server-side — then changed the password through the same screen
and confirmed via `curl` that a login with the new password succeeded.
Also incidentally re-confirmed the animated Windows-session splash screen
(`splash_screen.dart`) actually renders correctly — the logo, gold sweep
ring, and pulsing glow all showed up correctly on real hardware on this
build's first cold start, closing a visual-verification gap that couldn't
be checked on Windows earlier in this session (see `dental_laravel/README.md`'s
Windows `.msix` entry for that limitation).

The doctor branch of both endpoints was verified via `curl` against a
throwaway test doctor (dual-guard dispatch in `Api\ProfileController`,
plus a wrong-old-password rejection check) rather than repeating the full
on-device UI pass, since the screen's code path is identical for both
account types — only the branch inside `ProfileRepository.update()`
differs, and that's exercised by `AccountType`, not by which UI drove it.

All test data cleaned up afterward: every Sanctum token created during
this verification pass (6, across both `curl` and the on-device session)
revoked, the phone number and password reverted back to their original
values, the throwaway test doctor deleted.

## Phase 4B: staff/user creation + permission assignment (2026-08-21)

New `features/users_admin/` — create-only (`UserFormScreen`), deliberately
not a full CRUD module: viewing/editing what an existing user can do is
already `permissions_admin`'s job, and this feature exists only to get a
brand-new user created and handed straight to that screen. Mirrors
`features/doctors_admin`'s shape (`user_form_screen.dart` parallels
`doctor_form_screen.dart`, `users_admin_repository.dart` parallels
`doctors_admin_repository.dart`), posting to the new `POST /users`
(`permission:users,create` — see `dental_laravel/README.md`'s Phase 4B
entry for why that permission module was previously unused). `role` picks
from a new `kAssignableUserRoles` constant — `User::ROLES` minus
`super_admin`, matching the same restriction the backend now enforces.

On success, `context.pushReplacement('/admin/permissions/${user.id}')` —
not `push`, so the create form doesn't sit on the back stack behind the
permission editor the admin actually needs next. A "مستخدم جديد" FAB was
added to `PermissionUserListScreen` as the entry point, next to the
existing per-user "Manage" navigation.

**Verified live on the real Android 8.1 device**: logged in as staff,
opened "الصلاحيات" from the admin hub (already showing the web-created
test user from the same verification pass — confirming both clients
share the same backend correctly), tapped the new FAB, filled and
submitted the form, and landed exactly on the new user's permission-edit
screen with the `users` module now visible in the grant list — matching
the web flow's behavior field-for-field. Confirmed via `tinker` that the
account persisted with the correct `full_name`/`username`/`email`/`phone`/
`role`/`status`. `flutter analyze` clean throughout.

All test data cleaned up afterward: both the web-created and
Flutter-created test staff accounts deleted, all Sanctum tokens for
`admin@clinic.test` revoked, the debug app force-stopped on the device,
the CDP-driven Chrome instance closed.

## Phase 4C: patient registration — services & days (2026-08-21)

New `features/patient_registration/` — deliberately separate from
`features/records/` (which covers the *other*, unrelated `patients` table
— see `App\Models\PatientRegistration`'s docblock in the backend README
for why). Domain models `RegisterDay`/`Service` (mutually importing each
other — the API nests each inside the other depending on the endpoint)
and `PatientRegistration`; one repository covering all three resources
plus the settings CRUD (`permission:settings,edit`-gated server-side, same
as the web settings page). Three screens:

- `patient_registration_form_screen.dart` — mirrors
  `PatientRegistrations/Create.vue`'s day-first cascading picker exactly:
  picking a day filters the service dropdown to `RegisterDay.services`.
- `register_settings_screen.dart` — day add/delete, service add/delete
  with a `FilterChip` multi-select for days (the Flutter-idiomatic
  equivalent of the web's checkbox grid).
- `patient_registration_list_screen.dart` — mirrors `Index.vue`, with a
  FAB to create and a settings gear in the app bar.

New entry point: "تسجيل المرضى" added to `RecordsHubScreen`, alongside
"المرضى" (the other patient concept) rather than under `AdminHubScreen` —
this is front-desk staff work, not system administration, matching where
the equivalent lives on the web (main nav, not the settings area).

**A real backend-shape bug caught before it reached this feature's own
list screen**: `Api\PatientRegistrationController::index()` originally
returned a raw `LengthAwarePaginator` via `response()->json($paginator)`
— Laravel's default flat shape (`{current_page, data, ...}` at the top
level), not the `{data: [...], meta: {current_page, ...}}` shape every
other paginated endpoint in this API returns via
`SomeResource::collection($query)->response()`, which is what this app's
shared `core/network/paginated.dart` (`Paginated.fromJson`) expects.
Caught by checking the actual JSON shape against `Paginated.fromJson`'s
assumptions before wiring the Flutter list screen to it, not after a
runtime failure — fixed by adding `PatientRegistrationResource` and using
the same `Resource::collection()->response()` pattern as every other list
endpoint, instead of writing a one-off parser for a shape that shouldn't
have existed in this API to begin with.

**A real crash-causing model bug, found via a live `curl` 500**: the new
`Service` model had no explicit `$table` — Eloquent's naming convention
inferred `services`, not the actual `register_services` (the class is
named `Service`, but the table predates the class and was never going to
be renamed). `RegisterDay`'s inferred table name happened to match
(`register_days`), which is exactly why this kind of bug hides easily —
fixed by adding `protected $table = 'register_services';`.

**A real Flutter rendering bug, found only through on-device testing —
`flutter analyze` and every backend/web check passed clean**: the
settings screen's "add day" button (`FilledButton`, inside a `Row`
alongside an `Expanded` text field) threw `BoxConstraints forces an
infinite width` and crashed the entire screen to a blank white body with
**no visible error** — confirmed live: `adb logcat` showed zero relevant
output, the screen just rendered nothing. Only running `flutter run`
directly against the device (not a plain `adb install` + launch) surfaced
the real Dart-level exception in the console: a `Row`'s non-flexible
children get unbounded max-width constraints, which most widgets tolerate
by sizing to intrinsic content but `FilledButton`'s internal layout does
not, particularly when nested inside a `ListView`/sliver. Fixed by
wrapping the button in `Flexible`. Worth keeping as a general lesson for
this codebase: **a blank screen with zero logcat output is not proof of a
clean render** — `doctor_form_screen.dart`, `user_form_screen.dart`, and
every other form built earlier this session always put their submit
button as the ListView's own direct child, never inside a `Row`, which is
exactly why this exact bug never surfaced until this screen's day-name
input needed an inline button next to it.

**Verified live on the real Android 8.1 device**, first via a plain debug
build (which silently hit the blank-screen bug above), then via
`flutter run -d <device>` to get real console diagnostics, then again via
a plain rebuild once fixed: full create flow (day-first cascade correctly
filtered the service list, submitted, appeared correctly in the list with
phone rendered LTR and service/day rendered RTL — on two separate lines,
not one forced-LTR line, avoiding the mixed-script bidi bug class this
project has hit before rather than reintroducing it), settings screen
(added a day — appeared in both the day list and the service form's
`FilterChip`s — then deleted it, both confirmed), full parity confirmed
between web-created and Flutter-created test registrations showing
correctly in both clients. `flutter analyze` clean throughout (it does not
catch layout-constraint bugs — those are only caught at runtime).

All test data cleaned up: every test registration, service, and day
deleted via `tinker`, the admin account's Sanctum tokens revoked, the app
force-stopped, Chrome closed.

## Phase 4D: POS thermal ticket printing (2026-08-22)

Prints a registration ticket on the POS terminal's **built-in** thermal
printer immediately after a patient is registered. The approved plan
assumed an external Bluetooth printer; the actual hardware turned out to
be an all-in-one Android POS terminal (model "Q2i", MediaTek/`alps`,
Android 8.1) whose printer is built into the device — so this phase is
that plan's intent, on the hardware that actually exists.

**Identifying the printer SDK — found, not guessed.** `adb shell pm list
packages` on the real device showed a system priv-app
`com.iposprinter.iposprinterservice` exposing an AIDL bind action. Its APK
holds no bytecode to read (resources only), so the interface came from the
vendor's own published SDK PDF ("2C-POS-V1 Mobile POS Printer SDK", whose
internal title "SDK for QZ-Q1&Q2" matches this "Q2i" unit), cross-checked
against the device: the doc's example Bluetooth address
`00:AA:11:BB:22:CC` is the exact address of a pre-bonded device named
"IposPrinter" in this unit's own `dumpsys bluetooth_manager` output.

**A real bug caused by trusting that PDF — caught on-device, not in
review.** The PDF's AIDL reference is a summary table listing method
names and their "business" parameters only; it silently omits the
`IPosPrinterCallback` parameter that **every** method actually takes.
AIDL transaction codes are positional, so an interface whose method
signatures differ from the real service's talks to the wrong methods
entirely. The first on-device print attempt failed with
`Attempt to invoke interface method void ...IPosPrinterCallback.onRunResult(boolean)
on a null object reference`. Fixed by replacing the reconstruction with
the genuine `.aidl` files, transcribed from
[paystory-de/cordova-plugin-iposprinter](https://github.com/paystory-de/cordova-plugin-iposprinter)
(Apache-2.0, license verified via the GitHub API before attributing it) —
an open-source Cordova plugin wrapping this exact service, found by
searching the real error message. Its `printerPerformPrint` also takes a
`feedlines` int the PDF omits entirely.

**A second real finding: the AIDL path doesn't work on this unit.** With
the correct interface, the service binds, `getPrinterStatus()` returns 0
(`PRINTER_NORMAL`), the ticket bitmap decodes correctly (384×287, verified
non-blank by sampling pixels) — and `printerInit()` still returns an
explicit `isSuccess=false` through its callback. Established with real
on-device logging (`Log.d` at every step, read back via `flutter run`'s
console), and confirmed **not** a paper/hardware fault: the user showed
the same printer printing fine through Android's ordinary print dialog,
paper loaded.

**The fix: the vendor's documented second route.** The same SDK doc
describes the built-in printer also being reachable as a virtual
Bluetooth SPP device speaking plain ESC/POS. `PosPrinterPlugin.kt` now
tries AIDL first and **falls back to Bluetooth SPP** on any AIDL step
failing — connecting to the bonded "IposPrinter" over RFCOMM
(`00001101-…` SPP UUID) and writing the ticket as an ESC/POS raster
block (`GS v 0`). **Verified printing on real paper**, confirmed twice
over: by the user, and independently in logcat by the printer service's
own broadcast sequence `BUSY_ACTION` →
`CURRENT_TASK_PRINT_COMPLETE_ACTION` → `NORMAL_ACTION`.

**Why the ticket is a bitmap, not printer text.** The printer's built-in
fonts are Chinese GBK/GB18030 + ASCII only — no Arabic glyphs (confirmed
from the raw font resource files bundled inside the printer service's own
APK). So `ticket_widget.dart` lays the ticket out as a real Flutter
widget (correct Arabic shaping and RTL), `ticket_renderer.dart`
rasterizes it off-screen via an `OverlayEntry` + `RepaintBoundary` at
`pixelRatio: 1.0` (widget pinned to 384 logical px = the printer's
documented 384-dot line width), and only the resulting PNG crosses the
platform channel.

Printing never blocks or rolls back the registration: the record is
already saved server-side before printing is attempted, and a print
failure surfaces as its own message. Android-only (`Platform.isAndroid`
guard) — other platforms skip it silently.

New files: `android/app/src/main/aidl/com/iposprinter/iposprinterservice/
{IPosPrinterService,IPosPrinterCallback}.aidl`,
`android/app/src/main/kotlin/.../PosPrinterPlugin.kt`,
`lib/features/printing/{data/pos_printer_service.dart,
presentation/ticket_widget.dart, presentation/ticket_renderer.dart}`.
`android/app/build.gradle.kts` gained `buildFeatures { aidl = true }`
(AIDL codegen is off by default in modern AGP — without it the `.aidl`
files compile to nothing), and the manifest gained the Bluetooth
permissions.

All test data cleaned up: every test registration, service, and day
deleted via `tinker`, admin Sanctum tokens revoked.

Phase 4 (A–D) is complete.

## Phase 5: registration search/filter + QR-driven payment at the desk (2026-08-22)

Three pieces: filterable service/day pickers, the desk-payment QR added
to the Phase 4D ticket and shown on screen, and a full scan-to-pay flow
for staff. Backend summary in `dental_laravel/README.md` §"Phase 5";
this section covers the Flutter side and the real bug this phase found.

**Filterable pickers.** `patient_registration_form_screen.dart` swaps
the two `DropdownButtonFormField`s for Material 3 `DropdownMenu`
(`enableFilter: true`), each wrapped in a bare `FormField` to keep the
same required-field validation the plain dropdown had (`DropdownMenu`
has no `FormField` variant of its own). The service field carries a
`key: ValueKey('service-field-$_dayId')` so it fully resets — instead of
drifting out of sync with `_serviceId`, which is cleared from *outside*
the field (in the day picker's `onSelected`) — whenever the day changes.
`register_settings_screen.dart` gets the same idea for its day
checkbox/chip grid, past a `> 6` day-count threshold, with a plain text
filter that only affects which chips are *visible* (already-selected
days stay selected even if filtered out of view).

**QR on the ticket.** `ticket_widget.dart` takes an optional `qrBytes`
and renders it via `Image.memory` beneath the existing ticket fields.
`patient_registration_form_screen.dart`'s `_submit()` fetches the PNG
(`GET /patient-registrations/{id}/qr`, via the same `ApiClient` every
other request uses) right after the registration is created — best
effort: a fetch failure just means the ticket prints without the QR,
same "never block a registration that already succeeded" rule Phase 4D
established for the print step itself. **Verified printing on real
paper** — the taller bitmap (384×498 vs. the pre-QR ~384×330) and the
physical ticket both confirmed the QR is really on it.

**On-screen QR.** `TaskInstanceQrImage` (task-instance-only) is gone,
replaced by a generic `core/widgets/qr_image.dart` (`QrImage(path:
size:)`) that any bearer-gated QR endpoint can use — `TaskInstanceDetailScreen`
was repointed at it rather than kept as a second copy.
`PatientRegistrationListScreen` gained a trailing QR icon per row that
opens the same widget in a dialog.

**The scan-to-pay flow.** `QrScanScreen` gained a `QrScanMode` (`taskInstance`
default, `patientRegistrationPayment`) rather than becoming two
near-duplicate screens — the doctor-only `/scan` route is unaffected,
and a new `/records/patient-registrations/scan` route (reachable from a
scanner icon on `PatientRegistrationListScreen`'s app bar, the staff
entry point that didn't exist before this phase) uses the second mode.
A successful scan pushes `PatientRegistrationPaymentScreen` with the
resolved `RegistrationPaymentState` (registration + payments +
`total_paid` + `is_paid`) as `extra`. That screen shows a paid/unpaid
banner; if unpaid, an amount `TextField` plus `0`/`00`/`000`/clear
quick-digit buttons that append to whatever's typed (type "5", tap
"000" → 5000 — the exact flow described when this was planned) confirm
via `RecordsRepository.createPayment()` (reused as-is — a payload keyed
by `patient_registration_id` instead of `appointment_id`, not a second
method) and print a receipt (`receipt_widget.dart`, sharing
`ticket_row.dart` with `TicketWidget` rather than duplicating the
label/value row layout). Re-scanning an already-paid registration shows
the paid banner and payment list, no charge form. **Verified on the real
device**: print → scan the printed paper → unpaid → pay → receipt
prints → re-scan → paid, twice over (once via `flutter run`'s log,
once via the user's own photos of the printed ticket and receipt).

**A real bug, found live by this being the first real exercise of an
existing code path.** `features/records/domain/payment.dart`'s
`Payment.fromJson` had `amount: (json['amount'] as num?)?.toDouble() ?? 0`
— but Laravel's `decimal` cast serializes to a JSON **string**
(`"amount":"5000.00"`), not a number. The cast threw on every real
payment response. Because the throw happened *after* `POST /payments`
already succeeded, the confirm button reported "تعذر تسجيل الدفع"
(payment failed) while the payment had, in fact, been recorded — this
surfaced on-device as three duplicate 5,000 payments from three
"failed" confirm attempts before the cause was found. `PaymentEntry`
(new this phase, in `registration_payment_state.dart`) already parsed
this correctly with `double.tryParse(json['amount'].toString())`, which
is what made the mismatch obvious; `Payment.fromJson` now does the same.
This is a pre-existing bug in a screen from an earlier phase
(`PaymentFormScreen`'s create path shares `RecordsRepository.createPayment()`
→ `Payment.fromJson`), not something this phase introduced — it had
simply never been exercised end-to-end against a real decimal amount
before. All three duplicate test payments deleted after the fix.

New files: `lib/features/patient_registration/{domain/registration_payment_state.dart,
presentation/patient_registration_payment_screen.dart}`,
`lib/features/printing/presentation/{receipt_widget.dart, ticket_row.dart}`,
`lib/core/widgets/qr_image.dart`. Removed:
`lib/features/task_instances/presentation/task_instance_qr_image.dart`
(superseded by the shared `QrImage`).

All test data cleaned up: every test registration, service, day, and
payment deleted via the API/`tinker`, admin Sanctum tokens revoked.

## Phase 6: task filters, hiding the patients list, registration-list filters, and ticket reprinting (2026-08-22)

Four independent pieces. Backend summary in `dental_laravel/README.md`
§"Phase 6"; this section covers the Flutter side.

**Tasks (المهام) cascading filters — `features/tasks_admin/`.**
`task_list_screen.dart` gained three cascading `DropdownMenu`s (نوع
الدراسة → المرحلة → القسم, same `enableFilter: true` pattern as every
other picker added this project), converted from `ConsumerWidget` to
`ConsumerStatefulWidget` to hold the selection state. The task list
itself is only fetched/rendered once both stage and department are
chosen — matching dental_clinics2's `admin/manage_tasks.php` exactly, a
placeholder text shows otherwise.

**Real gap found and fixed as part of this**: `core/data/lookup_repository.dart`'s
`LookupItem` only ever carried `{id, name}` — the API already returned
`stage_id`/`education_type_id` for stages/departments (confirmed via
`Api\LookupController`), but the client discarded them, so the
client-side cascading filtering this screen needed wasn't actually
possible until `LookupItem` gained two additional nullable fields.
Additive and safe — every other caller (Patients, Doctors, Appointments
admin) just gets `null` for fields their endpoint doesn't return.

`TasksAdminRepository.list()` grew `{stageId, departmentId}` optional
params; `taskAdminListProvider` became a `.family` keyed on
`(stageId, departmentId)` (a Dart record, not a class — free `==`/`hashCode`
is exactly what a family key needs), mirroring
`patientRegistrationListProvider`'s existing family shape.

**A real bug, found live by this being the first time this screen was
ever exercised against a task with a non-null grade.** `TaskAdmin.grade`
was `(json['grade'] as num?)?.toDouble()` — but `Task.grade` is a
`decimal:2` cast in Laravel, which serializes to a JSON *string*
("100.00"), not a number. The very first cascade test (primary
Education → Fourth Stage → operative) hit a real task with `grade:
"100.00"` and the whole list crashed to "تعذر التحميل." with no further
detail in `flutter run`'s log or logcat — the exception was swallowed
inside the FutureProvider's error state with nothing printed beyond the
successful HTTP response, which is what made this one harder to spot
than Phase 5's `Payment.amount` version of the same bug: there, the
generic snackbar text was the tell; here, only re-reading `TaskAdmin.fromJson`
against the real (already-logged) response body revealed it. Fixed with
the same `double.tryParse(json['grade']?.toString() ?? '')` pattern.
Once the pattern was known, `grep -rn "as num?" lib/` turned up an
identical latent bug in `features/task_instances/domain/task_instance.dart`
(`TaskInstance.grade`, same `decimal:2` cast on the model) — fixed
proactively, unverified against live data (no graded task instance was
on hand to reproduce it against), but the fix is the same one-line
change and the reasoning transfers directly. A third hit,
`features/records/domain/appointment.dart`'s `paidTotal`, was checked
and is **not** the same bug — it's `$this->payments->sum('amount')`
server-side, a PHP `Collection::sum()` over decimal-cast (string)
values, which PHP coerces to a real number through arithmetic before
Laravel ever JSON-encodes it; confirmed by reasoning through
`AppointmentResource`, not left as an assumption.

**"قائمة المرضى" hidden, not removed — `features/records/`.**
`records_hub_screen.dart`'s `items` list drops the `('المرضى', ...,
'/records/patients')` tuple (4 → 3). `app_router.dart`'s
`/records/patients*` routes and `PatientListScreen`/`PatientFormScreen`
are untouched — confirmed necessary, not just cautious, by reading how
the web's `AppointmentController.php` feeds its patient dropdown
directly from `Patient::orderBy('name')->get(...)` with no other
patient-creation path in that form.

**Patient Registration list — `features/patient_registration/presentation/patient_registration_list_screen.dart`.**
Converted to `ConsumerStatefulWidget` to close a gap the repository/provider
already half-supported: `PatientRegistrationRepository.list()` and
`patientRegistrationListProvider` already accepted a search string, but
the screen never had search UI at all. Now has a debounced (`Timer`,
350ms — Flutter has no built-in debounce) search `TextField` plus day/service
`DropdownMenu` filters, sourced from the existing `registerDaysProvider`/`servicesProvider`.
The family parameter grew from a bare `String?` to a
`PatientRegistrationFilter` record (`{search, registerDayId, serviceId}`)
— checked for other callers first (only untyped `ref.invalidate(patientRegistrationListProvider)`
calls elsewhere, unaffected by the type change).

**Ticket reprinting.** Each row's `ListTile` gained a print `IconButton`
(Android-only, `!kIsWeb && Platform.isAndroid`) next to the existing QR
icon, running the identical best-effort sequence
`patient_registration_form_screen.dart::_submit()` already ran once at
creation time — fetch the QR bytes (best-effort, ticket still prints
without it on failure), `renderWidgetToPng(TicketWidget(...))`,
`PosPrinterService.printTicket()`. No new printing infrastructure; this
was the first *second* call site for the whole Phase 4D/5 print stack.

**Verified end-to-end on the real Android POS device**: cascading task
filters (list correctly hidden, then correctly populated once the fixed
`grade` parsing was in place); "المرضى" gone from the records hub while
`/records/patients` and the appointment patient picker still work;
registration search narrowed a full list to one match; reprint fetched
the QR, rendered the ticket, and printed via the Bluetooth SPP fallback
— confirmed via logcat's `finish success=true` +
`CURRENT_TASK_PRINT_COMPLETE_ACTION` broadcast, the same corroboration
standard every prior print in this project has used.

All test data (test days/services/registrations created for
verification) cleaned up via the API/`tinker`; test Sanctum tokens
revoked.

## NFC doctor lookup (2026-08-23)

Adds `nfc_manager` (resolved to **4.1.1** by `flutter pub add` — 4.2.1
exists but doesn't satisfy this project's SDK constraint) for two things:
scanning a tag to fill `nfc_tag_id` on the existing doctor create/edit
form (`features/doctors_admin/presentation/doctor_form_screen.dart`,
just another field the existing "حفظ" persists — no separate "link"
endpoint needed), and a new, deliberately small staff screen,
`features/task_progress_admin/presentation/nfc_lookup_screen.dart`
(reachable from the admin hub, `تقدم المهام (NFC)`): scan → resolve
doctor (+ an unambiguous pending-task shortcut if there is one, per the
user's requirement) → "ابدأ المهمة". This does **not** replicate the
web's `TaskProgress/Index.vue` day→stage→group doctor matrix — confirmed
during planning that no Flutter equivalent of that screen exists, and
rebuilding it wasn't the ask.

**UID extraction — verified against the real installed package source,
not assumed.** The pub.dev doc's summary suggested trying each
platform-specific tech class (`NfcAAndroid`, `NfcBAndroid`, ...) in
turn. Reading the actual installed `nfc_manager-4.1.1` source
(`lib/src/nfc_manager_android/tags/tag.dart`) found a simpler, tech-agnostic
path: `NfcTagAndroid.from(tag)?.id` returns the tag's raw UID regardless
of which NFC standard it speaks, with no per-tech fallback chain needed.
Shared between both scan sites via `core/nfc/nfc_uid_reader.dart` rather
than duplicating the session-start/discover/stop boilerplate.

`AndroidManifest.xml` gained `android.permission.NFC` and
`<uses-feature android:name="android.hardware.nfc" android:required="false"/>`
— `required="false"` so the app still installs on non-NFC devices, since
nothing else in this project assumes universal NFC hardware (mirrors how
`android.hardware.usb.host` is declared non-required for the same
reason in the printer-settings work below).

**Backend verified fully via curl** (both `nfc-scan` response branches,
`start()`, the blank-`nfc_tag_id`-becomes-`''`-not-`null` bug found and
fixed — see `dental_laravel/README.md` §"NFC doctor lookup" for the full
account) before touching the device at all.

**Real device verification found a genuine hardware fault, not a code
bug.** On the connected POS terminal (serial `202203011615`), the doctor
form's NFC scan button correctly reached
`NfcManager.instance.checkAvailability()` and got back a non-`enabled`
result, so the app's own error path fired exactly as written
("تعذرت قراءة البطاقة: ... قارئ NFC غير متاح..."). Investigating why —
`adb shell dumpsys nfc` showed `mState=turning on` stuck indefinitely;
`adb shell svc nfc enable` didn't change that. `adb logcat` showed the
actual cause, repeated identically across three separate enable
attempts: the device's own NFC HAL (`SecHAL`, talking to `/dev/sec_nfc`)
fails at `nfc_hal_open_sm: Get Bootloader information` with
`__send_to_bootloader: Failed to send header` — the NFC controller chip
itself never responds. `adb shell pm list features` reporting
`android.hardware.nfc`/`.hce`/`.hcef` reflects this device family's
Android build, not this specific unit's actually-functioning hardware —
the same class of "documented/declared capability that doesn't actually
work on this exact physical unit" this project already hit once before
with the built-in POS printer's AIDL path (Phase 4D), which is why that
feature has a Bluetooth-SPP fallback today. There's no equivalent
software fallback for NFC (it's read-only tag hardware, nothing to
substitute), so this specific capability stays backend-verified +
code-reviewed-against-the-real-package-API but not physically
tap-tested, until either this unit's NFC hardware is confirmed working
by other means or a second, NFC-functional device is available. Flagged
plainly rather than claimed as tested — confirmed with the user before
moving on to Phase B (printer settings) rather than blocking on it.

New files: `lib/core/nfc/nfc_uid_reader.dart`,
`lib/features/task_progress_admin/{domain/nfc_lookup_result.dart,
data/task_progress_repository.dart, presentation/nfc_lookup_screen.dart}`.

## Generalized printer connectivity (2026-08-23)

Extends the single hardcoded built-in POS printer with a settings screen
(`lib/features/printing/presentation/printer_settings_screen.dart`,
reachable from the admin hub, `إعدادات الطابعة`) offering three
connection types — built-in (unchanged default), Bluetooth (search/pair,
reusing Android's own `ACTION_PAIRING_REQUEST` system dialog for the
PIN — this app never builds a custom PIN UI), and USB — plus a 58mm/80mm
paper-width choice. Settings persist via `shared_preferences`
(`printer_settings_repository.dart`), not `flutter_secure_storage`
(reserved for the actual secret, the Sanctum token) — a printer choice
isn't a secret. 80mm maps to 576 raster dots, 58mm to 384 (unchanged),
both standard ESC/POS conventions at ~8 dots/mm.

**A gap the initial research missed, caught before implementation**:
picking 80mm would have had zero visible effect unless the *rendered
bitmap width* also changed, not just the raster width Kotlin encodes —
`TicketWidget`/`ReceiptWidget` gained a `widthDots` parameter (was a
hardcoded `Container(width: 384)`), and all three print call sites
(`patient_registration_form_screen.dart`, `..._list_screen.dart`'s
reprint, `..._payment_screen.dart`) now read `printerSettingsProvider`
before rendering. `PosPrinterService.printTicket(pngBytes)` itself keeps
its existing signature — it reads stored settings internally and
forwards `connectionType`/`bluetoothAddress`/`usbDeviceName`/
`paperWidthDots` to the platform channel, so no call site needed a new
*argument*, only the `TicketWidget(...)` construction line above it.

**`PosPrinterPlugin.kt` generalized, not rewritten from scratch**: the
existing AIDL-first/Bluetooth-SPP-fallback path (Phase 4D's fix for this
same device's non-functional AIDL service) is untouched and still the
default for `connectionType: builtin`. New: `printViaBluetoothAddress()`
connects directly to an already-paired device by address, skipping AIDL
entirely; `printViaUsb()` is genuinely new native code (`UsbManager`,
`UsbDeviceConnection`, finds the first bulk-OUT endpoint across all
interfaces — not assumed to be interface 0 — and chunks `bulkTransfer()`
calls at the endpoint's own `maxPacketSize`, since a full ticket exceeds
one transfer). `bitmapToEscPosRaster()`'s dots-per-line went from a
hardcoded constant to a parameter. New MethodChannel calls
(`listPairedDevices`, `pairDevice`, `listUsbDevices`,
`requestUsbPermission`) plus one `EventChannel`
(`.../pos_printer/bt_scan_events`) streaming live `ACTION_FOUND`
results — a stream fits discovery better than a request/response call.
Runtime Bluetooth permissions (API 31+) are requested Dart-side via
`permission_handler`, not inside the plugin, because `PosPrinterPlugin`
is constructed with `applicationContext` only (confirmed by reading
`MainActivity.kt` before assuming otherwise) — it has no `Activity` to
request permissions from.

**A real build-breaking version conflict, found and fixed**:
`permission_handler: ^13.0.1`'s own transitive `permission_handler_android`
resolved independently to 14.0.0, whose `android/build.gradle.kts` uses
the newer `kotlin { compilerOptions { jvmTarget } }` Gradle DSL —
incompatible with this project's Kotlin Gradle Plugin 2.1.0 / AGP 8.9.1,
which are pinned deliberately for Android 8.1 (API 27) compatibility,
not something to bump for one plugin. Fixed with a `dependency_overrides:
permission_handler_android: 13.0.1` pin in `pubspec.yaml` (confirmed via
pub.dev's version history that 13.0.1 predates the DSL change by
roughly 17 months) rather than touching the toolchain pins.

**Three separate `flutter build apk` attempts were needed for reasons
unrelated to the code** — the first failed on the Kotlin DSL issue
above; the second and third hit `dl.google.com` (Google's Maven
repository) being extremely slow/unstable (`curl` to the same host
independently showed 15+ second downloads and intermittent connection
resets, confirming a real network issue rather than a build
misconfiguration). The third attempt succeeded after ~40 minutes,
confirming the Kotlin/Dart code itself had been correct since the first
attempt.

**A real layout crash found and fixed during on-device verification,
not present in `flutter analyze`** (a pure runtime/theme interaction,
invisible to static analysis): `app_theme.dart`'s `FilledButtonThemeData`
and `OutlinedButtonThemeData` both default `minimumSize` to
`Size.fromHeight(44)` — i.e. **infinite width** — intended for
standalone full-width buttons like the "حفظ" save button at the bottom
of this same screen. Every inline button placed next to other content in
a `Row` (the Bluetooth "بحث" scan button, the USB "تحديث" refresh
button, and the "تحديد"/"اقتران" buttons used as `ListTile.trailing`)
inherited that same infinite-width minimum and crashed
`performLayout()` with "BoxConstraints forces an infinite width" —
caught live via the running `flutter run` console, not by reading code:
the crash silently ate the whole row (an `adb shell uiautomator dump`
taken at the time came back with an anomalously empty widget hierarchy,
which was itself the symptom, not a separate bug — the render tree had
faulted mid-layout). Fixed by giving each of the five affected buttons
its own `style: FilledButton.styleFrom(minimumSize: const Size(64, 44))`
/ `OutlinedButton.styleFrom(minimumSize: const Size(64, 36))` override,
rather than touching the shared theme (which is correct for every other
button in the app that relies on the full-width default).

**A second, smaller real gap fixed during the same verification pass**:
reopening the settings screen with Bluetooth or USB already selected
(the persisted choice from a previous save) left the paired/USB device
list empty until the user re-tapped the segment, because
`_loadPairedDevices()`/`_loadUsbDevices()` were only wired to
`SegmentedButton.onSelectionChanged`, never to the initial seed. Fixed
by triggering the appropriate load from `_seed()` via a post-frame
callback when the already-persisted connection type warrants it.

**Fully verified on-device** (POS terminal, serial `202203011615`,
after both fixes above): connection-type switching and paper-width
radios render and persist correctly across screen reopen (confirmed
Bluetooth+80mm survived a reload before being reset back to the
sensible builtin/58mm default); Bluetooth paired-devices list populates
immediately on open; live scan via the `EventChannel` correctly
streamed a real discovered device into the UI with a working "اقتران"
button; USB tab correctly shows "لا توجد أجهزة USB متصلة حالياً" (this
device has no `android.hardware.usb.host` feature, as already known and
accepted going into this phase — the empty state itself is the expected,
correct result, not an unverified gap). **Regression-tested the
untouched builtin path** by reprinting an existing patient ticket at
both paper widths — logcat confirmed `bitmap 384x498` and
`bitmap 576x498` respectively, the same `AIDL path failed, falling back
to Bluetooth` → `builtin bluetooth fallback device IposPrinter` →
`writing NNNNN ESC/POS bytes` → `finish success=true` sequence as
before this phase, at both widths. USB *printing* itself (as opposed to
the device-list screen) remains unverified for the reason stated above —
would need a USB-host-capable Android device and a real USB ESC/POS
printer.

New files: `lib/features/printing/{domain/printer_settings.dart,
data/printer_settings_repository.dart,
presentation/printer_settings_providers.dart,
presentation/printer_settings_screen.dart}`. Rewritten:
`android/app/src/main/kotlin/.../PosPrinterPlugin.kt`,
`lib/features/printing/data/pos_printer_service.dart`.

## Bluetooth device scan silently missing real devices (2026-08-23)

**Real bug, reported by the user, not found by testing**: a Bluetooth
printer visible in the phone's own Bluetooth settings never appeared in
the printer-settings screen's own "بحث" scan, even though the scan
completed with no error and other devices (already-paired ones) showed
fine.

**Root cause, confirmed live via `adb`, not guessed**: on Android 6–11
(API 23–30 — this project's test device is API 27), classic Bluetooth
discovery (`BluetoothAdapter.startDiscovery()` /
`BluetoothDevice.ACTION_FOUND`) silently withholds results from any app
that lacks a location permission — `startDiscovery()` still returns
success and `ACTION_DISCOVERY_FINISHED` still fires on schedule, the
found devices are just never delivered to that app's `BroadcastReceiver`.
The system Bluetooth settings app is a privileged system app, exempt
from this restriction, which is exactly why the same printer showed up
there but nowhere in this app. `AndroidManifest.xml` had no location
permission declared at all — only `BLUETOOTH_SCAN` (the Android 12+
permission, irrelevant to this test device), so there was nothing for
`permission_handler` to even request that would have covered the gap.

**Fix**: added `ACCESS_FINE_LOCATION` with `android:maxSdkVersion="30"`
to the manifest (scoped to exactly the OS range that needs it —
`BLUETOOTH_SCAN`'s existing `neverForLocation` flag already covers
discovery on API 31+ without exposing location to the user there), and
`printer_settings_screen.dart`'s `_scanBluetooth()` now requests
`Permission.locationWhenInUse` alongside the Bluetooth permissions. Not
treated as a hard gate on newer Android — the permission is never even
declared in the manifest for API 31+, so requesting it there always
reads as denied, and blocking the scan on that would break scanning on
every device that doesn't need this at all. Denied-but-relevant (API
≤30) shows a snackbar explaining why some devices may still be missing,
rather than failing silently a second time in a different way.

**Verified live**: rebuilt and reinstalled on the test device (this
pulled up Android's own "Review permissions" screen, since adding a new
dangerous permission to an already-installed app triggers that on
reinstall — toggled it on, confirmed, `flutter run` continued
normally). Re-ran the same scan that previously missed the printer;
it now appears under "أجهزة مكتشفة" alongside the devices that were
already showing.

## Staff dashboard redesign (2026-08-23)

The staff (non-doctor) landing screen was a placeholder — two plain
centered buttons ("السجلات" / "الإدارة") with nothing else. Replaced
with an actual dashboard in `home_screen.dart`'s new `_StaffDashboard`
widget: a welcome header (name + role), a 2×2 grid of "اختصارات سريعة"
for the actions staff reach for most often (تسجيل مريض جديد، المواعيد،
الدفعات، تقدم المهام NFC — routes that already existed, just not
one tap away from login), and the two module hubs re-styled as proper
cards (icon, title, subtitle, chevron) instead of a `FilledButton`/
`OutlinedButton` pair. No new backend calls — purely a client-side
layout change, so nothing to curl-verify here.

`admin_hub_screen.dart`'s flat 14-item list was reorganized into four
sections — "إدارة الأطباء" / "البيانات الأساسية" / "سير العمل" /
"الإعدادات" — the same grouping `AuthenticatedLayout.vue` (the web
navbar) was reorganized into the same day, so the two surfaces now
share one mental model instead of the web presenting a curated
structure and the app dumping everything into one list. "المجموعات"
sits in "إدارة الأطباء" here for the same reason it does on the web:
it's grouped by *subject*, not by permission tier, since unlike the
web's navbar this screen doesn't need to hide/show individual items —
`AdminHubScreen` is only ever reached by staff who already passed the
`/admin` route's own gate.

Both screens verified live on the test device: the dashboard's shortcut
grid renders without overflow and the "المواعيد" shortcut correctly
opens the Appointments list; the grouped admin hub scrolls through all
four sections cleanly with dividers between items in each card.

## Tasks: education-type cascade in the form, filter carry-over, and an أساسية/اختيارية flag (2026-08-23)

Ported alongside the same change on the web (see `dental_laravel/README.md`'s
matching entry for the shared backend/schema details — new
`tasks.is_required` column, and a real `Api\TaskController::store()` bug
found and fixed there).

`task_form_screen.dart` previously had no education-type field at all —
just an unfiltered, independent stage `DropdownButtonFormField`. Added
one (via the already-existing `taskEducationTypesProvider`), filtering
the stage field's options by it exactly like `task_list_screen.dart`'s
own cascade already does (`items.where((s) => s.educationTypeId ==
_educationTypeId)`, `ValueKey('stage-$_educationTypeId')` to force a
clean reset on change) — inlined rather than extracting a shared widget,
since neither this codebase nor the equivalent web Vue pages share
cascade logic across files today. Editing an existing task derives its
education type from its stored stage (a task doesn't have one directly),
the same trick used on the web's `Tasks/Edit.vue`.

`TaskListScreen`'s FAB now passes its current `_stageId`/`_educationTypeId`
selections as router `extra` to `/admin/tasks/new` (both `null` when the
list hasn't been filtered yet, which the form already treats as "start
empty, pick manually") — `app_router.dart`'s route builder reads them
into `TaskFormScreen`'s two new constructor parameters. Added the
أساسية/اختيارية field using this project's established `RadioGroup<T>`
pattern (same one used for the printer paper-width choice), defaulting
new tasks to أساسية; `task_admin.dart` gained `isRequired`, and
`task_list_screen.dart`'s task tiles now show a small badge for it.

**Verified live on-device**: created a task with the education-type
filter unset (education type and stage both opened empty, as expected),
confirmed the stage dropdown stays disabled until an education type is
picked and then only lists stages belonging to it (a device with stages
across two education types was on hand for this — only the matching
stage showed), selected اختيارية and saved, then confirmed via a direct
API fetch that `is_required: false` persisted correctly (not the
`store()` bug described in the web entry — that bug was specific to the
immediate `POST` response body, and this test read the value back with a
separate `GET`, which was never affected). Separately confirmed the
filter-carry-over path: set the list's education-type + stage filter,
tapped "+", and the create form opened with both already selected.

## Task progress: full web-equivalent matrix, NFC folded into the search box (2026-08-23)

The earlier "تقدم المهام (NFC)" screen (`nfc_lookup_screen.dart`) was
deliberately scoped to just the NFC shortcut, explicitly *not*
replicating the web's `TaskProgress/Index.vue` matrix. The user asked
for the opposite emphasis: bring this screen back to full parity with
that web page, and fold NFC in as the doctor search box's alternate
input — not a separate screen. `nfc_lookup_screen.dart` is removed;
`task_progress_screen.dart` replaces it as `/admin/task-progress`
(admin hub tile renamed from "تقدم المهام (NFC)" to "تقدم المهام", icon
swapped from `Icons.nfc` to `Icons.fact_check_outlined` since NFC is no
longer the headline feature).

New backend surface required first (see `dental_laravel/README.md`'s
matching entry for the three extracted `App\Services\TaskProgress*`
classes both this app and the web page now share): `GET /task-progress/
filters`, `GET /task-progress/groups/{group}`, `PUT /task-progress/
instances/{id}/complete`, `PUT /task-progress/instances/{id}` — added to
`Api\TaskProgressController` alongside the existing `nfcScan()`/`start()`.

**Screen structure** (`task_progress_screen.dart`): day → education
type/stage (optional narrowing, not required — matches the web's own
`index()`, which only gates the group list on `day` being set) → group
list → tapping a group loads its department-tabbed doctor matrix
(`TabController` managed manually, not `DefaultTabController`, so NFC
matching can read the active tab's data directly). Each department tab
has a search box (leading search icon, trailing NFC icon) filtering the
doctor list client-side by name/username, then expandable doctor rows
(`ExpansionTile`) showing per-slot task cards with a status badge and
the same three actions the web has: "بدء المهمة" (small optional-notes
dialog → `start`), "تأشير كمكتملة" and "تعديل" (both a shared grade+notes
dialog → `completeInstance`/`updateInstance`) — any action invalidates
the group provider to refetch, mirroring the web's `reloadGroup()`.
New domain file `domain/task_progress_group.dart` mirrors
`TaskProgressFilters`/`TaskProgressGroupSummary`'s JSON shapes exactly;
existing `nfc_lookup_result.dart` (`NfcLookupResult` etc.) is unchanged
and still used for the `nfcScan()` call itself.

**NFC as the search box's alternate input**: tapping the NFC icon runs
the same `NfcUidReader.readUid()` → `nfcScan()` flow the old screen had.
Every department tab shares the same doctor list (only their task cards
differ — confirmed by reading `TaskProgressGroupSummary::build()`, which
computes `$doctors` once outside the per-department loop), so membership
only needs checking once regardless of which tab is active. A match
fills the search box with the doctor's name (running the same filter
typing would) and expands their row; `kind == pending_task` also
surfaces a snackbar naming the pending task. No match — a snackbar says
so plainly; there's no endpoint to jump across groups a doctor belongs
to, and the web's own QR-in-page doesn't do that either.

**A real layout bug found live, not by reading code**: the filter row
(three dropdowns) stayed visible even after drilling into a group's
detail view. Typing in the new search box opened the keyboard, shrinking
the available height, and the fixed filter row plus the group header/
tabs/search box together no longer fit — a genuine `BOTTOM OVERFLOWED BY
121 PIXELS` render error, not just a cosmetic complaint. Fixed by hiding
the filter row entirely once a group is selected (its own back arrow
already returns to it) — this is also a better use of the limited screen
space than showing three dropdowns nobody can interact with mid-drill-down.

**Verified live on-device** (`202203011615`): walked the full day → group
→ department cascade against real seeded data; expanded a doctor row and
confirmed the task-card grade/status matched a direct API fetch of the
same group exactly; started a task, marked it completed with a grade,
edited it, and confirmed the list refreshed correctly after each action;
confirmed the grade-exceeds-task-grade rejection surfaces correctly;
reproduced and fixed the overflow bug above, then confirmed the search
box works correctly with the keyboard open; tapped the NFC icon and
confirmed it correctly surfaces "تعذر التعرف على البطاقة" — this
device's already-known NFC hardware fault (see the earlier "NFC doctor
lookup" entry), not a new limitation, and expected given that fault
remains unresolved. All test task instances created during verification
were deleted afterward.

## Payments and appointments linked to patient registrations (2026-08-23)

Flutter side of a web+API+Flutter change; see `dental_laravel/README.md`'s
matching entry for the backend/migration detail (including two real MySQL
FK bugs found while adding `appointments.patient_registration_id`).

**Payments** (`records/domain/payment.dart`,
`payment_list_screen.dart`/`payment_form_screen.dart`): added
`patientRegistrationId`/`Name`/`Phone` fields and a `personName` getter
(`patientRegistrationName ?? appointmentFullName`). The form gained a
source-type toggle (`_source`: `'appointment'`/`'registration'`) between
the existing appointment picker and a new registered-patient picker.
`paymentListProvider` changed from a plain `FutureProvider.autoDispose`
to `.family<..., String?>` keyed on the new search filter.

**Appointments** (`records/domain/appointment.dart`,
`appointment_form_screen.dart`/`appointment_list_screen.dart`): same
shape — added `patientRegistrationId`/`Name`/`Phone` + a `personName`
getter, and `_pickPatient()`'s `PatientListScreen(pickMode: true)`
became `_pickRegistration()`'s
`PatientRegistrationListScreen(pickMode: true)` (the same picker Phase 1
added to `patient_registration_list_screen.dart`). The submit payload
sends `patient_registration_id` instead of `patient_id`. Editing a
legacy appointment (registration null, only the old `patient_id` set)
no longer forces a pick — `_submit()`'s validation only requires a
registration on **create**, matching the backend's
`sometimes`/`required` split; an informational line explains this when
editing such an appointment.

A real, unrelated bug found live while verifying this on-device
(`202203011615`): `_pickDate()`'s `showDatePicker` used
`initialDate: _appointmentDate ?? DateTime.now()` against a hardcoded
`firstDate: DateTime(2020)`. This device's system clock reads **2010**,
so `DateTime.now()` fell before `firstDate` and tripped
`showDatePicker`'s own assertion (`initialDate must be on or after
firstDate`), crashing the picker outright on every tap — not a Phase 2
regression (the code was already this way), but it fully blocked date
entry on this device and would do the same for any real device with a
wrong clock. Fixed by clamping `initialDate` into `[firstDate, lastDate]`
before calling `showDatePicker`. The same unclamped pattern exists in
three other screens (`payment_form_screen.dart`,
`dynamic_section_form.dart`, `academic_session_form_screen.dart`) —
left as-is for now since they weren't part of this task and only
misbehave on a device with a misconfigured clock, but worth the same
fix if one of them is touched again.

**Verified live on-device** (`202203011615`, and via curl against both
the physical-device LAN IP and localhost): logged in as a temporary
staff test user, granted `patients`/`appointments`/`tasks` `view`
permissions (discovering the `PermissionManager` 5-minute cache gotcha
described in the backend README entry along the way), created a new
appointment through the registered-patient picker + task picker + the
newly-fixed date picker, confirmed it saved (`تم إضافة الموعد`), confirmed
the list tile shows the registration's name, confirmed via
`GET /api/v1/appointments` that `patient_registration_id` was set and
`patient_id` was null, opened it for edit and confirmed the registration
pre-fills correctly. All test data (the appointment, the temporary staff
user, its permission grants) deleted afterward.

## Diagnosis (task) field on patient registration (2026-08-23)

Third phase of the same four-phase request; see `dental_laravel/README.md`'s
matching entry for the backend/migration detail.

`core/data/lookup_repository.dart`'s `LookupItem` gained a second,
separate additive pair — `stageName`/`educationTypeName`, parsed from
`tasks()`'s nested `stage.education_type` (now returned by
`TaskResource`, backend change in this same phase) — alongside the
existing `stageId`/`educationTypeId` pair that only `stages()`/
`departments()` populate. Both pairs coexist on the same shared
`LookupItem` class; callers that don't need one pair simply see it as
null.

`patient_registration_form_screen.dart` gained a "التشخيص" picker
reusing `tasksLookupProvider` (already used by
`appointment_form_screen.dart` — no new endpoint call, per the plan),
plus an informational `Text` below it showing the selected task's
`stageName`/`educationTypeName` joined with " · " — the same
"pick, then show read-only context" pattern already used for
`AppointmentFormScreen`'s legacy-appointment hint text. `_submit()`
passes `taskId: _taskId` through to `PatientRegistrationRepository.create()`,
which now accepts an optional `taskId` parameter.
`domain/patient_registration.dart`'s `PatientRegistration` class gained
`taskId`/`taskTitle`/`stageName`/`educationTypeName` fields parsed from
the resource's flattened `task` block — the two existing call sites that
build a placeholder `PatientRegistration` (`appointment_form_screen.dart`,
`payment_form_screen.dart`'s registration-picker seeding) needed the four
new required named arguments added (all `null`, since neither call site
has that data).

**Verified live on-device** (`202203011615`): logged in as a temporary
staff test user (granted `patients`/`tasks` permissions), registered a
patient with a diagnosis task selected, confirmed the informational line
showed "Fourth Stage · primary Education" — matching a direct API check
of the same task — submitted, and confirmed via
`GET /api/v1/patient-registrations?search=...` that `task_id` round-tripped
correctly. All test data (the registration, day, service, staff user and
its permissions) deleted afterward.

## Bigger QR/text and the teaching-hospital logo on the ticket (2026-08-23)

Fourth and final phase of the same four-phase request; see
`dental_laravel/README.md`'s matching entry for the web/Blade side.

`ticket_widget.dart`: the QR went from a flat `180×180` to
`widthDots * 0.55` (≈211px at 58mm/384dot, ≈317px at 80mm/576dot) so it
stays proportionate at both paper widths instead of being flat-sized;
title/subtitle/QR-caption/date font sizes bumped a few points each,
matching the web bump's proportions. `ticket_row.dart` (shared with
`ReceiptWidget`, the payment-desk receipt) also got a `16px → 18px` row
bump — the request was specifically about the registration ticket, but
`ticketRow()` is the one row renderer both templates share, and a
uniformly bigger, more legible thermal-print row isn't something
`ReceiptWidget` would want to opt out of.

The logo is genuinely new here — `TicketWidget` was text-only before.
Added a `logoBytes` parameter (`Uint8List?`), rendered via
`Image.memory` above the title, same fail-open contract as the existing
`qrBytes` (null just omits it, never blocks printing). Fetched by the
caller exactly like `qrBytes` already is — `clinicSettingsProvider`, then
a raw-bytes `GET` of the URL — in both places a ticket gets rendered:
`patient_registration_form_screen.dart::_submit()` (the original print)
and `patient_registration_list_screen.dart::_reprintTicket()`. No new
capture-timing logic needed; `ticket_renderer.dart`'s existing two-frame
wait (already there for `qrBytes`) covers the logo the same way.

`ClinicSettings` (the domain class) gained `universityLogoUrl` alongside
the existing `logoUrl`, plus a `ticketLogoUrl` getter
(`universityLogoUrl ?? logoUrl`) — the same university-logo-first
precedence `print.layout.blade.php`'s letterhead already uses, so the
Flutter ticket and the web ticket prefer the same image. The
login-screen splash logo (bundled asset, unrelated to this provider)
is untouched.

A real, cross-device discovery made verifying this on-device: the
backend's `logo_url`/`university_logo_url` are absolute URLs built from
Laravel's `APP_URL` config (`Storage::disk('public')->url(...)`), not
relative paths — the same class of host-mismatch already solved for the
API itself via `--dart-define=API_BASE_URL` (see the "Bluetooth scan
fix" entry's neighbor, Phase 2's appointments entry), but this is the
*first* feature to actually fetch one of these URLs from a physical
device rather than just displaying a same-machine `Image.network`. With
`APP_URL=http://localhost/...` (this project's dev default), a physical
device can never reach that URL — `localhost` resolves to the phone
itself. Not a code bug (the app already fails open exactly as designed),
but worth documenting: **a real deployment must set `APP_URL` to a host
the client devices can actually reach**, or every absolute-URL-based
asset (this logo included) silently degrades to "missing" on physical
hardware while working fine from the same-machine desktop/emulator
targets. Confirmed by temporarily pointing `APP_URL` at the LAN IP for
this one verification pass (reverted immediately after).

**Verified live on-device** (`202203011615`): registered a patient with
a temporary logo uploaded to `ClinicSetting.clinic_logo` and `APP_URL`
pointed at the device-reachable LAN IP; confirmed via the raw Dio log
that `GET /clinic-settings` returned the LAN-IP `logo_url`, the
subsequent logo fetch returned `200` with the expected PNG byte count,
and the native printer plugin logged `bitmap 384x637` (taller than
before, from the added logo + bigger text/QR, with no overflow or
capture exception) and `finish success=true error=null`. All test data
(registration, day, service, staff user + permissions, the uploaded
logo file, the `clinic_logo` DB value) reverted afterward, `APP_URL`
restored to its original value.

## Ticket-feed printing animation (2026-08-23)

Flutter-only, no backend/API changes. Requested visual: the ticket looks
like it slides out of the screen toward the printer while it prints,
rather than the previous silent wait with no feedback.

New `showTicketPrintAnimation<T>()`
(`lib/features/printing/presentation/ticket_print_animation.dart`) shows
a non-dismissible dialog — a fixed printer-slot graphic with "جاري
الطباعة..." above a `ClipRect`/`Align(heightFactor: ...)` reveal of the
*actual* rendered ticket PNG (the same bytes already going to the
printer, not a placeholder), animated top-to-bottom over 1.1s so it
looks like paper feeding out from the slot. Runs the real print call
(`task`) concurrently with the visual animation via `Future.wait`, so a
fast print doesn't truncate the animation and a slow one doesn't leave
it frozen half-fed; holds briefly on the fully-revealed ticket, then
closes itself. Wired into both places a ticket gets printed —
`patient_registration_form_screen.dart::_submit()` (new registration)
and `patient_registration_list_screen.dart::_reprintTicket()` — wrapping
the existing `posPrinterServiceProvider.printTicket()` call in place,
with the surrounding try/catch and error snackbar untouched. Deliberately
scoped to the ticket only (not `ReceiptWidget`'s payment receipt), per
the request.

**Verified live on-device** (`202203011615`): registered a test patient,
captured the animation mid-flight via rapid back-to-back screenshots and
confirmed the fully-revealed ticket + "جاري الطباعة..." label render
correctly with no layout overflow; confirmed the real print still
completes successfully and the dialog closes itself automatically.
While setting up this verification pass, found XAMPP's MySQL and Apache
had both stopped running (unrelated to this change — a prior system
network hiccup during an earlier verification pass) and restarted them
before retrying. All test data (registration, day, service, staff user +
permissions) deleted afterward.

## Two real Task Progress bugs, reported live by the user (2026-08-23)

Both found by reproducing the user's exact report ("تقدم المهام لا يعمل
بتطبيق فلتر") on-device rather than guessing from the description alone.

**1. Home dashboard shortcut crashed straight to "Page Not Found"** —
`home_screen.dart`'s `_StaffDashboard` quick-actions grid still pushed
`/admin/task-progress/nfc`, the old NFC-only screen's route. That route
was removed when the screen was superseded by the full day→group→
department→doctor matrix (see the "Task progress: full web-equivalent
matrix" entry above) — the admin hub's own tile was updated at the time,
but this second, separate reference on the home dashboard was missed.
Every tap threw `GoException: no routes for location:
/admin/task-progress/nfc`, confirmed live via screenshot. This alone
made the feature simply unreachable from the home screen — "doesn't
work" in the most literal sense. Fixed by pointing it at
`/admin/task-progress` and relabeling it (dropping the stale "(NFC)"
suffix, matching the admin hub tile's own wording).

**2. The stage filter dropdown could show a stale, invalid selection
after changing education type** — `task_progress_screen.dart`'s
`_FilterRow` used `DropdownButtonFormField`'s `initialValue`, which (like
`appointment_form_screen.dart`'s day→service picker, the same bug class
fixed earlier this session) is only read once at first build, not
re-read on every rebuild. `onEducationTypeChanged` resets `stageId` to
`null` and swaps in a different stage list — an *external* state change,
not a direct tap on the stage dropdown itself — so without a fix the
widget would keep showing whatever stage was previously selected, even
once that value no longer belongs to the new stage list. Fixed the same
way as the earlier instance: `key: ValueKey('stage-field-$educationTypeId')`
forces the `FormFieldState` to fully reset whenever education type
changes.

**Verified live on-device** (`202203011615`, superadmin account): tapped
the home shortcut — opened correctly, no crash. Walked the cascade day
→ "primary Education" → "Fourth Stage" (groups list narrowed correctly
each step), then switched education type to "Higher Education" — the
stage dropdown correctly reset to its placeholder instead of staying
stuck on "Fourth Stage" (which isn't even a valid stage for that
education type), and the groups list correctly updated to "لا توجد
مجموعات مطابقة" for that combination. No test data was created during
this pass (navigation and filtering only), so no cleanup was needed.

## Unified login — no more staff/doctor toggle (2026-08-24)

Flutter side of a web+API+Flutter change; see `dental_laravel/README.md`'s
matching entry for the backend/web side (no registration screen existed
on Flutter to remove — confirmed by an exhaustive search before starting;
this is purely the login-screen half).

`login_screen.dart`'s `SegmentedButton<AccountType>` (طالب/موظف) is
gone, along with the `_selected` state and the `_identifierField`
getter that used it to pick which validation-error key to read. One
`TextFormField` now labeled "البريد الإلكتروني أو اسم المستخدم" covers
both identifier shapes.

`AuthRepository`'s `loginStaff({email, password})` and
`loginDoctor({username, password})` — two methods, two endpoints — are
replaced by one `login({identifier, password})` hitting the now-unified
`POST /login` (`Api\AuthController::login()`, see the backend entry) with
a `login` field, mirroring the web form's own field name exactly. The
response's new `account_type` key (`"staff"`/`"doctor"`) tells the
client which resource shape came back and which `AuthAccount` subtype to
parse — replacing "which button did the user tap" as the source of
truth for something `AccountType` still needs downstream (session
restore's `fetchMe(type)` parses `/me` differently per type; that part
is unchanged, only *how* the type is first determined changes).
`AuthController.loginStaff`/`loginDoctor` collapsed into one `login()`
the same way.

**Verified via curl against `/api/v1/login`** (mirroring the backend
entry's own curl pass): staff login by email, doctor login by username,
doctor login by email (the same auto-detect fallback, confirming a
doctor account is reachable by either identifier shape now, not just
`username` like the old dedicated endpoint required), a wrong-password
attempt correctly rejected with a `login` field error (matching what
`login_screen.dart`'s `_fieldErrors['login']` now reads), and the old
`/api/v1/doctor/login` route confirmed gone (404). `flutter analyze`
clean.

**Later verified live on-device** (`202203011615`): confirmed the login
screen itself shows the single "البريد الإلكتروني أو اسم المستخدم" field
with no staff/doctor toggle; logged in as the staff test account
(`superadmin@clinic.test`) — correctly landed on the staff home
screen/dashboard; logged out, logged back in as the doctor test account
by **username** (`doctortest`, the same field the staff login had just
used by email) — correctly landed on the doctor's own "مهامي" task
screen. Confirms `account_type` round-trips correctly end to end (server
response → `AccountType` → correct post-login routing) for both account
shapes through the one screen, not just via curl against the raw
endpoint.

## Printed receipt when a task is started, "تقدم المهام" (2026-08-24)

Starting a task for a doctor/student in the Task Progress admin screen
now prints a physical thermal receipt — name, task/department, notes,
start time, who started it, and a **large** QR (bigger than the
patient-registration ticket's) that reopens this task instance for
review/status updates later. Full design and backend/verification
detail is in `dental_laravel/README.md`'s matching entry — this one
covers the Flutter-side pieces only.

**Real bug fixed as part of this**: `task_progress_screen.dart`'s
`_promptNotes()` dialog captured typed notes in a
`TextEditingController` but only ever returned the confirm/cancel
`bool` from `showDialog` — the typed text was silently thrown away and
never sent to the server. Now returns `Future<String?>` (`null` =
cancel, matching `_promptGradeNotes()`'s existing convention),
returning `controller.text.trim()` on confirm.

**New files/changes**: `TaskStartResult`
(`task_progress_admin/domain/task_progress_group.dart`) parses the
widened `POST /task-progress/start` response (`notes`, `assigned_date`,
`task.department`, `started_by`);
`task_progress_repository.dart::start()` returns it instead of
discarding the response; new
`printing/presentation/task_instance_ticket_widget.dart`
(`TaskInstanceTicketWidget`) — a sibling to `ticket_widget.dart`
copying its structure (header, RTL, `ticketRow()`, nullable fail-open
`logoBytes`/`qrBytes`) but built from primitives so `printing/` stays
free of a `task_progress_admin/domain/` dependency. QR sized at
`widthDots * 0.75` (vs `TicketWidget`'s `0.55`) and fetched at
`size=500` (vs the registration flow's implicit 300px), both explicitly
bigger per the "كيو ار بحجم كبير" request. `_startTask()` in
`task_progress_screen.dart` wires printing in via a new
`_printStartReceipt()` after the existing snackbar/`_reloadGroup()`
call — fetch QR + logo, `printerSettingsProvider` for `dotsPerLine`,
render via `renderWidgetToPng`, print via `showTicketPrintAnimation` +
`PosPrinterService.printTicket()` — the exact same best-effort,
Android-only, fail-open sequence already proven in
`patient_registration_form_screen.dart::_submit()`, reused unmodified.

**Verified on-device** (`202203011615`, real hardware with a built-in
POS printer): started two real tasks with distinguishing test notes;
watched the printer-feed animation run, then confirmed in `flutter run`
device logs that `PosPrinterPlugin` actually printed
(`finish success=true error=null`, falling back to Bluetooth to the
built-in `IposPrinter` after the AIDL path failed — the same fallback
path the registration ticket already uses successfully); confirmed the
rendered ticket bitmap grew from 384×636 to 384×670 once a
`started_by` row was added mid-verification (a follow-up ask, to also
record which staff member started the task), confirming that row
actually renders and isn't silently dropped. Confirmed the scan/review
loop the QR feeds into — `qr_scan_screen.dart`
(`QrScanMode.taskInstance`) → `task_instance_detail_screen.dart` — is
pre-existing and unmodified by this work (verified server-side via
`POST /task-instances/scan` resolving the printed payload correctly,
rather than re-testing UI that wasn't touched). `flutter analyze` clean
throughout. Test `TaskInstance` rows created during verification were
deleted afterward via `php artisan tinker`.

### Reprint any time, a real missing-QR bug, and a layout bug (2026-08-24)

Two follow-ups requested right after the first on-device pass above.

**Reprint any time, not just at the moment of starting**: added a
"طباعة الإيصال" action to every task slot with an `instance_id`
(`assigned` or `completed`, not only the instant `_startTask` runs).
`TaskSlotCard` gained `startedByName` (from `TaskProgressGroupSummary`'s
now-widened `started_by` field — see the backend README entry);
`_reprintReceipt(doctor, departmentName, card)` builds a
`TaskStartResult` from data already on screen and calls the same
`_printReceipt()` (renamed from `_printStartReceipt` since it's no
longer start-only) that `_startTask` already used — no new endpoint, no
duplicated print logic.

**Real bug, reported live**: the first printed receipts had no QR code
on the actual paper, despite the QR bytes fetching successfully (`200
OK`, valid PNG confirmed in device logs). `renderWidgetToPng()`
(`ticket_renderer.dart`) only waits two frames before snapshotting the
off-screen widget — enough for layout/paint of already-decoded content,
not reliably enough for a fresh `Image.memory` decode of a ~500px PNG.
The QR's box was still sized correctly regardless (`Image.memory`
reserves `width`/`height` before pixels are ready), so nothing looked
wrong anywhere except the physical printout. Fixed with a new
`precacheTicketImages(context, [qrBytes, logoBytes])` helper — calls
`precacheImage(MemoryImage(bytes), context)` on the *same* `Uint8List`
instance the ticket widget renders (before `renderWidgetToPng` runs),
so `Image.memory`'s internal `MemoryImage` — equality is by list
identity — hits an already-decoded cache entry instead of racing a
fresh decode during the capture window. Applied to all three print call
sites sharing this exact pattern, not just the reported one: this
screen's `_printReceipt`, and both
`patient_registration_form_screen.dart::_submit()` and
`patient_registration_list_screen.dart::_reprintTicket()` — same root
cause wherever `Image.memory` + `renderWidgetToPng` are paired.

**Real layout bug, found live while adding the reprint button**:
`_TaskSlotTile`'s action buttons lived in `ListTile`'s `trailing` as a
`Wrap` — adding a fourth button pushed the unconstrained trailing area
wide enough to squeeze `title` down to almost nothing, wrapping "class
1 (1)" one character per line (seen in an on-device screenshot, not
predicted from the widget tree). Fixed by moving the button `Wrap` out
of `trailing` into the tile's `subtitle` column, so it wraps across the
tile's full width instead of competing with the title.

`flutter analyze` clean throughout. Verified on-device: reprint button
exercised on an already-`assigned` slot, same printer-success log
pattern as the original start-time print; layout fix confirmed via
screenshot.

### Education type, stage, and group on the receipt (2026-08-24)

`TaskInstanceTicketWidget` gained `educationTypeName`/`stageName`/
`groupName` rows — no backend change, no new field on `TaskStartResult`.
The data was already on screen: `TaskProgressGroupDetail.groupOption`
(`TaskProgressGroupOption` — `name`/`stageName`/`educationTypeName`,
already parsed from `TaskProgressGroupSummary`'s `group` key and shown
as the group header, e.g. "Fourth Stage · primary Education" / "Group
A") is now threaded down through `_DepartmentDoctorList` →
`_TaskSlotTile` → both `_startTask` and `_reprintReceipt` → `_printReceipt`,
the same way `departmentName` already was. Verified on-device: printed
bitmap grew from 384×636 to 384×738 (three new rows) for a doctor
actually in "Group A" / "Fourth Stage" / "primary Education", printer
log confirmed success. `flutter analyze` clean.

### QR scan entry point on "تقدم المهام" (2026-08-24)

Requested so staff can scan a printed task receipt and jump straight
to that instance instead of drilling through the day/type/stage/
group/department/doctor matrix. No new scan logic — `QrScanMode.taskInstance`
(`qr_scan_screen.dart`, `POST /task-instances/scan` →
`context.pushReplacement('/tasks/${instance.id}')`) already existed and
was already reachable from `home_screen.dart`'s doctor-only FAB
(`context.push('/scan')`); this just adds the same push from a second
place. `task_progress_screen.dart`'s `AppBar` gained an
`Icons.qr_code_scanner` `IconButton` (new `go_router` import) calling
`context.push('/scan')` — reuses the existing `/scan` route as-is, no
router changes. `TaskInstanceDetailScreen` (the scan's destination) was
already confirmed usable by both a doctor (ownership-checked) and staff
via `PUT /task-instances/{id}`, so no gating concerns opening it from a
staff-only screen.

Verified on-device: the icon opens the scanner with the correct title
and a working back arrow (round-trip navigation confirmed via
screenshots). Actually scanning a code couldn't be exercised on this
test device — logs showed `CameraX: No available camera can be found`
(camera permission was already granted, so this reads as a
hardware/driver limitation of this specific POS terminal) — a
**pre-existing** constraint shared by the already-shipped doctor-facing
scan entry point, not something introduced or regressed here. `flutter
analyze` clean.

### Student identity on the task detail screen, permission-gated (2026-08-24)

`TaskInstanceDetailScreen` never showed the doctor/student's own name
or who started the task, even though `doctor.name` was already in
`TaskInstance`'s parsed model, just never rendered. Added two rows
("الطالب/الطبيب" — name + username, "بدأ بواسطة"), but gated: the
backend now only sends `doctor`/`assigned_by_name` at all when the
viewer is authorized (see `App\Support\TaskInstanceVisibility` in the
backend README entry) — `TaskInstance.doctorName`/`doctorUsername`/
`assignedByName` are simply `null` for an unauthorized viewer because
the server never included the keys, not because the client is hiding
something it received. `TaskInstance.fromJson` gained `doctorUsername`
(`doctor.username`) and `assignedByName` (`assigned_by_name`) alongside
the existing `doctorName`; the detail screen renders each row only
`if (... != null)`, same pattern already used for every other optional
field on that screen (department, case sheet type, grade, notes).

Verified on-device: logged in as the actual doctor a real task instance
belongs to (a `Doctor` principal always passes the visibility check for
their own instance), opened "مهامي" → the task → detail screen —
confirmed both new rows render with the correct data
("Bakr Abdulrahman (_akr__bdulrahman)" / "System Administrator"),
matching a curl call against the same endpoint with an admin token
exactly. The negative case (a staff token without `task_progress,view`
or admin getting neither field) was verified via curl only — see the
backend README entry — since exercising it on-device would need a
second staff login switch with no additional client-code path to
cover beyond the `if (... != null)` checks already used everywhere else
on this screen. `flutter analyze` clean.

## Redesigned login screen, in-app notifications, and Firebase push scaffolding (2026-08-24)

Three requests bundled together: a branded login screen with the clinic
logo, an in-app notification inbox for "a task was started for you," and
full Firebase push SDK/config scaffolding (no real Firebase project
exists yet — confirmed with the user to build it inert rather than
guess at credentials).

### Login screen redesign

`login_screen.dart`'s visual tree was rebuilt to match `SplashScreen`'s
branded navy/gold look (same color values, duplicated as local consts
rather than extracting a shared file, to avoid touching the
already-verified splash screen for a four-constant DRY gain) — full-
screen gradient background, a static (non-animated — this is a
persistent screen, not a transient splash) circular logo frame, the same
Arabic institutional subtitle, and a white rounded card holding the
actual form. **All existing logic untouched**: `_formKey`, controllers,
validators, `_submit()`, the `ref.listen` error-mapping block — this was
a restyle, not a rewrite.

New `features/auth/data/branding_repository.dart`: `PublicBranding
{clinicName, logoUrl}` + `publicBrandingProvider` (`FutureProvider`, not
gated on auth state unlike `clinicSettingsProvider`, since this screen
runs pre-token) hitting the new public `GET /branding`. The logo image
itself: `Image.network(branding.logoUrl!)` when the fetch resolves a
real admin-uploaded logo, falling back to the already-bundled
`assets/branding/app_logo.png` on any failure or when nothing's
configured — same fail-open contract every other logo/QR image in this
app already follows.

Verified on-device: the redesigned screen renders correctly with the
fallback logo (nothing uploaded on this install yet) and the branded
card; login still functions end-to-end (confirmed by actually logging
in, not just visually inspecting the form).

### In-app notification inbox

New `features/notifications/` folder mirroring `task_instances`'
structure: `domain/app_notification.dart` (`AppNotification`, parsed
from the flat `AppNotificationResource` shape), `data/notification_repository.dart`
(`list()`/`markRead()`/`markAllRead()`), `presentation/notifications_providers.dart`
(`notificationsListProvider` — first page, newest first; `unreadNotificationCountProvider`
derived from it for the badge — no dedicated count endpoint, matching
this project's preference for not adding infrastructure a small
clinic's volume doesn't need), `presentation/notification_inbox_screen.dart`.

Wiring: new `/notifications` route in `app_router.dart`; a bell
`IconButton` wrapped in a `Badge` (unread count) added to
`home_screen.dart`'s `AppBar.actions`, unconditional (both doctors and
staff can be notified), positioned before the existing profile button.
Tapping a notification marks it read then navigates to
`/tasks/{taskInstanceId}` — reuses the already-built
`TaskInstanceDetailScreen`, no new destination screen needed since
"task started" is (so far) the only notification type.

**Two real bugs found and fixed live on-device, not caught by
`flutter analyze` or curl testing**:

1. **Stale cache on opening the inbox.** `notificationsListProvider` is
   `autoDispose`, but `HomeScreen`'s own bell-badge watch keeps a
   listener on it alive for as long as `HomeScreen` stays mounted
   underneath a pushed route (go_router doesn't dispose it on push) — so
   opening the inbox just re-served whatever was cached from whenever
   the badge last fetched, even after a brand-new notification had
   since arrived. Reproduced exactly this way: started a real task via
   curl while sitting on the doctor's home screen, opened the bell —
   badge showed "1" correctly (fresh state from `AsyncNotifier` restore),
   but the *inbox screen itself* showed "لا توجد إشعارات" (empty).
   Fixed by converting `NotificationInboxScreen` to a
   `ConsumerStatefulWidget` and invalidating `notificationsListProvider`
   in a post-frame callback on `initState` — guarantees a fresh fetch
   every time the inbox is actually opened.
2. **Pull-to-refresh silently did nothing on an empty inbox.** The first
   version only wrapped the non-empty list branch in `RefreshIndicator`;
   the empty-state `Center(child: Text(...))` had no scrollable
   ancestor at all, so a pull gesture had nothing to grab. Fixed by
   wrapping both branches in `RefreshIndicator` with
   `AlwaysScrollableScrollPhysics` (a `ListView` even in the empty case,
   padded with a `SizedBox` so the empty message doesn't sit flush at
   the top).

Re-verified on-device after both fixes: started a real task for the
logged-in doctor, bell badge showed "1", opened the inbox — the
notification appeared immediately with correct title/message/timestamp
and an unread indicator, tapping it marked it read (badge cleared) and
opened the correct task's detail screen showing all the right data.
(One transient `500` was hit mid-testing on a *second* tap into the
detail screen — traced to a one-off Laravel log entry showing a stray
`sqlite`/`production`-env request that couldn't be reproduced on an
immediate retry, either via curl or on-device; treated as an
environment fluke, not a code regression, since it's unrelated to
anything touched in this pass and never recurred.)

### Firebase push scaffolding (inert until a real project exists)

Added `firebase_core`/`firebase_messaging` to `pubspec.yaml` — `flutter
pub get` run explicitly before touching anything Android/native, to
catch version-solver conflicts early (none found).

**The one genuinely risky change in this pass**: Android's Google
Services Gradle plugin normally needs a real `google-services.json`
(which doesn't exist yet) or the build fails outright. Researched this
project's exact Gradle setup first (`settings.gradle.kts`'s newer
declarative `plugins {}` block, AGP 8.9.1/Kotlin 2.1.0, no
`buildscript{}` in the root `build.gradle.kts`) rather than guessing at
the wiring style. Solution: declare the plugin with `apply false` in
`settings.gradle.kts` (classpath resolvable, not applied anywhere), then
in `android/app/build.gradle.kts`, apply it **imperatively and
conditionally**:
```kotlin
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}
```
so the build is completely unaffected by the file's absence today, and
self-activates the moment a real file is dropped in — no further Gradle
edits needed at that point.

`lib/main.dart`: `main()` is now `async`, wraps `Firebase.initializeApp()`
in try/catch (throws until real native config exists — caught and
ignored, matching this app's fail-open convention everywhere else).

New `lib/core/push/push_notification_service.dart`
(`PushNotificationService`): no-ops immediately if `Firebase.apps.isEmpty`;
otherwise requests permission, gets the FCM token, registers it via
`POST /device-tokens`, listens for token refresh, and on a foreground
push just invalidates the Part-2 notification providers (refreshes the
existing in-app inbox/badge rather than building a second,
separate foreground-banner UI — background/terminated pushes already
show via the OS system tray automatically once FCM is configured, since
`PushNotifier` sends a `notification` payload block). Called
fire-and-forget (`unawaited`) from both of `auth_controller.dart`'s
success paths (fresh login and session restore) — never blocks the
login UX.

**Critical build-safety verification, called out explicitly since this
was the one change capable of breaking every other feature in this app
if done wrong**: ran a full `flutter run` on-device with no
`google-services.json` present. First build took 210.8s (Gradle
resolving the new Firebase native dependency tree for the first time,
confirmed via active CPU usage on the Gradle daemon while waiting, not
assumed stuck) but completed cleanly with **no Firebase-related build
failure or runtime crash** — the app launched, the login screen
rendered, and login worked normally. A second `flutter run` after a
later code change (the notification-inbox bug fixes above) took only
17.8s, confirming the long first build was purely the one-time
dependency-download cost, not a recurring problem. Checked device logs
specifically for any Firebase-related exception — none found; the
`try/catch` around `Firebase.initializeApp()` worked silently as
intended.

Backend no-op confirmed independently too (see backend README entry):
registered a fake device token, started a real task, confirmed no
`PushNotifier` warning/exception in `storage/logs/laravel.log` while the
in-app notification (Part 2) still got created — the two delivery paths
are fully independent.

`flutter analyze` clean throughout (including after adding the two new
Firebase packages).

## Doctor's "مهامي" rebuilt: grouped by department, matching the original app (2026-08-24)

Replaced `task_instances/presentation/task_list_screen.dart` (a flat,
status-filterable list of existing `TaskInstance` rows — couldn't show a
required-but-not-started case at all, no department grouping) with
`task_instances/presentation/my_tasks_screen.dart`, matching the original
PHP app's doctor task view combined with the admin screen's collapse
interaction (see the backend README entry for the full research). Reused
the admin `task_progress_admin` feature's existing domain classes
(`TaskProgressDoctorRow`, `TaskSlotCard` — identical JSON shape, since
both sides share `TaskProgressGroupSummary::buildDoctorRow()` on the
backend) rather than duplicating them; new
`task_instances/domain/my_task_department.dart` (`MyTaskDepartment`) only
wraps the outer department/single-doctor envelope, which differs from
the admin shape (`doctor` singular vs `doctors` list, since a doctor
viewing their own tasks is always exactly one doctor).

New `TaskInstanceRepository.mineProgress()` → `GET /my-task-progress`;
new `myTaskProgressProvider`. `MyTasksScreen`: `TabBar`/`TabBarView` per
department (same pattern as the admin screen's `_buildGroupDetail`);
within a department, groups that department's slot cards by `taskId`
into one `ExpansionTile` per task (collapsed header: title + "X/N
مكتملة"), expanding to each slot's status badge/date/notes/grade. No
staff actions (start/complete/edit) — a doctor only ever *views* their
own tasks; a slot with a real `instanceId` is tappable to
`/tasks/{id}` (the existing `TaskInstanceDetailScreen`, unchanged), an
unassigned slot is plain informational text.

**Dead code removed alongside the swap**, once confirmed genuinely
orphaned (grepped first, not assumed): the old `task_list_screen.dart`,
`TaskInstanceRepository.mine()` (and its now-unused `Paginated` import),
and `taskInstanceStatusFilterProvider`/`myTaskInstancesProvider` from
`task_instances_providers.dart` — all had exactly one remaining caller
each, the screen being replaced. The backend's `/my-task-instances`
endpoint itself was left untouched (still a legitimate general-purpose
API, just no longer called from this particular screen).

Verified on-device, logged in as a real doctor with real graded history
(`zm230093pde@st.tu.edu.iq` / `_aman__ohammed`, the account handed over
for testing this session): department tabs matched their real
departments; "operative" → "class 2" showed "0/3 مكتملة" collapsed,
expanded to three "الحالة 1/2/3" rows all correctly "لم تبدأ بعد"; "class
1" showed "1/2 مكتملة", expanded to one completed slot (grade 90.0, date,
notes) and one in-progress slot, both with a working chevron; tapping the
completed slot opened the correct task detail screen with matching data.
Switching department tabs (e.g. to "oral medicine") correctly showed that
department's own tasks ("tmj" — "0/3 مكتملة"). `flutter analyze` clean.

## Bluetooth scan hang when Bluetooth is off, plus one-tap enable buttons (2026-08-25)

**Reported by the user**: searching for a printer never showed it even
though it was visible in the device's own Bluetooth settings, and the
search spinner never stopped, even with Bluetooth completely off.

**Root cause, confirmed in `PosPrinterPlugin.kt`'s `onListen()`**: the
`EventChannel` handler backing `scanBluetoothDevices()` only checked that
a Bluetooth *adapter exists*, never that it's *enabled*, and discarded
`BluetoothAdapter.startDiscovery()`'s `Boolean` return value. With
Bluetooth off, `startDiscovery()` silently returns `false` and fires
neither `ACTION_FOUND` nor `ACTION_DISCOVERY_FINISHED` — the only two
events that ever reset `printer_settings_screen.dart`'s `_scanning` flag
back to `false`, so the spinner ran forever. The exact same file already
had the correct `!adapter.isEnabled` guard twice in the *print* path
(`printViaBuiltinBluetoothFallback`/`printViaBluetoothAddress`) — it was
just missing from the scan path.

**Fix**: `onListen()` now checks `adapter.isEnabled` up front and emits a
`bluetooth_disabled` stream error immediately instead of calling
`startDiscovery()`; the discarded return value is now checked too,
emitting `discovery_failed` on the rarer case the OS refuses for another
reason. Four new `MethodChannel` methods
(`isBluetoothEnabled`/`requestEnableBluetooth`/`isLocationEnabled`/
`openLocationSettings`) let the Dart side query and open the system
Bluetooth-enable prompt (`ACTION_REQUEST_ENABLE`) and Location settings
(`ACTION_LOCATION_SOURCE_SETTINGS`) directly — both via
`context.startActivity(..., FLAG_ACTIVITY_NEW_TASK)` since the plugin only
holds a plain `Context`, not an `Activity` (see the class doc comment).
`printer_settings_screen.dart`'s `_scanBluetooth()` now checks
`isBluetoothEnabled()` before scanning and shows a SnackBar with a
"تشغيل" action button if it's off (same button appears if Bluetooth is
switched off *during* an active scan, via the new `bluetooth_disabled`
error code); the existing Location-permission warning SnackBar (added in
the 2026-08-23 fix below) got the same kind of "الإعدادات" action button.

**A second bug found live while verifying the fix**: both new
`SnackBarAction` buttons were nearly invisible — `app_theme.dart`'s
`SnackBarThemeData` sets an explicit `backgroundColor`/`contentTextStyle`
but no `actionTextColor`, so Flutter's default action color resolved to
low contrast against this app's SnackBar background. Found via a
cropped/zoomed screenshot (not assumed), fixed by setting
`textColor: InstagramColors.blue` explicitly on all three
`SnackBarAction`s.

**Verified on-device** (Honor tablet, `ADYX9X4607G00324`, Android 13):
with Bluetooth off, tapping "بحث" showed both SnackBars in sequence (the
Location warning, then the Bluetooth-disabled one) with correctly-colored
blue action buttons — confirmed only after chaining the tap and
screenshot inside one `adb shell` call, since the per-tool round trip
through this session was slow enough (minutes) to miss the earlier,
shorter-duration SnackBars entirely on the first several attempts.
Tapping "تشغيل" opened the real system "هناك تطبيق يريد تمكين البلوتوث"
dialog; tapping "سماح" there enabled Bluetooth (confirmed via
`settings get global bluetooth_on`); re-tapping "بحث" then started a real
scan (spinner animating, no immediate error) with the previously-paired
"soundcore R50i" correctly listed under "أجهزة مقترنة". `flutter analyze`
clean.

**A third, separate, pre-existing bug found live on this same device
while verifying the fix above — root-caused and fixed**: even with
Bluetooth on and `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT` both granted, the
scan spinner still never stopped and no new devices were ever discovered.
`dumpsys bluetooth_manager` confirmed the OS-level adapter had already
genuinely finished discovering (`Discovering: false`) while the app's
spinner kept animating — so `ACTION_DISCOVERY_FINISHED` was firing, just
never reaching this app. `dumpsys activity broadcasts` confirmed it
directly: both `ACTION_FOUND` and `ACTION_DISCOVERY_FINISHED` broadcasts
were delivered to several other apps (`com.hihonor.iaware`,
`com.android.systemui`, `com.hihonor.hiview`, `com.android.settings`) but
explicitly marked `Skipped` for this app's own dynamically-registered
receiver, every single time, across multiple independent scan attempts —
ruling out (checked directly, not guessed) app-standby buckets, Doze
whitelist status, the `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT` app-ops
(`cmd appops get` showed both `allow`), the `neverForLocation` manifest
flag, and Honor's own manual "launch management" toggles (tried,
force-stopped and relaunched, broadcasts still skipped).

**Actual root cause**: `registerReceiverCompat()` registered the scan and
pairing receivers with `Context.RECEIVER_NOT_EXPORTED` on API 33+ (the
safer default, matching the third receiver in this same file for USB
permission results). But `RECEIVER_NOT_EXPORTED` only guarantees delivery
from broadcasts sent by "the system" (uid 1000) or the same app — and on
this Android 13 build, broadcasts from `com.android.bluetooth` (the
Bluetooth stack process, uid 1002) are **not** treated as equivalent to
uid 1000 for that check, so they were silently and permission-lessly
dropped for any receiver registered as not-exported. No exception, no
log line at the app level — `dumpsys activity broadcasts` was the only
way this surfaced. `printer_settings_screen.dart`'s USB-permission
receiver was unaffected since it only ever receives this app's own
self-sent `PendingIntent` broadcast, which does satisfy the "same app"
exemption.

**Fix**: `registerReceiverCompat()` now takes an `exported: Boolean`
parameter (default `false`, preserving the existing safer behavior for
the USB-permission receiver); the two Bluetooth-stack-sourced receivers
(scan results/discovery-finished, and pairing's bond-state-changed) now
pass `exported = true`.

**Verified live**: rebuilt, reinstalled, re-logged in, re-ran the exact
same scan that previously hung forever with zero discovered devices —
this time the spinner started and stopped on its own within the normal
window, and a real nearby device (`58E_BD90`, not previously
paired) appeared under "أجهزة مكتشفة" with a working "اقتران" button.
`dumpsys activity broadcasts` immediately after confirmed both broadcasts
now show `Deliver`, not `Skipped`, for this app's receiver.

## Cascading education-type → stage filters, plus search, across Doctors/Groups/Taxonomy admin (2026-08-25)

Requested by the user, matching a pattern this app already had for Tasks
(`task_list_screen.dart`/`task_form_screen.dart`'s نوع الدراسة → المرحلة →
القسم cascade). Their example — "picking a stage should only show stages
under the chosen education type, not all of them" — turned out to be a
**real, existing bug**, confirmed by reading the code rather than assumed,
in two places:

- `taxonomy_admin/presentation/taxonomy_list_screen.dart`'s
  `_TaxonomyFormDialog`, creating/editing a **department** (the only
  `TaxonomyKind` with both an education-type and a stage field): the stage
  dropdown listed every stage regardless of the education type picked in
  the same dialog.
- `doctors_admin/presentation/doctor_form_screen.dart`: identical bug —
  the stage dropdown was fed the full, unfiltered `doctorStagesProvider`
  list with no relation to the education-type field above it.

**Fix, both places**: cascade the stage dropdown exactly like
`task_form_screen.dart` already does (`stages.where((s) =>
s.educationTypeId == _educationTypeId)`, `ValueKey('stage-$_educationTypeId')`
to force a clean reset, reset `_stageId` to `null` when the education type
changes). The doctor form's stage field is required, so it's also
`enabled: false` until an education type is picked (matches the web's own
`Doctors/Create.vue`); the department dialog's stage field is optional
(`Department.stage_id` is nullable, "— بدون —" stays selectable), so it's
narrowed without being force-disabled.

**New elsewhere, not a bug fix** — the same cascade pattern, plus search,
was added to screens that had no filtering at all before:
- `doctor_list_screen.dart` already had a name/email search box; added
  education-type → stage cascading filters combined with it.
  `Api\DoctorController::index()` was missing both filters server-side
  (the web's own `App\Http\Controllers\DoctorController::index()` already
  had them) — ported verbatim, plus added `username` to the search clause
  (the web controller already searched it; the API one didn't — small
  found parity gap, fixed alongside since it's the same block).
- `group_list_screen.dart` had **no search or filter UI at all** before
  this. Added a name search plus education-type (UI-only — `Group` has no
  `education_type_id` column) → stage cascading filters.
  `Api\GroupController::index()` already accepted `stage_id`; added a
  `search` `when()` clause — genuinely new, no group-name search existed
  anywhere in this project (web or API) before this.
- `group_form_screen.dart` had a stage field but no education type at
  all — added a UI-only education-type field narrowing it, never sent in
  the payload, exactly like `task_form_screen.dart` already does for
  `Task` (which also lacks the column). On edit, derives the initial
  education type from the group's own stage (same "derive from stored
  child" trick `task_form_screen.dart` uses for editing an existing task).
- `taxonomy_list_screen.dart`'s list view (all three kinds) had no
  search or filter UI either — added a name search for all three, plus an
  education-type filter for stages and education-type→stage cascading
  filters for departments. Pure client-side (`Api\LookupController`'s
  three `index` endpoints return their whole small flat table — no
  backend change needed at this scale).

Extracted the previously-private `_CascadingDropdown<T>` from
`task_list_screen.dart` into `core/widgets/cascading_dropdown.dart` as
public `CascadingDropdown` (dropped the always-unused `<T>` type
parameter while moving it) — now a 5-screen consumer, past the point
duplicating it further was worth it.

**Verified live** on the Honor tablet, logged in as Super Admin: doctor
list — selecting "Higher Education" correctly showed zero matching
doctors (confirmed against the real data — no doctor has that education
type) and its stage dropdown narrowed to only "First Stage"; switching to
"primary Education" correctly showed the other three stages instead.
Department edit dialog — opened "operative" (primary Education/Fourth
Stage), switched education type to "Higher Education": the stage field
auto-reset to "— بدون —" and its dropdown then only offered "First
Stage" — the user's exact reported bug, confirmed fixed. Group list now
renders the search box and both filters; group create form now renders
the new "نوع التعليم" field above "المرحلة". Backend verified via curl
against the live API: unfiltered `/doctors`/`/groups` calls unaffected;
`education_type_id`/`stage_id` filters narrow correctly (cross-checked
against `php artisan tinker` ground truth); the new `search` param on
`/groups` and the new `username` clause on `/doctors` both confirmed
matching real records a name-only search would have missed. `flutter
analyze` clean; `npm run build` (web/Vue side, see the matching
`dental_laravel/README.md` entry) clean.

## NFC alongside search on the Doctors and Groups admin lists (2026-08-25)

Requested as a follow-up to the filter/search work above — NFC as an
alternate to typing, matching the pattern `task_progress_screen.dart`
already established (tap-to-scan instead of typing a doctor's name),
extended to the two list screens that didn't have it yet.

**Backend**: added `Api\DoctorController::nfcLookup()` (`GET
/doctors-nfc-lookup?tag_id=...`) — a lighter, reusable twin of
`Api\TaskProgressController::nfcScan()`. That endpoint also runs
`PendingTaskFinder` to offer a direct task-start shortcut, which is
irrelevant to "which doctor is this card" on an admin list — added a
purpose-built one in `DoctorController` instead of making
`doctors_admin`/`groups_admin` depend on the unrelated
`task_progress_admin` feature for this. Returns a full `DoctorResource`
(so the education-type/stage IDs are available too, not just the name);
404 with the same "لا يوجد طبيب مرتبط بهذه البطاقة" message on an
unlinked tag. Also added `doctor_id` to `Api\GroupController::index()`'s
filters (`whereHas('doctors', ...)`) — scanning a card doesn't match a
*group name*, so it's a separate, combinable filter ("which group(s) is
this doctor in"), not folded into the name search.

**Flutter**: added `LookupRepository.doctorByNfcTag(String tagId)` —
reuses the existing `LookupItem` class as-is rather than a new one, since
the response's `id`/`name`/`stage_id`/`education_type_id` fields are
exactly what it already parses. Shared by both screens (matches
`NfcUidReader`'s own existing doc comment: "shared between doctor
NFC-tag enrollment and the staff NFC lookup screen" — now a third
caller, same file).

- `doctor_list_screen.dart`: NFC icon as the search `TextField`'s
  `suffixIcon` (spinner while scanning). On a successful scan, sets the
  search text to the doctor's name *and* jumps the education-type/stage
  dropdowns to match — immediate, not relying on the name search alone.
- `group_list_screen.dart`: same icon/spinner placement, but a scan can't
  match a *group name*, so it sets a new `_doctorId` filter (combinable
  with the existing name search and stage filter) and shows a small
  removable `Chip` ("مجموعات ⟨اسم الطبيب⟩") rather than stuffing the name
  into the search box, which would just search for a group literally
  named after a doctor and (almost always) find nothing.

**Verified**: backend via curl — set a test doctor's `nfc_tag_id`
temporarily, confirmed `/doctors-nfc-lookup` resolves it (including
case-insensitive input, normalized the same way `validateDoctor()`
already does) and 404s on an unlinked tag; confirmed `/groups?doctor_id=`
narrows to exactly the group(s) that doctor belongs to and combines
correctly with `search` (0 results for a doctor's real group ANDed with
an unrelated name substring); reverted the test data afterward (temporary
`nfc_tag_id` cleared, group membership detached — not real data, don't
want it lingering in a DB other test flows read from). On-device: both
list screens render the NFC icon correctly (real `Icons.nfc` glyph,
confirmed via a cropped screenshot, not a missing-icon placeholder);
tapping it on both screens correctly starts a real `NfcUidReader` session
and, since the tablet has no NFC hardware reader tapped in this pass,
correctly surfaces the "تعذر التعرف على البطاقة" error path end-to-end
(same generic-fallback message `task_progress_screen.dart`'s own catch
block already produces for a non-`ApiException` failure — not a
regression introduced here). A real card tap wasn't tested (none on
hand this session) — the read call itself is the exact
`NfcUidReader.readUid()` already proven working live for doctor NFC-tag
enrollment and the task-progress screen, not new code. `flutter analyze`
clean.

## Day-governed diagnosis at patient registration, plus dropdown search (2026-08-25)

The user's example: "Sunday's diagnosis is قلع (extraction)" — day
already narrows the **service** picker in `patient_registration_form_screen.dart`
(`RegisterDay.services`, via `register_day_service_map`), but "التشخيص"
(a plain `Task` pick) sat next to it fully independent. See the matching
`dental_laravel/README.md` entry for the full schema/backend picture
(new `register_day_task_map` pivot, opt-in-per-day validation, new `PUT
/tasks/{task}/register-days` endpoint) — this entry covers the Flutter
side only.

**The diagnosis list itself is unchanged** — still every existing `Task`
record via `tasksLookupProvider`, exactly as before. This feature only
adds an optional per-day *narrowing* on top; confirmed explicitly with
the user mid-implementation, since "day-governed" could easily be
misread as "a new/separate diagnosis list" rather than "which of the
existing tasks are offered."

- `RegisterDay` domain gained `taskIds: List<int>` (mirrors `services`,
  parsed from the API's now-nested `tasks`) — empty means "no rule for
  this day," not "no tasks allowed."
- `patient_registration_form_screen.dart`: the day picker's `onSelected`
  now also clears `_taskId` if the newly-picked day has rules and the
  current pick isn't one of them (mirrors the existing service-clearing
  logic right next to it). The task picker itself moved from a plain
  `DropdownButtonFormField` to the shared `CascadingDropdown`
  (`core/widgets/cascading_dropdown.dart`, already used in 5 other admin
  screens) fed a filtered list:
  `selectedDay.taskIds.isEmpty ? allTasks : allTasks.where(taskIds.contains)`
  — narrows when the day has rules, shows everything otherwise. This is
  also the dropdown-search fix the user asked for in the same message
  (`CascadingDropdown` already wraps `DropdownMenu(enableFilter: true)`).
- `appointment_form_screen.dart`'s task picker got the same
  `CascadingDropdown` swap (no day-filtering there — appointments aren't
  day-scoped, just the missing search).
- `register_settings_screen.dart`: new "التشخيص" section mirroring the
  existing "الخدمات" section's list+day-`FilterChip`-grid UI exactly,
  minus the create form (tasks are still only made in Tasks admin) — a
  search `TextField` (same `> 6` threshold convention the days/services
  sections already use) over `tasksLookupProvider`'s list, each task a
  `Card` with per-day `FilterChip`s and its own "حفظ" button
  (`PatientRegistrationRepository.updateTaskDays()`, new). Each row's
  day selection is seeded once from `registerDaysProvider`'s nested
  `taskIds`, inverted client-side (day→tasks becomes task→days) — no new
  read endpoint needed for this.

**Verified live** on the Honor tablet, logged in as Super Admin (see the
backend README entry for the matching curl-level validation checks):
created two real register-days and a service via curl (this dev DB had
none configured before), opened "إعدادات التسجيل" — confirmed the new
"التشخيص" section renders with all real tasks, searched "extraction",
found it instantly, assigned it to "الأحد" only, saved, got the "تم
الحفظ." confirmation. Opened "تسجيل مريض جديد", picked "الأحد" — the
"التشخيص" dropdown narrowed to show *only* "extraction" (the user's
exact example, confirmed working end-to-end). Picked "الاثنين" (left
unconfigured) instead — the dropdown correctly showed the full,
unrestricted task list again, confirming no regression for days nobody
has configured yet. All test data reverted afterward. `flutter analyze`
clean.

## PDF printing for Doctors, Groups, and Task Progress (2026-08-25)

The user asked for PDF printing "the same way it exists in dentalclinic"
(the original PHP app). Research first (see the approved plan, since this
one genuinely changed the design): `admin/print_doctors.php`,
`print_doctor_card.php`, and `task_progress_print.php` are **not** real
server-generated PDFs — they're plain HTML pages with `@media print` CSS,
opened in a new tab and printed via `window.print()`. TCPDF is installed
in the legacy app's `composer.json` but only used by an unrelated
QR-badge-sheet feature, never by these three. There's no "browser tab" on
a mobile app to reproduce that trick in, so this is a from-scratch
client-side PDF via the `pdf`/`printing` packages instead — same content
and layout as the legacy pages, produced the way a mobile app actually
can. Also confirmed: **no standalone "group" print exists in the legacy
app at all** — its only "group" print is the task-progress report scoped
to a group (`admin/ajax/get_group_doctors.php`'s three buttons all open
`task_progress_print.php` with `group_id`/`+department_id`/`+doctor_id`).
Since the user asked for groups printing as a *separate* item from task
progress, `group_roster_pdf.dart` is a new (not-ported) roster PDF,
directly analogous to the doctors one.

**Arabic text needs a bundled font** — the `pdf` package renders its own
glyphs rather than using the OS text renderer, so without an embedded
Arabic-capable TTF the report would render boxes. Bundled **Tajawal**
(`assets/fonts/Tajawal-{Regular,Bold}.ttf`, OFL) rather than the
originally-planned Cairo — Cairo (and most modern Google Fonts Arabic
families, checked via the `google/fonts` GitHub API: NotoSansArabic,
NotoKufiArabic) now ship **variable-font-only**, with no separate static
Bold file the `pdf` package can load as a second `pw.Font` instance.
Tajawal, Amiri, Almarai, and IBMPlexSansArabic still ship classic static
weight files; Tajawal was picked as the closest visual match to Cairo.

- `core/pdf/pdf_letterhead.dart` (new) — loads the two font weights once
  (cached statically), builds a `pw.ThemeData` for RTL, and a shared
  `buildLetterhead()` widget (logo, university/college name, report
  title, print timestamp) reused by all three PDFs rather than
  duplicated three times. `ClinicSettings` gained `universityName`/
  `collegeName` fields (backend already had them, just unmapped on the
  Flutter side).
- **Real bug found live, fixed**: the letterhead's university/college
  name lines rendered blank on first use, even though `GET
  /clinic-settings` genuinely returns them (confirmed via curl). Cause:
  `ref.read(clinicSettingsProvider).valueOrNull` — on a `FutureProvider`
  nothing else had watched yet, this reads `AsyncLoading` synchronously
  (`.valueOrNull` → `null`) rather than waiting for the fetch. Fixed by
  awaiting `ref.read(clinicSettingsProvider.future)` in all three print
  handlers instead — verified with a redeploy that the letterhead then
  showed "University of Tikrit" / "College of Dentistry" correctly.
- **Backend**: `Api\DoctorController::index()` now eager-loads
  `groups:id,name` (same relation `DoctorPrintController.php`, the web
  roster port, already uses) and `DoctorResource` gained a `groups`
  field — `DoctorAdmin.groupNames` reads it. `Api\GroupController::show()`
  now also selects `username` on the `doctors:id,name,email` column list
  — `GroupMember.username` reads it (also happens to match the field the
  legacy task-progress print already used for its QR payload, though
  this app doesn't render a QR).
- `doctors_admin/presentation/doctor_roster_pdf.dart` (new) — per-stage
  grouped tables (#, الاسم, البريد الإلكتروني, نوع التعليم, المجموعة)
  plus a summary box (total/grouped/ungrouped/per-stage), mirroring
  `print_doctors.php` exactly. `doctor_list_screen.dart` gained an
  AppBar print icon building from the **currently filtered/searched**
  list already on screen (no extra fetch) — mirrors the legacy "طباعة
  الفلتر" button's scope.
- `groups_admin/presentation/group_roster_pdf.dart` (new) — group
  name/stage, weekly-slots table, member table (#, الاسم, اسم المستخدم,
  البريد الإلكتروني). `group_detail_screen.dart` gained an AppBar print
  icon.
- `task_progress_admin/presentation/task_progress_pdf.dart` (new) — cover
  block (group/stage/education-type + active filter line) plus one table
  per department (#, اسم الطبيب, المهمة, الحالة [colored badge matching
  `_TaskSlotTile`'s own `_statusColor()`/`_statusLabel()` exactly],
  درجة المهمة, الدرجة المحققة, التاريخ), iterating every required slot
  (not just filled instances) so unfilled slots print too, matching
  legacy. The `pdf` package has no native table rowspan, so a doctor's
  name is repeated on every one of their task rows rather than merged —
  simpler than emulating a merge, and still clearly readable in the
  rendered PDF (confirmed on-device). `task_progress_screen.dart` gained
  the same three print scopes the legacy page's three buttons had: whole
  group (group-detail AppBar), current department only (a print icon
  next to the `TabBar`, using `_tabController!.index`), and a single
  doctor (a print icon added to that doctor's `ExpansionTile` title row).

**Verified live** on the Honor tablet, logged in as Super Admin (needed
`--dart-define=API_BASE_URL=http://<LAN-IP>/...` — a fresh `flutter run`
defaults to the Android-emulator-only `10.0.2.2`, which just hangs/times
out on a real device; not this feature's bug, a pre-existing run-config
gotcha rediscovered here). Doctors roster: printed the full unfiltered
list (15 doctors, two stages) — per-stage tables, group column, and
summary box (15 total / 15 grouped / 0 ungrouped) all matched the admin
list exactly, Arabic/RTL rendered correctly, letterhead complete after
the `.future` fix above. Group roster ("Group B", 50 members): 2-page
PDF, weekly slot and all 50 members with real usernames listed
correctly. Task progress, all three scopes on the same real group:
whole-group print produced a genuine 68-page document (7 departments ×
50 doctors × 9 slots) with correct per-doctor status/grade/date data and
correctly colored status badges throughout; department-scoped print
(the "operative" tab) correctly narrowed to 14 pages with "· القسم:
operative" appended to the cover subtitle; single-doctor print (from
that department's doctor list) correctly narrowed to exactly that
doctor's 9 rows with "· الطبيب: {name}" in the subtitle. `flutter
analyze` clean throughout. The existing thermal-receipt printing feature
(`features/printing/`) was not touched by any of this — confirmed by the
diff itself (only new imports/methods/buttons added to files it shares,
no edits to `pos_printer_service.dart`, `ticket_renderer.dart`, or the
native plugin), so it wasn't separately re-tested live this pass.

## "الجلسات الدراسية" renamed to "العام الدراسي", plus an active-year banner on Doctors/Groups/Tasks/Task-Progress and the dashboard (2026-08-25)

See the matching `dental_laravel/README.md` entry for the backend side
(the model-hook enforcement of "one active year," and the two real
scoping gaps it closed in `Api\GroupController`/`TaskProgressGroupSummary`/
`DoctorTaskSummary`/`TaskProgressFilters`) — this entry covers Flutter.

- **Rename**: every `الجلسات الدراسية`/`جلسة دراسية` label across
  `admin_hub_screen.dart`, `academic_session_list_screen.dart`,
  `academic_session_form_screen.dart`, and `academic_session_detail_screen.dart`
  became `الأعوام الدراسية`/`عام دراسي` (also fixed the gendered
  agreement on the status chips — `نشطة`/`غير نشطة`/`الحالية` don't agree
  with the now-masculine `العام`, replaced with `مفعّل`/`غير مفعّل`/
  `النشط حالياً`).
- **New `CurrentAcademicYear` domain class** (`academic_session_admin.dart`)
  — deliberately not reusing `AcademicSessionAdmin` even though its
  nullable-safe `fromJson` *could* technically parse the smaller
  `{id, name}` shape: `GET /academic-sessions/current` is a genuinely
  different, smaller server contract, and reusing the CRUD model would
  leave misleading defaulted-out fields (`isActive: true`, counts: `0`)
  on an object nothing should ever edit.
- **`currentAcademicYearProvider`** (`academic_sessions_providers.dart`)
  — deliberately not `.autoDispose`, same reasoning as
  `clinicSettingsProvider`: it's read by five different screens at once
  (dashboard + the four admin list screens), and disposing/refetching
  every time one of them unmounts would be wasteful.
  `academic_session_detail_screen.dart`'s `_setCurrent()` now invalidates
  it alongside the two providers it already invalidated.
- **`core/widgets/academic_year_banner.dart`** (new) — one shared
  `AcademicYearBanner` widget (five call sites: `doctor_list_screen.dart`,
  `group_list_screen.dart`, `task_list_screen.dart`,
  `task_progress_screen.dart`, `home_screen.dart`'s staff dashboard),
  matching this codebase's own "extract once 3+ places need it"
  convention (`CascadingDropdown`'s doc comment). Renders nothing while
  loading, on error, or when no year is active — same "never blocks, only
  informs" contract as `clinicSettingsProvider`. Takes an optional
  `margin` override (`home_screen.dart` passes a narrower one — it's
  already inside a padded `ListView`, unlike the four bare-`Column`
  admin screens the default margin was tuned for).

**A real bug found live, not just in code review**: on first deploy, the
banner's university/college-name-style text ("العام الدراسي النشط:
{name}") rendered correctly on the dashboard but the admin list screen
showed **no** "current" badge on *any* row, even though every banner
elsewhere confidently named "2027" as active. Traced to the real dev
database (see the backend README entry) having zero rows with
`is_current=1` — `AcademicSessionHelper::resolve()`'s existing fallback
(most-recent-`is_active`-by-`start_date`) was silently choosing one for
display everywhere the banner reads, while the list screen's per-row chip
correctly reflects the literal (all-false) `is_current` column — two
different, both-correct readings of two different pieces of state, not a
Flutter bug. Fixed at the data layer (see backend entry) rather than by
changing either screen's logic.

**Verified live** on the Honor tablet, logged in as Super Admin (same
`--dart-define=API_BASE_URL=http://<LAN-IP>/...` gotcha as the PDF entry
above — noted once there, applies to every `flutter run` this session).
Confirmed the banner renders identically worded ("العام الدراسي النشط:
2027") on the dashboard and all four target screens. Confirmed the
Groups-scoping backend fix live, not just via curl: before the fix's
data was set up, the Flutter Groups list showed groups from a prior
academic year (`Group A`/`Group B`, stamped to a non-current session)
mixed in with session-less ones; after creating real cross-year test
data and pointing the current year at the right row, the same screen
correctly narrowed to only the session-less group. Confirmed the rename
in the admin hub (`الأعوام الدراسية` tile) and the list/detail/form
screens, including the corrected `النشط حالياً` badge appearing on
exactly the one row explicitly marked current. `flutter analyze` clean
throughout.

**Follow-up, same day**: the user asked for the activate/deactivate
control specifically as an iOS-style toggle switch, with turning one year
on automatically turning the others off. Replaced the list screen's
static status `Chip` and the detail screen's `Chip`/`OutlinedButton.icon`
pair with `CupertinoSwitch` (from `package:flutter/cupertino.dart` —
already part of the Flutter SDK, no new dependency) reflecting
`session.isCurrent`, wired to the same `setCurrent()` call both screens
already had. No new "turn off" case exists — turning a switch on for a
different year is the only way to turn the current one off, matching the
feature's own "exactly one active year" rule; the currently-current row's
switch is simply disabled (`onChanged: null`) rather than offering a
no-op toggle. The list screen's tile became a `ConsumerStatefulWidget` to
show a small per-row spinner while the request is in flight. **Verified
live**: tapping a different row's switch turned it green and the
previously-current row's switch off in the same refresh, the list
re-sorted (still `orderByDesc('is_current')` server-side) so the newly
current year moved to the top — confirmed the backend's `AcademicSession`
`saving()` hook (see the backend README entry) is doing the exclusivity
work, not any client-side logic. Reverted the test toggle back to the
original active year afterward.

## Fixed: profile photo upload silently not updating (2026-08-25)

Reported by the user; root-caused and fixed entirely on the backend — see
`dental_laravel/README.md`'s matching entry for the full story (two
stacked bugs: `User::$fillable` missing `profile_image`, and `.env`'s
`APP_URL` being `localhost`, unreachable from a real device on the LAN).
Nothing in `profile_screen.dart`/`profile_repository.dart` needed
changing — both were already doing the right thing (`updateAccount()`
correctly swaps in the fresh account from the response;
`NetworkImage(currentPhotoUrl)` correctly re-fetches once the URL
actually changes). Worth recording here since it's a good example of a
Flutter-reported symptom whose fix was 100% backend: before concluding
"the UI doesn't refresh," reproducing against the raw API response (curl)
ruled out a client-side caching/state bug in about two requests, redirecting
the investigation to where the real bug actually was.

## Dashboard avatar now shows the uploaded profile photo (2026-08-25)

`home_screen.dart`'s `_StaffDashboard` welcome-header `CircleAvatar` was
hardcoded to a plain person icon — it never read `profile_image_url` at
all, so the fix above (profile photos actually saving/loading) had no
visible effect on this one screen. Added a `profileImageUrl` parameter
(`account is StaffAccount ? account.profileImageUrl : null`, since
`HomeScreen`'s `account` is the sealed `AuthAccount` and only
`StaffAccount` carries this field on the staff-dashboard branch) and gave
the avatar the same `backgroundImage: NetworkImage(...)` /
person-icon-fallback pattern already used in `profile_screen.dart`.
Verified live on the Honor tablet: the header now shows the same photo
`/profile` shows, replacing the generic icon.

## Printer-not-connected alert on every print attempt (2026-08-25)

Every `PosPrinterService.printTicket()` failure now surfaces a SnackBar
instead of a bare `Text('... $e')` — new shared helper
`printing/presentation/printer_error_snackbar.dart`
(`showPrinterErrorSnackBar(context, messagePrefix)`), used at all four
print call sites: patient registration (`patient_registration_form_screen.dart`),
ticket reprint (`patient_registration_list_screen.dart`), payment receipt
(`patient_registration_payment_screen.dart`), and task-start receipt
(`task_progress_admin/presentation/task_progress_screen.dart`). The
SnackBar's action ("إعدادات الطابعة") jumps straight to
`/admin/printer-settings` instead of leaving the user to find that screen
themselves — reusing the `InstagramColors.blue` action-text-color fix
already established for `printer_settings_screen.dart`'s own Bluetooth-
scan-hang SnackBars, since the theme's default SnackBarAction color is
nearly invisible in dark mode.

Every failure gets identical treatment on purpose: `PosPrinterPlugin.kt`
funnels every `printTicket` failure path through one `finish(false,
error)` → `result.error("print_failed", error, null)`, with no distinct
error code for "not connected" versus anything else — matching specific
message strings here would be fragile, and in practice every failure this
plugin can produce *is* effectively "the configured printer wasn't
reachable."

Verified live on the Honor tablet against a real bonded-but-unreachable
Bluetooth printer and, more deterministically, against the "USB" connection
type with no device attached (`جهاز USB غير محدد أو تعذر فك ترميز
الصورة` — confirmed via `adb logcat`'s `PlatformException(print_failed,
...)`): the SnackBar reliably appears with the correct message and a
visibly blue action button. One rough edge found and left as a known
minor gap: `patient_registration_form_screen.dart`'s `_submit()` shows
the SnackBar and then immediately calls `Navigator.of(context).pop()` —
the SnackBar itself still renders correctly on the screen underneath
(this app's `ScaffoldMessenger` lives above the router, not per-route),
but the action's `onPressed: () => context.push(...)` closure captured
the now-popped screen's `context`; tapping the action from *this specific*
call site did not visibly navigate in testing, while the other three call
sites (which don't navigate away right after showing the error) are
unaffected. Not chased further this session — the alert itself (the part
actually requested) is confirmed working everywhere; only the action
button's navigation from the registration flow specifically may need a
`Navigator.of(context, rootNavigator: true)`-style fix if it turns out to
matter in practice.

## App icon set on Android, and the app renamed to "CDC" (2026-08-25)

The Android app was still shipping Flutter's default icon — the clinic
logo (`assets/branding/app_logo.png`) had only ever been wired into the
Windows desktop build's `flutter_launcher_icons` config
(`windows: { generate: true, ... }` in `pubspec.yaml`), left that way
deliberately per that entry's own comment ("nothing here was asked to
touch Android/iOS/web icons"). The user then asked for it directly.

The user also supplied a corrected version of the logo (fixes a missing
hamza: "الاسنان" → "الأسنان") and asked for its white background to be
removed. Replaced `assets/branding/app_logo.png` with the corrected
image, flood-filled its white background to transparent with ImageMagick
(`magick app_logo.png -fuzz 10% -fill none -draw "color 0,0 floodfill"`
from each corner, since the logo itself is a solid-filled circle with
nothing else touching the edges), then added `android: true` +
top-level `image_path` to the existing `flutter_launcher_icons` config
so `dart run flutter_launcher_icons` regenerates both the Android mipmap
launcher icons and the Windows `.ico` from the same source image. No
adaptive-icon foreground/background was configured — plain legacy
icons, matching the tool's default for `android: true` with no
`adaptive_icon_*` keys.

Also changed `AndroidManifest.xml`'s `android:label` from
`dental_clinic_app` to `CDC` (the launcher/recents display name — the
Dart package name `dental_clinic_app` in `pubspec.yaml` and the
`applicationId` were deliberately left untouched, since renaming either
is a materially bigger, riskier change than what was asked). Verified
live on the Honor tablet's home screen: the app icon is now the
transparent-background clinic logo (renders as a clean circular badge,
no white square behind it) and the label under it reads "CDC".

## Infectious-disease/viral-hepatitis lab screening gate (2026-08-26)

See `dental_laravel/README.md`'s matching entry for the full backend story
(schema, `PatientScreeningGate`, the new `patient_screening` permission
module, the `TaskInstance` → `PatientRegistration` linkage architecture
change, and the `screening_status` default-value bug found and fixed in
`Api\PatientRegistrationController::store()`). This entry covers the
Flutter side only: reception must scan a patient's ticket QR and record
"سليم"/"غير سليم" before that patient can be paid for or have a doctor's
task started against them.

- **No new domain classes** — the exact same
  `RegistrationPaymentState`/`PatientRegistration` models and
  `patientRegistrationRepositoryProvider.scan()` already used for the
  payment flow are reused everywhere here too; only
  `PatientRegistration` gained a `screeningStatus` field (parsed from the
  same JSON, defaulting to `'pending'` if absent) plus an
  `isScreeningClear` getter.
- **New screen**, `patient_registration_screening_screen.dart` (sibling
  of `patient_registration_payment_screen.dart`): shows the scanned
  patient's info and two buttons, "سليم" / "غير سليم", posting to the new
  `PatientRegistrationRepository.confirmScreening()` method.
- **Two new `QrScanMode` values** in the shared `qr_scan_screen.dart`
  (`patientRegistrationScreening`, `taskPatientLink`) — both resolve the
  *same* ticket QR via the *same* `scan()` call already used for payment;
  only what happens after differs (`patientRegistrationScreening` opens
  the new screening screen; `taskPatientLink` pops back to its caller
  with the resolved state via `context.pop(state)` instead of navigating
  forward — used by the task-start flow below). Three new routes in
  `app_router.dart` mirror the existing scan/payment route pair exactly.
- **New entry icon** in `patient_registration_list_screen.dart`'s app
  bar, next to the existing "مسح رمز الدفع" icon, plus a small colored
  status badge (green/orange/red for clear/pending/flagged) on every row
  in the list — so staff can see a patient's screening status at a glance
  without re-scanning.
- **Payment screen gate**: `patient_registration_payment_screen.dart`
  now checks `_state.registration.isScreeningClear` before showing the
  amount-entry form — if not clear, a red blocking banner replaces it
  entirely (distinct wording for "غير سليم" vs "not checked yet"). Pure
  UX; the server-side gate is what actually enforces this.
- **"بدء المهمة" now requires a patient scan first** —
  `task_progress_screen.dart::_startTask()` pushes the new
  `taskPatientLink` scan route before doing anything else, and refuses
  immediately (client-side, before even prompting for notes) if the
  scanned patient isn't `clear` yet. `TaskProgressRepository.start()`
  gained a required `patientRegistrationId` parameter, sent to the
  backend as `patient_registration_id` — the server enforces the same
  gate independently either way.

**Verified**: `flutter analyze` clean across all touched/new files. On
the Honor tablet: registered a test patient and confirmed the new
"بانتظار الفحص" (pending) badge shows on the registration list; opened
the new "فحص السلامة من الأمراض المعدية" icon and confirmed it opens a
scanner screen titled "مسح رمز الفحص" (correct `QrScanMode` routing);
from تقدم المهام, tapped "بدء المهمة" on an unassigned task slot and
confirmed it now opens "امسح رمز المريض" instead of the old notes-only
prompt (confirms the gate is wired in before the task-start call, not
just added to the backend). The backend logic this all calls into was
independently verified end-to-end via curl (see the other README) — the
camera QR-decode step itself is unchanged, already-proven code shared
with the existing payment-scan flow, so it wasn't re-demonstrated live in
this pass (doing so needs a physically printed ticket held up to the
tablet's camera, not something a single automated session can stage).
Test registration created during on-device verification was deleted
afterward via tinker.

## Printing now offers to turn Bluetooth on itself when it's off (2026-08-26)

The user asked: when the configured printer is Bluetooth and printing
fails because the adapter is simply off, open Bluetooth for the user
instead of just reporting a generic failure.

`PosPrinterService.printTicket()` (`pos_printer_service.dart`) now checks,
before ever invoking the native print channel: if
`settings.connectionType == PrinterConnectionType.bluetooth` and
`isBluetoothEnabled()` is false, it calls `requestEnableBluetooth()` —
Android's own "Allow app to turn on Bluetooth?" system prompt, already
used by the printer-settings screen — and throws a new
`BluetoothDisabledException` to abort *this* print attempt (that prompt
has no completion callback per its own doc comment, so there's no way to
synchronously wait for the user's answer and retry within the same call).

`showPrinterErrorSnackBar()` gained an optional `error` parameter so it
can special-case this: instead of every failure showing the same
"تحقق من توصيل الطابعة" + "إعدادات الطابعة" message, a
`BluetoothDisabledException` shows "البلوتوث غير مفعّل — وافق على تفعيله
ثم أعد الطباعة" with no settings-navigation action, since the system
prompt it just triggered is the whole fix. All four existing print call
sites (`patient_registration_form_screen.dart`,
`patient_registration_list_screen.dart`,
`patient_registration_payment_screen.dart`, `task_progress_screen.dart`)
needed only a one-line change each — passing `error: e` through to the
already-shared helper — since they already funnel every print failure
through it. Deliberately scoped to `connectionType == bluetooth` only,
not the `builtin` mode's own internal Bluetooth-SPP fallback (see that
enum's doc comment) — the user's request was specifically about the
explicit Bluetooth printer setting.

`flutter analyze` clean. Not yet re-verified live with the adapter
actually toggled off on-device in this pass — the underlying
`isBluetoothEnabled`/`requestEnableBluetooth` channel methods are
pre-existing and already proven from the printer-settings screen's own
earlier Bluetooth-scan-hang fix; only the new call site inside
`printTicket()` and the snackbar branching are new here.

## Web lab-screening UI, and a payment form that was failing silently (2026-08-26)

See `dental_laravel/README.md`'s "Follow-up, same day" note on the
infectious-disease screening entry — this is the Flutter-repo-adjacent
pointer for the web-side fix: `PatientRegistrations/Index.vue` gained a
direct "سليم"/"غير سليم" confirmation modal (no camera scan needed on
web — staff already see the row), and `Payments/Create.vue` gained the
flash-error banner it was completely missing, so a payment blocked by
`PatientScreeningGate` stops failing silently on the web form.

## Fixed: not enough paper feed after a Bluetooth/USB ticket to clear the tear bar (2026-08-26)

Real hardware issue reported by the user, testing on an actual POS
terminal (a second physical device, model "Q2i", connected for this
specific report): after every ticket printed via Bluetooth or USB, they
had to manually press the printer's own feed button to advance the paper
enough to tear it off without cutting into the QR code.

Root cause, `PosPrinterPlugin.kt`'s `bitmapToEscPosRaster()` — the
function that turns the rendered ticket bitmap into raw ESC/POS bytes for
*both* the Bluetooth (`printBluetooth`) and USB (`printUsb`) code paths
(confirmed the single shared function; the builtin AIDL path doesn't go
through it at all, which is exactly why the user only saw this on
Bluetooth/USB) — sent `ESC d 4` (feed 4 print lines) right after the
image data, then returned. At a thermal printer's typical default line
spacing (~1/6", ~4.2mm/line), 4 lines is only ~17mm of trailing feed —
not enough clearance past the QR code for the tear bar on this hardware.
Changed to `ESC d 8` (~34mm), doubling the trailing margin.

**Verified**: rebuilt and installed on the Q2i device itself — builds and
launches cleanly (Kotlin native-code change, so this required a full
rebuild, not a hot reload). Could not verify the actual physical paper
distance live in this pass: the device's printer settings were currently
set to "الطابعة المدمجة" (builtin) with no USB device connected at the
time, so there was nothing to print a real ticket to. The code change
itself is a one-line, low-risk constant increase in an already-isolated
function used nowhere else — worth a live print/tear test with the real
Bluetooth or USB printer connected to confirm 8 lines is enough (and
isn't excessive) before considering this fully closed.

## "المختبر" added as a dashboard shortcut, on both platforms (2026-08-26)

The user pointed out the infectious-disease screening feature had no
visible home for it — not on the dashboard, not listed as its own
section — the only way in was a small icon buried inside the patient
registrations list. Added a proper "المختبر" quick-access tile:

- **Flutter**: `home_screen.dart`'s `_StaffDashboard` shortcuts grid
  gained a fifth tile, "المختبر" (`Icons.coronavirus_outlined`), pushing
  straight to the existing scan-screening route
  (`/records/patient-registrations/scan-screening`) — same destination
  the patient-registrations list icon already used, just promoted to a
  first-class dashboard shortcut alongside "تسجيل مريض جديد"/"المواعيد"/
  "الدفعات"/"تقدم المهام". `GridView.count`'s 2-column layout handles the
  odd fifth tile fine (renders on its own row).
- **Web**: `DashboardController::index()`'s `can` prop gained
  `patient_screening` (checking the `patient_screening.confirm`
  permission, same module added alongside the original feature), and
  `Dashboard.vue`'s "Quick access" card grid gained a matching "المختبر"
  card linking to `patient-registrations.index` (which already has the
  "سليم"/"غير سليم" confirmation modal from the same-day web-UI
  follow-up above).

Verified live on-device (Q2i tablet): logged in, confirmed the new
"المختبر" tile renders as the fifth shortcut card, and tapping it opens
"مسح رمز الفحص" correctly. `flutter analyze`, `npm run build`, and
`php -l` all clean.

## Tap a patient row to pay, not just to scan (2026-08-26)

Follow-up to the same-day web "find the patient by QR scan or search"
change: the user asked for the "also for app" version. Flutter already
had both QR-scan and quick-digit (0/00/000) buttons on the payment
screen, so the actual gap was narrower — `patient_registration_list_screen.dart`'s
existing name/phone search UI (used elsewhere for picking a patient in
"pick mode") did nothing when tapped outside of that mode; there was no
way to go from "found the patient by typing their name" straight to
paying without also scanning their ticket.

Fixed by wiring the row's normal (non-pick-mode) tap to open the payment
screen directly:

```dart
onTap: widget.pickMode ? () => Navigator.of(context).pop(r) : () => _openPayment(context, r),
```

`_openPayment()` fetches the registration's current state via the
existing `patientRegistrationRepositoryProvider.status(id)` (the same
call the QR-scan path already makes after decoding) and pushes to
`/records/patient-registrations/payment` with it — so the screening gate
banner and payment form behave identically whether the patient was found
by scan or by search.

**Verified** live on the Q2i device: searched by name, tapped the row,
payment screen opened correctly with the right patient.

## Bigger QR code on the printed ticket (2026-08-26)

The user asked for a larger QR on the ticket used for both payment and
lab-screening scans — `ticket_widget.dart`'s `qrSize` bumped from `widthDots
* 0.55` to `* 0.75`. Still scales with paper width (58mm/384 dots vs
80mm/576 dots) rather than a flat pixel size, so it stays proportionate
on both paper sizes.

**Verified** live on the Q2i device: registered a fresh test patient and
caught the print-animation frame — the QR now visibly fills most of the
ticket's width, a clear, easy-to-compare jump from the old size on the
same hardware.

## New app icon on Android/iOS, and the login screen rebuilt on the ambient theme (2026-08-27)

The user supplied a new college seal logo (a photo with a white square
background) to use as both the in-app logo and the launcher icon on
Android and iOS, and reported that on the login screen, whatever you
typed into the username or password field was invisible — white text on
a near-white field.

**Logo processing**: `magick ... -fuzz 8% -transparent white -trim` keyed
out the white background and cropped to the circular seal, then three
derived assets went into `assets/icon/`: an opaque white-background
version for iOS (`app_icon_ios.png` — Apple's icon slot doesn't support
transparency at all), a safe-zone-inset transparent foreground and a
solid-white background for Android's adaptive icon
(`app_icon_foreground.png` / `app_icon_background.png`), plus the plain
transparent logo replacing `assets/branding/app_logo.png` itself (used
in-app on the login/splash screens, which sit on a dark background — an
opaque white square around the logo there would look wrong).

`pubspec.yaml`'s existing `flutter_launcher_icons` config (Android +
Windows only until now) gained `ios: true`, `image_path_ios` pointing at
the opaque variant, and `adaptive_icon_background`/
`adaptive_icon_foreground`. **First attempt failed**: setting
`remove_alpha_ios: true` on the transparent source instead of using a
dedicated opaque one produced a solid **black** iOS icon — that flag only
forces the alpha channel to fully opaque, it doesn't composite onto
anything, so whatever RGB value ImageMagick had stored under fully
transparent pixels (black, `xc:none`'s default) was revealed as-is once
alpha stopped hiding it. Switched to a pre-flattened white-background
source for iOS specifically instead of relying on that flag. Ran `dart
run flutter_launcher_icons` locally and confirmed both the generated
`Icon-App-1024x1024@1x.png` and an Android `mipmap-xxxhdpi/ic_launcher.png`
render correctly (checked by eye, not just "the command exited 0").

**Login screen — root cause of the invisible text**: not a per-field
color miss, but an architectural one. `LoginScreen` had its own hardcoded
navy/gold palette (`_navyDark`/`_gold`/etc., matching `SplashScreen`) with
each field's `fillColor` hand-set to a near-white grey — but never set
the typed *text* color, which fell through to `app_theme.dart`'s ambient
`instagramDarkTheme`/`instagramLightTheme` (already a real, correctly
light/dark-aware Instagram-accurate theme, complete with its own
`inputDecorationTheme` — this app just wasn't using it on this one
screen). In dark mode that ambient default is near-white text — on a
near-white hardcoded field fill, invisible.

**Fix**: rebuilt `LoginScreen` to use the ambient theme instead of
fighting it — plain `Scaffold` background, `TextFormField`s with no
color/border overrides at all (so they inherit the theme's already-correct
`inputDecorationTheme`), the button using `filledButtonTheme`'s default
Instagram blue. This fixes the contrast bug at the root (any future theme
tweak now applies here too, instead of this screen silently drifting out
of sync again) and, incidentally, is the actual redesign the user asked
for: the screen now looks like the rest of the app's Instagram-styled UI
instead of a one-off branded page. `SplashScreen` was deliberately left
on its own navy/gold look — only the login screen was in scope here — so
there's now a brief, intentional style handoff between the two rather
than one continuous brand experience; flagging it since the two screens'
own doc comments used to describe that continuity as deliberate.

`flutter analyze`: clean, no issues. Not yet verified on a real device in
this pass — worth a live check that the logo displays correctly and both
fields are legible in both light and dark mode before considering this
fully closed.

## Three iOS gaps found testing on a real iPhone (2026-08-27): missing permission strings, and one real feature gap

First real iOS device test (via AltStore/AltServer sideloading — see the
main README's SSH/deploy section for that saga) surfaced three broken
features. `ios/Runner/Info.plist` had exactly one usage-description key
(`NSCameraUsageDescription`, added for `mobile_scanner`'s QR check-in) —
every other permission-gated feature this app has added since was never
given its matching iOS permission string, so iOS silently refused each
one rather than even showing a prompt.

**Fixed — profile photo upload**: added `NSPhotoLibraryUsageDescription`.
`image_picker` itself has full iOS support; the missing Info.plist key
was the entire gap. Not yet re-verified on-device in this pass (no
rebuild/reinstall cycle happened after the fix), but this class of fix —
add the description string the plugin's own docs require — is
low-risk and well-understood.

**Partially fixed, hard platform limit remains — NFC doctor-tag
reading**: added `NFCReaderUsageDescription` to Info.plist and a new
`ios/Runner/Runner.entitlements` declaring
`com.apple.developer.nfc.readersession.formats`, wired into all three
Runner build configs' `CODE_SIGN_ENTITLEMENTS` in `project.pbxproj`.
**This will very likely still not work.** CoreNFC's entitlement is one of
several Apple restricts to apps signed with a paid Apple Developer
Program membership ($99/year) — a free/personal-team signature (which is
what AltServer/AltStore uses, and what this whole sideloading setup is
built on) has this entitlement stripped during signing regardless of
what's declared in the project. The code-level setup is now correct and
complete for the day a paid account exists; until then, expect the same
"NFC reader not available" error, just from a different point in the
stack (a stripped entitlement instead of a missing Info.plist key).

**Not fixed — Bluetooth printer scanning has no iOS implementation at
all**: this one isn't a missing permission string. Added
`NSBluetoothAlwaysUsageDescription`/`NSBluetoothPeripheralUsageDescription`
to Info.plist regardless (necessary infrastructure either way), but
`pos_printer_service.dart`'s Bluetooth scan/pair/print calls all go
through a custom `MethodChannel`
(`com.dentalclinic.dental_clinic_app/pos_printer`) whose *only*
implementation is `PosPrinterPlugin.kt` — Android-only. `ios/Runner/
AppDelegate.swift` has no Bluetooth code whatsoever. Adding the
permission strings lets iOS *ask* the question; there's still no native
Swift/CoreBluetooth counterpart on the other end to actually scan for or
print to a device. That's a real native-development task (scanning,
pairing semantics differ from Android's "paired devices" list, and BLE
vs. classic-Bluetooth-SPP support depends on what protocol these printers
actually speak), not a config fix — flagging it rather than attempting a
blind implementation with no printer hardware to test against from here.

## Each case now links to its clinical form, matching the web (2026-08-27)

The web app has always resolved a case's clinical form ("نموذج سريري")
via `CaseSheetController::open(TaskInstance $taskInstance)` — reopening
the existing sheet for that case if one exists, otherwise a blank one
pre-linked via `task_instances_id`. Flutter's `case_sheet_forms` feature
never had this: it was a free-standing "browse my records of type X"
flow whose create payload never sent `task_instances_id` at all, and
neither `my_tasks_screen.dart` nor `task_instance_detail_screen.dart` had
any button to open one. See the main `README.md`'s matching entry for the
new backend endpoints this relies on
(`Api\CaseSheetController::open()`, `Api\PendingTaskQrController::show()`).

**`CaseSheetFormScreen`** gained an optional `taskInstanceId`, carried as
a `task_instances_id` query param on both its go_router routes
(`/case-sheets/:resource/new` and `/case-sheets/:resource/:id`). Its
`_create()` payload now includes it when present. After a successful
create, the redirect to the resulting edit screen
(`context.pushReplacement('/case-sheets/$resource/${created['id']}')`)
now carries the same query param forward — otherwise the new "رمز QR"
button (below) would only be visible until the very next navigation.

**New shared `showQrDialog()`** (`core/widgets/qr_dialog.dart`) wraps the
existing `QrImage` widget in an `AlertDialog`, parametrized by
`imagePath`/`title`/`caption` — one helper instead of three near-identical
`AlertDialog`s. Used at:
- `my_tasks_screen.dart`'s `_SlotRow` (now a `ConsumerStatefulWidget`,
  changed from `StatelessWidget` to hold the "opening..." spinner state) —
  every case row gets a QR icon **regardless of whether it's started yet**.
  This was a mid-implementation correction: the QR on an unstarted "لم
  تبدأ بعد" row isn't gated on having a real instance — it's the
  *pending_task* QR (task+doctor, identical across every remaining
  unstarted slot of the same task, matching `TaskStarter`'s existing
  fungible-pending-slot pooling — there's no finer-grained identity until
  one is claimed), which is exactly what a senior scans to *start* that
  case. Once started, the icon switches to the real per-instance QR
  instead. A second icon, "نموذج سريري", appears only once a case has
  started (nothing to link a sheet to before then) and calls the new
  `CaseSheetRecordRepository.openFor()` to resolve/navigate.
- `case_sheet_form_screen.dart` — an AppBar action icon (instance QR only,
  a sheet only ever exists once a case has started).
- `task_instance_detail_screen.dart` — replaced the old always-visible
  inline `QrImage` with the same on-demand button (for consistency across
  all three touchpoints), and added the "نموذج سريري" button this screen
  never had.

**Admin/senior QR lookup needed zero new code**: `task_progress_screen.dart`
already had a "مسح رمز مهمة" button reusing `QrScanMode.taskInstance` —
`Api\TaskInstanceQrController::scan()`'s ownership check only fires
`if ($doctor instanceof Doctor)`, so a staff caller already received the
full result before this change. It lands on `TaskInstanceDetailScreen`,
which now shows the new "نموذج سريري" button too — so a senior scanning a
case's QR already chains straight into its clinical form.

`flutter analyze`: clean across every touched file. Backend verified via
curl (see main `README.md`); the Flutter side itself has not yet been
exercised on a real device in this pass — worth a live check of the two
new icons on an unstarted vs. started case row, and that a sheet created
this way actually persists `task_instances_id`.

## iOS printing support — a new Bluetooth-LE native plugin (2026-08-28)

Printing only ever worked on Android before this — `PosPrinterPlugin.kt`
speaks classic Bluetooth SPP, a vendor AIDL POS-terminal SDK, and Android's
USB host API, none of which iOS can reach for a non-MFi-certified device
(third-party iOS apps get CoreBluetooth for Bluetooth, which is BLE-only —
no classic SPP; and no general USB-host API at all). So the four print
call sites either threw `MissingPluginException`
(`task_progress_screen.dart`, which had no platform guard at all) or were
silently skipped by an explicit `Platform.isAndroid` check
(`patient_registration_form_screen.dart`,
`patient_registration_payment_screen.dart`,
`patient_registration_list_screen.dart`).

**The real printer already in production** (a generic "58E" thermal
receipt printer) was confirmed, live via the LightBlue BLE-scanner app, to
support Bluetooth LE — not just the classic SPP Android already uses. It
exposes GATT service `0xFF00` (`0xFF01` notify / `0xFF02` write+writeWithoutResponse
/ `0xFF03` notify — the extremely common generic-Chinese-BLE-serial-module
pattern used by countless cheap ESC/POS printers) and an alternate service
`0x18F0` (`0x2AF0` notify / `0x2AF1` write). Its advertisement packet does
**not** include a service UUID, confirmed the same way — any scan that
filters by service UUID would never see it.

**New file: `ios/Runner/PosPrinterPlugin.swift`** — a `CoreBluetooth`-based
plugin wired to the *exact same* two channel names Android already uses
(`com.dentalclinic.dental_clinic_app/pos_printer` MethodChannel,
`.../pos_printer/bt_scan_events` EventChannel), so `pos_printer_service.dart`
needed **zero changes** — iOS is simply a second native backend for the
same Dart API. `bitmapToEscPosRaster()`'s exact algorithm (including the
`ESC d 8` trailing-feed constant from the earlier tear-bar fix, which is a
hardware fact about this physical printer, not an OS detail) was ported
byte-for-byte, just rewritten from Android's single-call `Bitmap.getPixels()`
to a `CGContext`-based RGBA pixel read (iOS has no equivalent shortcut).
Scans for *all* nearby BLE peripherals (`withServices: nil`) rather than
filtering, connects on demand, discovers `FF00`→`FF02` first with `18F0`→`2AF1`
as a fallback, writes the raster in MTU-sized chunks (`.withResponse`,
since this class of cheap BLE-serial-bridge printer is known to drop
unthrottled `.withoutResponse` writes), waits the same 2000ms Android does
before disconnecting (the printer buffers asynchronously — an early
disconnect truncates the job, regardless of OS), and bounds every
operation with connect/write timeouts so a broken or out-of-range printer
fails cleanly instead of hanging the Dart `Future` forever.

**Where iOS's behavior genuinely differs from Android's** (each a real
platform constraint, not an oversight):
- `requestEnableBluetooth` is a no-op success — iOS has no programmatic
  "turn on Bluetooth" API at all (Apple deliberately doesn't expose one to
  third-party apps). Dart's `printTicket()` already throws
  `BluetoothDisabledException` regardless of this call's outcome, so the
  net effect matches Android's own "no completion, user re-taps طباعة"
  behavior — just without an in-between system dialog.
- `listPairedDevices` returns `[]` — BLE has no OS-level "bonded devices"
  list an app can enumerate (only peripherals *this app* has previously
  connected to, retrievable by identifier, not a general query).
- `pairDevice` doesn't "pair" in the classic-SPP sense (no bonding, no PIN
  dialog) — it connects, resolves the FF00/18F0 GATT profile, then
  immediately disconnects and reports success/failure. That's the honest
  BLE equivalent of "prove this address is a real, connectable printer,"
  which is all the settings screen's pairing flow actually needs.
- `isLocationEnabled` always reports `true` — BLE scanning has never
  needed Location on iOS (that's an Android classic-Bluetooth-discovery-
  only historical quirk); the settings screen's location-nag banner and
  its `Permission.locationWhenInUse` request are both skipped on iOS now
  too (`printer_settings_screen.dart`), since asking for it there would
  just be a confusing, purposeless prompt.
- "الطابعة المدمجة" (builtin, a vendor AIDL SDK for one specific Android
  POS terminal) and "USB" are impossible on iOS and no longer offered
  there at all — `printer_settings_screen.dart`'s connection-type
  selector only shows "بلوتوث" on non-Android. A fresh iOS install also
  no longer seeds from the shared `builtin` default (impossible there);
  `printer_settings_repository.dart`'s "nothing saved yet" fallback is
  now platform-aware, resolving straight to `bluetooth`.
- **All four print call sites now work identically on iOS and Android** —
  the three that were previously Android-only guards
  (`patient_registration_form_screen.dart`,
  `patient_registration_payment_screen.dart`,
  `patient_registration_list_screen.dart`) were relaxed to
  `Platform.isAndroid || Platform.isIOS`, confirmed with the user as the
  intended scope (full parity, not just the one screen that happened to
  already be unguarded).

**A genuinely easy-to-miss step, worth flagging for anyone touching this
again**: `ios/Runner.xcodeproj/project.pbxproj` is a manually-maintained
file list, not a glob — Xcode/`xcodebuild` won't compile a new `.swift`
file dropped into `ios/Runner/` unless it's *also* registered at 4 points
in that file (`PBXBuildFile`, `PBXFileReference`, the `Runner` group's
`children`, and the `PBXSourcesBuildPhase`'s `files` list), each needing a
fresh, unique 24-hex-digit ID. Skipped, this produces a confusing "cannot
find 'PosPrinterPlugin' in scope" Codemagic build failure with no obvious
cause — the file exists on disk in the right place, it's just never
handed to the Swift compiler.

**Verified**: `flutter analyze` clean across every touched file. Not yet
verified on a real device against the actual "58E_BD90" printer (no Mac
locally — ships via the existing Codemagic `ios-workflow` → AltStore
sideload pipeline) — still to confirm: the printer appears in the
discovered-devices scan, pairing succeeds, a real ticket prints in full
(no truncation) with correct Arabic rendering and adequate paper feed
before tear, and that a broken/out-of-range printer fails within the
~10-second connect timeout rather than hanging.

## Two real bugs found testing the above on the real device (2026-08-28)

**Bluetooth scan permanently blocked on iOS**: `printer_settings_screen.dart`'s
`_scanBluetooth()` requested `Permission.bluetoothScan`/`Permission.bluetoothConnect`
unconditionally — those are Android-12+-only permission *types*;
`permission_handler` has no iOS mapping for them and always reports them
denied there, regardless of the real CoreBluetooth permission
(`NSBluetoothAlwaysUsageDescription`) the user had already granted. So the
"يلزم إذن البلوتوث للبحث عن أجهزة" error showed every time on iOS, even
after granting Bluetooth access, and the scan never actually ran. Fixed:
iOS now requests `Permission.bluetooth` instead (the correct iOS-side
permission type in this package). Verified live: scan found "58E_BD90"
and pairing succeeded once this was fixed.

**Printing from Task Progress did nothing on iOS, silently** — a second,
separate guard from the three call sites already fixed above:
`task_progress_screen.dart`'s `_printReceipt()` had its own early-return
at the top of the function (`if (kIsWeb || !Platform.isAndroid) return;`),
missed in the original sweep because the earlier review only checked the
line calling `printTicket()` itself, not the whole function it's nested
in. This made the "طباعة الوصل بعد بدء المهمة" flow a complete no-op on
iOS — no ticket, no error, nothing — even after the BLE plugin and
pairing both worked correctly. Relaxed to
`!(Platform.isAndroid || Platform.isIOS)`, matching the other three
call sites. **Lesson for next time**: grep the whole file for
`Platform.isAndroid`, not just the line near the specific call being
changed — a guard can sit several dozen lines above the code it protects.

## "نسيت كلمة المرور؟" added to the Flutter login screen (2026-08-28)

The web app has had password reset for a while (`Auth\DoctorPasswordResetController`
for doctors, Breeze's own flow for staff — see main `README.md`), but the
Flutter login screen had no way to trigger either one; a doctor who forgot
their password had no self-service path at all on mobile.

Added `POST /api/v1/forgot-password` (`Api\PasswordResetController`) —
unified across both account types the same way `AuthController::login()`
is: tries the `users` table first, then `doctors`, and always returns the
same neutral "if this email is registered, a reset link was sent" message
regardless of which (or neither) matched, so the endpoint can't be used to
probe which emails are registered accounts. Deliberately **does not**
build a native in-app reset-token screen — completing the reset happens by
opening the emailed link, which lands on the existing web reset-password
page (already built, already working, and now reachable from a mail
client on the same phone). Duplicating that whole form natively for a
rarely-used flow wasn't worth the upkeep of two copies to keep in sync.

`login_screen.dart` gained a "نسيت كلمة المرور؟" text button under the
password field, opening a small dialog (email field only) that calls the
new endpoint via `AuthRepository.sendPasswordResetLink()` and shows the
server's neutral confirmation message in a `SnackBar`.

`flutter analyze` and `php -l` both clean; `php artisan route:list`
confirms the route registers correctly. Not yet tested against a real
mailbox end-to-end from the app itself — the underlying `Password::broker()`
send-reset-link call and the production SMTP config it depends on were
already verified working independently (see main `README.md`'s SMTP
section), so this is a thin, low-risk wrapper around both.

## Third real iOS printing bug: pairing had nothing to select from (2026-08-28)

Found live, after fixing the previous two: even after a successful scan +
pair on iOS, printing still failed — `[bad_args: عنوان بلوتوث مفقود]`
(surfaced only once the temporary raw-error-detail addition above shipped;
the generic message alone gave no way to tell this apart from a real
connection failure).

Root cause: `printer_settings_screen.dart`'s pairing flow is two steps —
tap "اقتران" on a *discovered* device (`_pair()`, calls `pairDevice`),
then tap "تحديد" on that same device once it reappears in the *paired*
devices list (`_selectBluetoothDevice()`, the only place that actually
sets `draft.bluetoothAddress`). That second list comes from
`listPairedDevices()`, which reflects Android's real OS-level bonded-
devices list there — but always returns `[]` on iOS (`PosPrinterPlugin.swift`,
since BLE has no equivalent concept, see that file's method table). So on
iOS, a successful pair had nothing to ever reappear in, no "تحديد" step
was ever reachable, and `bluetoothAddress` was never saved — printing
then failed immediately with "address missing," independent of whether
the printer itself was reachable at all.

Fixed in `_pair()`: on iOS, a successful pair now calls
`_selectBluetoothDevice()` directly instead of `_loadPairedDevices()` —
pairing *is* the selection there, since there's no separate persisted
"paired" state to browse back into later. Android's existing two-step
flow is unchanged. The user still needs to tap "حفظ" afterward to persist
the selection, same as Android.

Not yet re-verified against the real "58E_BD90" printer after this fix —
next on-device test should confirm a full print succeeds end-to-end now
that all three iOS-specific bugs (Bluetooth permission, the Task
Progress print guard, and this selection gap) are fixed.

## Optional case-sheet drafts for not-yet-started task slots (2026-08-28)

`my_tasks_screen.dart`'s `_SlotRow` showed "نموذج سريري" only once a slot
had actually started (a real `TaskInstance`). Now shown on every slot —
an unstarted one calls the new `_openCaseSheetForTask()` (hits
`CaseSheetRecordRepository.openForTask(taskId)` →
`GET /api/v1/tasks/{task}/case-sheet-draft`) instead of the existing
`_openCaseSheet()`, navigating with `?task_id=` instead of
`?task_instances_id=` in the query string. See main `README.md` for the
full design — this is deliberately **not** a real task-instance/screening-
gated start, just an optional draft keyed by (doctor, task), since the
original PHP app's equivalent flow silently started a real instance,
which would have bypassed this project's own infectious-disease
screening gate.

`CaseSheetFormScreen` gained a `taskId` parameter (mutually exclusive
with the existing `taskInstanceId`) — `app_router.dart`'s two
`/case-sheets/:resource/*` routes now also read `task_id` from the query
string, and `_create()`'s payload sends `task_id` instead of
`task_instances_id` when that's what's set. No "رمز QR" action for a
task_id-linked draft (unlike the instance-linked case) — there's no
task-instance QR to show yet.

`flutter analyze` clean. Backend verified independently via curl (see
main `README.md`) — this Flutter wiring itself not yet exercised
on-device in this pass.

## iOS printing worked but was slow — user-selectable safe/fast Bluetooth write mode (2026-08-28)

Confirmed live: after the three fixes above, printing from the real
"58E_BD90" printer succeeded reliably — but noticeably slower than
Android. Cause: `resolveWriteCharacteristic()` in `PosPrinterPlugin.swift`
always chose `.withResponse` (waits for an explicit ack after every
~20-180-byte chunk) whenever the characteristic supported plain `.write`
at all — which FF02 does, alongside `.writeWithoutResponse` — so it never
took the faster path even though the hardware supports it. `.withResponse`
was originally the conservative default because this class of cheap
BLE-serial-bridge printer is known to sometimes drop unthrottled writes;
with reliable printing now confirmed, `.withoutResponse` (paced by
`canSendWriteWithoutResponse`/`peripheralIsReady`, not unthrottled) is
worth using instead — a full ticket's per-chunk ack round-trip was the
dominant cost, not the fixed 2-second post-write drain.

Rather than just flip the default, this is now a printer-settings toggle:
new `BluetoothWriteMode { fast, safe }` on `PrinterSettings`
(`printer_settings.dart`), persisted in `printer_settings_repository.dart`,
sent as `bluetoothWriteMode` in `printTicket()`'s method-channel args
(`pos_printer_service.dart`), and read by `PosPrinterPlugin.swift` to
decide `usesWriteWithoutResponse` — `"safe"` opts out of
`.withoutResponse` even when the characteristic supports it, in case a
different physical printer unit needs the slower-but-more-conservative
path. `printer_settings_screen.dart` gained a "وضع الطباعة" segmented
control ("سريع"/"آمن"), shown only on iOS (Android's classic Bluetooth
SPP has no such distinction — nothing to toggle there). Defaults to
`fast`.

Also asked to "activate the printer's pairing code" — clarified with the
user that there's no evidence this specific printer's GATT profile
requires BLE bonding/authentication (its characteristics showed no
encrypted-write requirement in the LightBlue scan). If a printer unit
ever does require it, iOS's own system "Bluetooth Pairing Request" dialog
appears automatically during `centralManager.connect()` — this is
OS-level, invisible to and uncontrollable by the app (same category as
`requestEnableBluetooth`'s no-op — see the first iOS printing entry
above), so there's nothing to build here unless a real PIN requirement is
ever confirmed on an actual unit.

## Supervisor case-sheet preview, paper confirmation, and QR patient-autofill (2026-08-28)

Matches the web feature of the same name (see `README.md`) — a
staff/admin viewer can now open a doctor's case sheet from Task Progress
here too (previously nothing in this screen could open one at all), a
doctor can mark a case as paper-documented without hiding the electronic
form, and a case-sheet form can autofill its patient-identity fields from
the same registration ticket QR used elsewhere.

**`DynamicSectionForm`'s `State` class was made public** (renamed
`_DynamicSectionFormState` → `DynamicSectionFormState`) so
`CaseSheetFormScreen` can reach into it via a `GlobalKey` — the only way
to programmatically fill a field from outside, since select/radio/
checkbox/date/time fields read straight from the form's internal
`_values` map in their own `build()` (a parent-level `setState()` after
mutating `_values` correctly cascades to them) while text-controlled
fields (`text`/`textarea`/`number`/`decimal`/`teeth`) are bound to a
`TextEditingController` instead, which needs its `.text` set directly —
`onChanged` only fires on user interaction, never on a programmatic
assignment. New public `setFieldIfBlank(formKey, value)` handles both
paths and only ever fills a currently-blank field. New `readonly` (default
`false`) + `supervisorEditableFields` (default `[]`) params drive the same
per-field `fieldDisabled()`/`canSubmit` logic the web's `SectionedForm.vue`
now has — previously `readonly` was hardcoded `true` at the one call site
that existed, dead code as far as `false` was concerned, since nothing
reachable from this app ever passed anything else in.

**`CaseSheetFormScreen`** gained matching `readonly`/`supervisorEditableFields`
constructor params, round-tripped through `app_router.dart`'s
`/case-sheets/:resource/:id` route as `?readonly=1&supervisor_fields=a,b`
query params (this screen is reached by pushing a URL, not by passing
widget constructor args directly, so the state has to survive that
trip) — resolved once by the caller from `Api\CaseSheetController::open()`'s
new `readonly`/`supervisor_editable_fields` response fields, the same
call `openFor()` already made to resolve `resource`/`record_id`. Also
gained a "مسح رمز المريض" `AppBar` action (hidden when `readonly`, or
when the resource has no known patient-field mapping) that pushes a new
`/case-sheets/scan-patient` route (`QrScanMode.caseSheetPatientAutofill`
— same scan/resolve/pop-with-result shape as the existing
`QrScanMode.taskPatientLink`, kept as its own enum value so the call
site and this screen's title read clearly rather than reusing an
unrelated-sounding name), then fills whichever fields the new
`CaseSheetPatientFieldMap` maps for that resource — a straight Dart port
of the identical per-resource field-name map now in `SectionedForm.vue`
(deliberately duplicated rather than fetched from a new endpoint — same
call this project already made for `CaseSheetResolver`'s own map having
no client-side API equivalent either).

**`task_progress_admin/presentation/task_progress_screen.dart`** gained a
"معاينة الكيس شيت" button on every slot card with an instance — this
screen previously had zero case-sheet-opening capability for staff at
all. Resolves via the existing `CaseSheetRecordRepository.openFor()`,
same as the doctor side; shows a snackbar instead of navigating when the
doctor hasn't started filling anything in yet (staff can't create a
record, only edit the 2-ish supervisor fields on one that exists).

**"تأكيد أنه ورقي"** — `my_tasks_screen.dart` gained a small text button
next to each started slot's status (a "موثّق ورقياً" badge once
confirmed), calling a new `TaskInstanceRepository.confirmPaper()` →
`POST /task-instances/{id}/confirm-paper`. `TaskSlotCard` gained a
`paperCaseSheetConfirmedAt` field, populated by the shared
`TaskProgressGroupSummary::build()` backend service so both this screen
and the admin task-progress screen see it.

**Three real, pre-existing/newly-introduced backend bugs found live via
curl while testing this feature** (full detail in `README.md`, since all
three are backend-only and this app is just the client that would have
silently misbehaved because of them): (1) `EnforceCaseSheetAccess`'s
API-vs-web route-name parsing bug, which zeroed every resource's
supervisor-field list on the API at all times — a staff save of even its
own allowed fields always 403'd, and a doctor could freely overwrite
those same fields; (2) `TaskInstance::$fillable` missing the two new
paper-confirmation columns, so `confirm-paper` always returned a clean
200 with nothing actually written; (3) `Api\DentalChartController`
missing `senior_signature` from its validation rules (and
`DentalChartResource` never exposing it in output at all) — a
`dental-charts` supervisor save silently no-op'd even after the other
two fixes. None of these are Flutter-side bugs, but all three would have
made this exact feature appear broken from the app with no client-side
fix possible.

**A fourth real bug, this one Flutter-side, found live on-device**: the
new `/case-sheets/scan-patient` route opened a blank screen titled
"scan-patient" with "حدث خطأ في الخادم، حاول مرة أخرى." instead of the QR
scanner. Cause: `go_router` (14.8.1) matches sibling routes by trying
each in registration order and returning the *first* match — no
specificity-based sorting between a static segment and a `:param` one
(confirmed by reading `configuration.dart::_getLocRouteMatches()`
directly rather than assumed). `/case-sheets/:resource` was registered
*before* `/case-sheets/scan-patient` in `app_router.dart`, so it matched
first and captured `resource: 'scan-patient'`, routing to
`CaseSheetRecordListScreen` instead — which then failed fetching records
for a resource that doesn't exist, producing exactly that generic error.
Every other `:param` route in this file happened to already have its
static siblings (`/new`, the whole `/records/patient-registrations/...`
tree) registered in an order that didn't collide; this was the first new
static route added as a *sibling* of an existing `:param` route at the
same path depth. Fixed by moving the static route before the dynamic
one — the correct fix given go_router's actual (order-only) matching
behavior, not just a workaround.

Verified: `flutter analyze` clean project-wide. Backend verification
(curl against the local dev server, real Sanctum tokens) covered in
`README.md`'s matching entry.

## Fixed: a doctor's "مسح رمز المريض" scan always 403'd (2026-08-28)

Found live on a real device right after shipping the feature above: the
scan screen opened correctly (confirming the earlier route-order fix
worked) but every scan attempt returned "لا تملك صلاحية لهذا الإجراء."
`PatientRegistrationRepository.scan()` hits a `permission:patients,view`-gated
route that rejects any Doctor principal outright by design (see
`README.md`'s matching entry) — no doctor session could ever have
succeeded there, on web or Flutter.

Fixed by pointing `QrScanMode.caseSheetPatientAutofill` at a new
`PatientRegistrationRepository.scanForCaseSheet()` method (→
`POST /patient-registrations/scan-for-case-sheet`, doctor-only, also
enforcing `PatientScreeningGate` server-side) instead of reusing `.scan()`
— `taskPatientLink` and `caseSheetPatientAutofill` were split into their
own `switch` cases in `qr_scan_screen.dart` for this (previously shared
one case, since both used to call the same repository method the same
way). Same `RegistrationPaymentState` response shape either way, so
nothing else in `CaseSheetFormScreen`'s autofill logic needed to change.

A patient who hasn't been lab-screened yet, or came back flagged, now
surfaces the exact `PatientScreeningGate` message
("لا يمكن المتابعة قبل تأكيد سلامة المريض...") in the scan screen's error
banner instead of either a permission error or a silent autofill — the
user's own explicit requirement, matching the same gate already blocking
payment and task-starting.

Verified via curl against the local dev server (mirrors the checks in
`README.md`'s matching entry): a doctor scanning a clear registration
gets the full record; scanning a not-yet-clear one gets the exact
screening-gate message instead of a permission error. `flutter analyze`
clean project-wide.

## Payments: filtering, QR scan + screening confirmation, quick-digit parity (2026-08-29)

See `README.md`'s matching entry for the full backend/web picture — this
is the Flutter-side half.

**`PaymentListScreen`** gained a filter icon (AppBar) opening a modal
bottom sheet — date-range pickers (`from`/`to`, on `paid_at`) + a source
dropdown (موعد|تسجيل مريض). `paymentListProvider`'s family key changed
from a bare `String? search` to a `PaymentFilters` record type
(`typedef PaymentFilters = ({String? search, String? from, String? to, String? source})`,
`records_providers.dart`) — a Dart `record` gets structural equality for
free, which is exactly what a Riverpod family key needs for the same
filters to hit cache; no separate class/`==`/`hashCode` needed. Only
call site was this screen, updated to build one instead of passing a
bare string.

**`PaymentFormScreen`** had no QR scanner at all before this — patient
linkage was a plain `PatientRegistrationListScreen(pickMode: true)`
picker, and a code comment on the seeded registration explicitly
documented "this manual-entry form doesn't gate on screening status
anyway (only the QR desk flow does)." Added:
- A new `QrScanMode.paymentPatientLink` (`qr_scan_screen.dart`) — same
  resolve-and-pop-back shape as `taskPatientLink`, reusing the plain
  `.scan()` repository method (this screen is staff-only, under
  `/records`, so the staff-gated `patient-registrations/scan` endpoint
  is the *correct* one here — unlike the case-sheet autofill scan two
  entries up, which needed a doctor-only endpoint precisely because its
  caller is a doctor).
- A "مسح رمز المريض" `IconButton.filledTonal` next to the registration
  picker, pushing `/records/patient-registrations/scan-for-payment` and
  awaiting a `RegistrationPaymentState`.
- One shared `_applyRegistration(PatientRegistration)` helper, called
  from both the scan result and the existing list-picker result: if
  `registration.isScreeningClear`, sets `_registration` as before; if
  not, sets a new `_blockedRegistration` instead (leaving `_registration`
  null, so the existing "يرجى اختيار المريض المسجل" submit-guard still
  fires) and renders a red "لا يمكن الدفع" banner naming the patient and
  why — the same wording `_ScreeningBlockedBanner` already uses on the
  reception-desk `PatientRegistrationPaymentScreen`, reused here as inline
  text rather than extracting a shared widget (small, two call sites,
  slightly different layout context in each).
- Quick "0"/"00"/"000"/"مسح" amount buttons (`_appendDigits()`/
  `_clearAmount()`), identical pattern to
  `PatientRegistrationPaymentScreen`'s own — this screen's amount field
  was a plain `TextFormField` before, the one place in the app missing
  this convenience.

Verified: `flutter analyze` clean on every touched file.

## PaymentFormScreen simplified: registration-only, auto date, no paid-by (2026-08-29)

Same-day follow-up, by request, after seeing the shipped screen live:
`PaymentFormScreen` no longer offers the "موعد" (appointment) source at
all — the "نوع المدفوعة" radio toggle and appointment picker
(`_pickAppointment()`, the `Appointment` domain import) are gone, and
the form always settles a reception-desk registration now. `_paidAt`
defaults to `DateTime.now()` at declaration and in `_seed()` (was `null`
→ "— اختر تاريخًا —") — still shown and editable via the same date
field, for backdating, just no longer blank by default. "دفع بواسطة"
(`_paidByController`) is removed entirely; the backend column stays
nullable and untouched, this form just never populates it anymore.

**A real correctness point, not just UI removal**: `update()` is a
partial update (`Api\PaymentController::validatePayment()`'s `sometimes`
rules) — if this form only ever sent `patient_registration_id` and
never touched `appointment_id`, editing a *pre-existing*
appointment-sourced payment would leave the DB's old `appointment_id`
in place while also setting `patient_registration_id`, landing on a row
with both FKs set at once and breaking the "never both" invariant the
rest of the app relies on (list source badges, the payments source
filter added earlier today). Fixed by always sending
`'appointment_id': null` explicitly in the payload. Confirmed this is
safe against Laravel's `prohibits`/`required_without` rules: both are
implemented to short-circuit to "not triggered" when the field's own
value fails `required` (which an explicit `null` does) — so sending
`null` clears the old FK without tripping `prohibits:patient_registration_id`
on itself. Editing a legacy appointment-sourced payment from this
screen now seeds an *empty* registration picker rather than showing its
appointment (`_seed()` no longer has an `appointmentId` branch); saving
such an edit re-points it at whichever registration gets picked — an
accepted trade-off for the simplification. Web `Payments/Create.vue`
still offers the appointment source unchanged, for that edge case.

Verified: `flutter analyze` clean project-wide.

## PaymentFormScreen: paid/screening feedback, date fully automatic (2026-08-29)

Same-day follow-up, by request, after a real double-payment attempt: the
screen never showed whether a scanned/picked patient had already paid,
or whether their screening was clear, until the submit either silently
succeeded twice or the server rejected it with no visible reason first.

Extracted `PatientRegistrationPaymentScreen`'s (the reception-desk flow)
`_ScreeningBlockedBanner`/`_PaidBanner` into a new shared
`core/widgets/registration_status_banners.dart`
(`ScreeningBlockedBanner`/`PaidBanner`, public) rather than writing a
second drifting copy of the red "not clear" banner
`PaymentFormScreen` already had inline from yesterday's change — that
inline copy is gone now too, replaced by the shared widget.
`PatientRegistrationPaymentScreen` itself now imports these instead of
defining them privately; no behavior change there.

New `RegistrationPaymentState? _paymentState` (alongside the existing
`_registration`) carries the full picked/scanned patient's payment +
screening state. Both resolution paths feed it: `_scanRegistration()`
already got a full `RegistrationPaymentState` from `scan()` and used to
discard everything but `.registration` — now kept. `_pickRegistration()`
only ever returned a bare `PatientRegistration` from the list-picker
(no payment/screening data at all) — now follows up with
`PatientRegistrationRepository.status(id)` so both paths show identical
feedback regardless of how the patient was found.

**Deliberately scoped to create only.** `_paymentState` is only
populated/consulted while `_isCreate` — editing an existing payment
never fetches or checks it. The payment being edited already happened;
gating an edit on *today's* paid/screening status would be wrong (every
existing payment would trip "already paid" against itself) and could
block fixing a typo in an old record. `_pickRegistration()`'s
`status()` follow-up call itself is skipped entirely in edit mode for
the same reason.

Once `_paymentState` is set: `PaidBanner` always shows first (green
"تم الدفع — إجمالي المدفوع: …" / amber "لم يتم الدفع" — this alone
answers "لم يظهر هل قام بالدفع"). Then one of three: `ScreeningBlockedBanner`
if not clear (blocks the amount section, matching the reception desk);
else, if already paid, a read-only list of existing payments instead of
an amount field at all (answers "اذا قام بالدفع سابقا لا يحتاج ان يدفع
مرة أخرى" — no way to even reach the submit button for a second
payment); else the normal amount entry + quick digits + submit, exactly
as before. `_submit()` also gained a belt-and-suspenders `if (_blocked
|| _alreadyPaid) return;` in case state goes stale between a render and
a tap — the UI already hides the button in both cases, so this should
be unreachable in practice.

`تاريخ الدفع` is gone from this screen entirely now, not just defaulted
— no field, no `_paidAt`, no `_pickPaidAt()`. `paid_at` is never sent on
create (the `payments` table's own `DEFAULT current_timestamp()` fills
it in) and never touched on update (the `sometimes` partial-update rule
leaves an edited payment's original date alone) — yesterday's "default
to today but still editable" middle ground turned out not to be what
was wanted; this is the fully-automatic version.

Verified: `flutter analyze` clean project-wide.

## Thermal ticket/receipt: full-width logo, settings-driven header, bordered info table (2026-08-29)

By request: the printed logo was tiny, the clinic/university header text
was hard-coded instead of pulled from settings, and the patient-info
lines were too small and not visually a "جدول" (table).

**Logo, full paper width.** `TicketWidget`/`TaskInstanceTicketWidget`
rendered their (already settings-sourced) logo at a fixed
`Image.memory(logoBytes!, width: 72, height: 72)` regardless of paper
width — ~19% of a 58mm ticket's 384 dots, ~12.5% of an 80mm one's 576.
Changed to `Image.memory(logoBytes!, width: widthDots)` — height
omitted so `Image` preserves the logo's own aspect ratio rather than
squashing it into a forced square. `ReceiptWidget` (the payment-desk
receipt) **had no logo at all before** — no parameter, no fetch at its
call site — added one, matching the other two widgets exactly.

**Header text now sourced from `ClinicSettings`.** All three widgets
printed a literal hard-coded string pair
(`'المستشفى التعليمي لكلية طب الأسنان'` / `'جامعة تكريت'`) regardless
of what was actually configured in "الإعدادات" — despite the *logo*
already being fetched from settings at two of the three call sites. New
`headerTitle`/`headerSubtitle` params on each widget, filled in by every
call site as `settings?.universityName ?? settings?.clinicName` /
`settings?.collegeName` — the exact same precedence
`print/layout.blade.php`'s web letterhead already uses for print
headers (`university_name ?: clinic_name` / `college_name`), now
finally shared with the thermal path instead of drifting from it. Null
or empty falls back to the original hard-coded strings *inside the
widget itself* (never blocks printing if settings fetch fails or
nothing's configured — same fail-open contract [logoBytes] already
had). `patient_registration_payment_screen.dart` gained an entirely new
settings+logo fetch block for this (mirroring
`patient_registration_form_screen.dart`'s existing one) since
`ReceiptWidget` never had one.

**Patient-info rows: real bordered table, bigger text.** `ticket_row.dart`'s
`ticketRow()` (a borderless `Row` of two `Text`s per line, stacked in a
`Column` — visually a list, not a table) replaced with `ticketTable()`
— a real `Table` with `TableBorder.all()` grid lines, taking a
`List<(String, String)>` of label/value pairs. Font size bumped
18 → 22 (`ticketRow()`'s only size) for readability, per request; the
value cell keeps its `TextOverflow.ellipsis` safety net, so a long
value truncates rather than overflowing the fixed ticket width. All
three widgets' sequences of `ticketRow(...)` calls became one
`ticketTable([...])` call each. Header title/subtitle font sizes
(24/16 on Ticket and TaskInstanceTicket, 20/14 on Receipt) left
unchanged — already the largest text on each ticket.

Verified: `flutter analyze` clean project-wide. Not verified on a real
printer in this session (no physical access) — the user will confirm on
next print after the next Codemagic build + AltStore reinstall, per
this project's standing pattern for Flutter-only changes.

## Task-progress PDF report: doctor name printed once per block, not repeated (2026-08-29)

`task_progress_pdf.dart`'s own doc comment already admitted the
trade-off: the `pdf` package has no native rowspan, so `_flattenRows()`
repeated the doctor's name on every one of their task rows instead of
blanking it after the first — "trading the visual merge for simplicity."
By request, after seeing a real exported report (68 rows, most doctors
have 5-7 task rows each, the name repeated on every single one):
`doctorName` is now only set on the first row of each doctor's block
(`i == 0 ? doctor.name : ''`), blank on the rest — the standard
faux-rowspan technique for a grouped table in a library with no real
cell-merging, and what the user actually wanted here. No web equivalent
exists to also fix — this report has no Blade counterpart, it's
generated client-side in Flutter only (the legacy `admin/task_progress_print.php`
was ported here, not to a web print view).

Verified: `flutter analyze` clean. Not re-verified against a real PDF
render in this session — the user will confirm on next export.

## Fixed: supervisor case-sheet preview couldn't scroll the tooth chart (2026-08-29)

Found live: previewing the Operative case sheet as a supervisor/admin
(readonly) showed the odontogram's arch rows visibly cropped at the
edges with no way to scroll to see the rest of the teeth. Root cause
was architectural, not specific to this one widget:
`_DentalChartFieldWidgetState`/`_EndodonticsFieldWidgetState` in
`dynamic_section_form.dart` disabled editing by wrapping
`ToothOdontogramField`/`EndodonticsField` in `IgnorePointer(ignoring:
readonly)` — `IgnorePointer` removes the *entire* subtree from hit
testing, which also disables any scroll gesture recognizer inside it,
not just tap-to-edit. Both widgets have an internal horizontal
`SingleChildScrollView` (the arch rows; `EndodonticsCanalTable`'s
10-canal table) that this silently broke for any readonly viewer.

Fixed by giving both widgets their own `readOnly` parameter instead,
reaching only the actual edit affordances — `ToothOdontogramField`'s
per-tooth `GestureDetector.onTap` (opens the editor sheet), and every
interactive control inside `EndodonticsField`/`EndodonticsCanalTable`
(the enable `Switch`, `TextFormField`s via `enabled: !readOnly`,
`ChoiceChip`/`FilterChip` via `onSelected: null`, `Checkbox` via
`onChanged: null`) — while their `SingleChildScrollView`s stay fully
interactive regardless. `dynamic_section_form.dart`'s two call sites no
longer use `IgnorePointer` at all, passing `readOnly:
widget.state.fieldDisabled(widget.field)` straight through instead.

Confirmed web's `ToothOdontogram.vue` never had this bug — it disables
individual `<button>` elements via `:disabled`, which never blocks a
parent's native scroll in HTML the way Flutter's `IgnorePointer` blocks
an entire subtree's gestures; no web-side change needed.

Verified: `flutter analyze` clean project-wide. Not re-verified against
a real device in this session — the user will confirm on next preview
after the next Codemagic build + AltStore reinstall.

## Real FDI quadrant tooth picker for `type: 'teeth'` fields (2026-08-29)

By request, referencing the original "dentalclinic" app's own
horizontally-scrollable tooth picker: `DynamicSectionForm` rendered
every `type: 'teeth'` field (Operative's "أسنان غير حيوية"/"أسنان
مفقودة"/"تيجان / جسور", and the same type used across Orthodontics,
Surgery, Prosthodontics, Complete Denture, and Oral Medicine's own
layouts — `grep`-confirmed across all 6 of those `App\Support\*Form.php`
files) as a plain comma-list text field the user had to type by hand
("UR8, UL1"), while web already had a real picker
(`Components/QuadrantTeeth.vue`) for the identical field type.

New `QuadrantTeethField` (`case_sheet_forms/presentation/quadrant_teeth_field.dart`)
ports `QuadrantTeeth.vue` directly rather than inventing a new design:
same quadrant order (`UR: 8→1, UL: 1→8, LR: 8→1, LL: 1→8`), same two
stacked rows (`[UR,UL]`/`[LR,LL]`) with a divider between each row's two
quadrant blocks, same comma-separated storage string (`"UR8, UL1"` —
not a JSON array, so a record saved here still loads identically in
the original PHP app), same tap-to-toggle interaction, wrapped in a
horizontal `SingleChildScrollView` so the full arch is reachable on a
narrow phone screen. `readOnly` disables only each tooth button's
`onTap` (`null` when read-only) rather than wrapping the whole picker
in `IgnorePointer` — the exact bug just fixed two entries up for the
odontogram/endodontics widgets, deliberately not repeated here.

Wired into `DynamicSectionForm`'s field-type switch as a new `case
'teeth':` branch (previously falling through to the generic text-field
`default:`), and removed from `_isTextControlled()`'s set since it no
longer needs a `TextEditingController`. `CaseSheetField.isSupported`
already listed `'teeth'` as supported — no domain-model change needed,
only the renderer was behind web.

Verified: `flutter analyze` clean project-wide. Not re-verified on a
real device in this session — the user will confirm on next preview
after the next Codemagic build + AltStore reinstall.

## Oral Medicine's Extraoral/Intraoral Examination: real head-diagram images + tap-to-mark drawings (2026-08-29)

By request ("استعادة الصور مع الرسومات الخاصة بها كما dentalclinic" —
restore the images with their own drawings, like in dentalclinic),
after the Oral Medicine Chart screenshot showed this section as one of
several "غير مدعوم في التطبيق بعد" (not supported yet) placeholders.
Of Oral Medicine's six JSON-blob composite field types, this is the one
that's genuinely about images-with-drawings (the other five —
history_complaint, pmh_checklist, surgical_history, family_history,
social_history — are checklist/text sections with no images, and stay
unsupported placeholders for now; not in scope for this request).

**New `HeadDiagramsBoard`** (`case_sheet_forms/presentation/head_diagrams_board.dart`)
ports `Components/HeadDiagramsBoard.vue` directly: the same four
reference images (frontal/posterior/right/left — the exact same JPEGs,
copied from `public/images/head-diagrams/` into
`flutter_app/assets/images/head_diagrams/` and registered in
`pubspec.yaml`, since these are static reference images, not
admin-uploaded/mutable data), tap-to-stamp a pain-quality symbol at the
tapped point (not freehand drawing — one point per tap, exactly like
the original), a pattern dropdown (mild/moderate/severe + 7 lettered
qualities) and a clear button per view. Storage shape is identical:
`{frontal: [{x,y,type}], posterior: [...], right: [...], left: [...]}`,
points in the image's *natural* pixel space so a chart saved at one
screen size still lines up at another.

The symbol-drawing logic (`drawPainPatternForHeadDiagram()`, ported via
the Vue component, not re-derived from the original PHP) is
pixel-for-pixel identical, translated from HTML `<canvas>` 2D context
calls to Flutter's `CustomPainter`/`Canvas`: `quadraticCurveTo` →
`quadraticBezierTo` (same control/end-point semantics, direct 1:1
translation), the same two-stage scale clamp (`scale = max(0.8,
minScale)`, then `lineWidth = max(1.2, 1.2*scale)` — two *independent*
clamps, not one, since `1.2 × 0.8 = 0.96 < 1.2`), same spacing/height
constants for the mild (|||||)/moderate (wavy MMM)/severe (/////)
patterns, same single-letter glyphs (B/D/N/P/S/T/R) for the
burning/dull/numbing/pressure/sharp/tingling/radiating qualities.
Coordinate mapping simplifies slightly versus the web version: an
`AspectRatio` ancestor sized to the image's own decoded
`width`/`height` guarantees the rendered canvas always preserves the
image's aspect ratio, so a single scale factor covers both x and y
(the web version computes them separately since a browser `<canvas>`
has no equivalent built-in aspect-lock).

**New `ExtraoralIntraoralExamField`** (`extraoral_intraoral_exam_field.dart`)
wraps `HeadDiagramsBoard` with the rest of the section web's
`ExtraoralIntraoralExam.vue` renders above it: a 7-muscle
tenderness grid (right/left text per muscle), four more right/left
pairs (TMJ clicking, preauricular pain, swelling, deviation on
opening), max mouth opening, facial defects, and oral mucosa condition
— same JSON keys as the web component (`muscles`, `tmj_clicking`,
`preauricular_pain`, `swelling`, `deviation_opening`,
`max_mouth_opening`, `facial_defects`, `oral_mucosa_condition`,
`head_diagrams`), so a record saved by either app loads correctly in
the other.

Wired into `DynamicSectionForm` as a new `case 'extraoral_exam':`
(previously fell through to the generic unsupported-placeholder path)
and added to `CaseSheetField.isSupported`. Needed one new submit-path
special case: unlike `endodontics_data` (which has a real Eloquent
`'array'` cast on `DentalChart`), `oral_medicine_charts.extraoral_intraoral_examination`
has no cast at all, so `buildSubmitPayload()` now `jsonEncode()`s this
one field's value specifically before sending it — every other
composite/grouped field already had its own correct serialization path,
this was a new gap `_coerce()`'s decode-on-load side already implied
but the encode-on-save side hadn't been written yet.

Verified: `flutter analyze` clean project-wide (including after `flutter
pub get` re-resolving the new asset entries). Not verified on a real
device in this session — the user will confirm on next preview after
the next Codemagic build + AltStore reinstall.

## Prosthodontics/Complete Denture: stage-evaluation table now renders on Flutter (2026-08-29)

By request ("diagnosis signature date grade خاص بالمدير او المشرف وهو
الوحيد الذي يحق له التعديل عليها" — diagnosis/signature/date/grade is
for the manager/supervisor only, and only they may edit it): the
9-row "Stages and evaluation" table (`diagnosis_instructor_signature`
plus a `stage_{key}_{signature,date,grade}` triple per stage —
Preliminary impression, Cast-Surveying, Final impression, … through
Final evaluation) is exactly where these fields live on Prosthodontics
and Complete Denture, and `CaseSheetFormSchema`'s own doc comment
already flagged it as parsed-but-never-rendered on Flutter. So the
permission model (`CaseSheetSupervisorFields::stageFields()`) already
correctly reserved every one of these cells for staff — but a
supervisor had no way to actually *reach* them on mobile, since the
table itself didn't exist there. `diagnosis_instructor_signature` itself
was never affected by this gap — it's a normal `sections()` field
(type `text`), already rendered and already gated correctly by the
existing generic `fieldDisabled()` mechanism.

New `_StageEvaluationTable`/`_StageRow`/`_StageDateField` in
`dynamic_section_form.dart` (not a new file — small enough, and tightly
coupled to `DynamicSectionFormState`'s internals the same way
`_SectionCard` already is) render a card per stage rather than porting
`SectionedForm.vue`'s wide HTML table verbatim — three columns of text
input don't fit a phone screen without cramming or forcing horizontal
scroll, and no other field in this form is table-shaped in a way that
would set a precedent to match instead. `_seed()`/`buildSubmitPayload()`
both gained a stage-row loop alongside the existing `sections()` loop,
since `CaseSheetFormSchema.stages` is a separate top-level list, not
part of `allFields`. New `stageFieldDisabled(stageKey, part)` mirrors
`fieldDisabled()` exactly, checking `supervisorEditableFields` for
`stage_{key}_{part}` — the same synthetic keys
`CaseSheetSupervisorFields::stageFields()` already emits, so a
supervisor previewing either sheet can now actually fill these in on
mobile, while a doctor's own view still shows them editable client-side
(matching this app's existing pattern everywhere else — server-side
`EnforceCaseSheetAccess` is the real enforcement, per-field
`readonly`/`fieldDisabled` only ever gates a *staff* viewer, never a
doctor's own record) but is rejected server-side on an actual attempt
to change one, exactly as it already was before this fix.

Verified: `flutter analyze` clean project-wide. Not verified on a real
device in this session — the user will confirm on next preview after
the next Codemagic build + AltStore reinstall.

## Supervisor-only fields were fully editable on a doctor's own case-sheet page (2026-08-29)

Corrects the entry immediately above, which explicitly (and, it turned
out, wrongly) accepted "a doctor's own view still shows them editable
client-side... but is rejected server-side on an actual attempt to
change one" as the intended behavior. A live screenshot of a doctor's
own Operative/Orthodontics/Oral Medicine sheet showed exactly that: every
`CaseSheetSupervisorFields`-registered field rendered as an ordinary,
fully-editable text box, indistinguishable from a field the doctor is
actually meant to fill in — reported as a bug, then clarified to the
real requirement: keep these fields **visible** (a doctor should be able
to read the supervisor's notes/grade/signature once given), just make
them **impossible to edit** from the doctor's own page.

**Root cause**: `fieldDisabled()`/`stageFieldDisabled()` only ever locked
a field *because of* `widget.readonly` (true only on the staff
supervisor-preview screen) — `widget.supervisorEditableFields` is always
`[]` for a doctor, so `readonly && !supervisorEditableFields.contains(key)`
evaluates to `false` for every field on a doctor's own edit screen,
supervisor-registered or not. There was no rule saying "this field is
off-limits to you regardless of your own read/write mode."

**Fix**: `CaseSheetFormSchema` gained a `supervisorFields` list — the
registry's full, *unconditional* set for the resource (`App\Support\
CaseSheetSupervisorFields::fieldsFor()`, now added to
`Api\CaseSheetFormController::show()`'s response), as opposed to
`supervisorEditableFields` (per-viewer, only ever non-empty for whoever
may currently edit them). `fieldDisabled()`/`stageFieldDisabled()` now
check `supervisorFields` first: a field in that list is locked unless
this viewer is the one allowed to edit it — independent of `readonly`.
Every other field's behavior is unchanged. See `dental_laravel/README.md`'s
matching entry (same date) for the full change across both web and API.

A doctor now sees the supervisor's notes/signature/grade the moment
they're filled in, rendered with the same disabled styling used
elsewhere in these forms, but can never type into them — a supervisor's
own preview is unaffected.

Verified: `flutter analyze` clean project-wide (no issues).

## Operative: treatment plan notes are also supervisor-only (2026-08-29)

Backend-only follow-up (`App\Support\CaseSheetSupervisorFields`) — no
Flutter code changed. `dental-charts`' `treatment_plan_notes` field
joined the registry's list for that resource, confirmed by the user from
a live screenshot as also being supervisor-only. Since the fix directly
above already made `DynamicSectionForm`'s `fieldDisabled()` check that
registry generically, this one extra entry is enough to lock the field
on the doctor's own page too, the moment the schema endpoint (fetched
live, no caching) reflects it — no Codemagic rebuild needed. See
`dental_laravel/README.md`'s matching entry for the full detail.

## Oral Medicine's remaining five JSON-blob composites now render on Flutter (2026-08-29)

By request, from a live screenshot showing "History of the Complaint",
"PMH. (Past Medical History)", "History of Surgical Operations or
Treatments", and "Family History" all still rendering as "غير مدعوم في
التطبيق بعد" (not yet supported) placeholders: Oral Medicine has six
JSON-blob composite field types in total (`App\Support\OralMedicineForm`);
only `extraoral_exam` had a real Flutter widget before this (see the
2026-08-29 entry above it), the other five were parsed by the schema but
had no renderer, so `_UnsupportedField` was all a doctor or supervisor
ever saw for them — meaning `history_of_complaint`, `past_medical_history`,
`surgical_history`, `family_history`, and `social_history` were
effectively unfillable from the mobile app.

Five new widgets, each a direct port of its matching web component —
read in full before building, not guessed, per this project's standing
rule:
- `HistoryOfComplaintField` (`history_complaint` type) — port of
  `Components/HistoryOfComplaintSection.vue` +
  `Components/SymptomsChecklist.vue`: the 28-item symptom checklist
  (`symptoms: string[]`, with a `hasSides`-flagged subset revealing a
  right/left detail pair and the special `other` item revealing free
  text — `symptom_details: {key: {right, left, other}}`), the six
  open-ended follow-up questions, and a 0–10 pain scale.
- `ValueDetailsChecklistField` (`pmh_checklist` type) — port of
  `Components/ValueDetailsChecklist.vue`: a generic "Yes/No + details if
  yes" grid (`{key: {value: 'yes'|'no', details: string}}` per item),
  driven by the field's own 14-category `options` list — a real gotcha
  here: PMH's `options` are `{key, label}` pairs, not the `{value,
  label}` shape `CaseSheetField.options` assumes for select/radio/
  checkboxes elsewhere, so the wrapper widget reads `field.raw['options']`
  directly instead of going through that getter.
- `SurgicalHistoryField` (`surgical_history` type) — port of
  `Components/SurgicalHistorySection.vue`: `extra_oral`/`intra_oral` are
  plain "yes"/"no" strings (confirmed against real imported data by the
  web component's own comment — not the value+details pattern PMH uses),
  plus three free-text fields.
- `FamilyHistoryField` (`family_history` type) — port of
  `Components/FamilyHistorySection.vue`: eight plain free-text fields,
  one per hereditary condition, no value/details toggle.
- `SocialHistoryField` (`social_history` type) — port of
  `Components/SocialHistorySection.vue`: marital status/tobacco use/
  alcohol/exercise (radio), two checkbox multi-select lists
  (`tobacco_other`, `caffeine`), and several free-text fields.

Wiring, mirroring exactly how `extraoral_exam` was added: `CaseSheetField.isSupported`
gained all five type names; `DynamicSectionForm._coerce()` gained
matching cases (all six of Oral Medicine's composites decode identically
— `_parseGroup(raw)` — since none of these columns carry an Eloquent
`'array'` cast, unlike `endodontics_data`); the ad hoc `field.type ==
'extraoral_exam'` check in `buildSubmitPayload()` was generalized into a
new `_jsonBlobFieldTypes` set (mirrors `SectionedForm.vue`'s identically
-named `JSON_BLOB_FIELD_TYPES` constant) covering all six, so every one
of them gets `jsonEncode()`d back to a string before reaching the API;
five new `case`s in `_FieldWidget`'s dispatch switch, each backed by a
small wrapper `StatefulWidget` (`_HistoryComplaintFieldWidget`, etc.)
following the exact `_ExtraoralExamFieldWidget` pattern — no `_FieldLabel`
(the section card's own title already labels it), reads/writes
`state._values[field.formKey]` as a `Map<String, dynamic>`.

Radio groups in the three new widgets that needed them use `RadioGroup`
(the current non-deprecated Flutter API — confirmed by first trying the
older direct `Radio.groupValue`/`onChanged` pair, which `flutter
analyze` flagged as deprecated, then matching the pattern the existing
`_RadioField` in this same file already uses) rather than reintroducing
the old pattern.

Verified: `flutter analyze` clean project-wide (no issues, including
after fixing the `RadioGroup` deprecation warnings and a `ValueChanged<T?>`
non-nullable-callback signature mismatch caught the same way — both
self-caught before shipping). Not verified on a real device in this
session — the user will confirm on next preview after the next
Codemagic build + AltStore reinstall.

## Orthodontics' last two unsupported field types now render on Flutter (2026-08-29)

By request, from live screenshots showing "Stages of treatment",
"Appliance type & Design", and "Number of teeth" still as "غير مدعوم في
التطبيق بعد" placeholders — these were the only two remaining unhandled
`App\Support\OrthodonticsForm` types (`teeth_squares_grid`,
`quadrant_repeater`) after every one of Oral Medicine's composites was
covered earlier today.

- **`TeethSquaresGridField`** (`teeth_squares_grid`) — port of
  `Components/TeethSquaresGrid.vue`: a 4-row × 16-column marking grid
  (Unerupted/Erupted/Erupted/Unerupted, header 8→1 then 1→8), each cell
  tappable to open a bottom-sheet picker offering Primary teeth A–E,
  Permanent teeth 1–8, the "/" (Extracted) mark, or Clear. `value` is
  `{ [square_id]: mark }`, `square_id = '${row_type}_${col}'`, matching
  the web component's keys exactly. Wrapped in a horizontal
  `SingleChildScrollView` inside a fixed LTR `Directionality` — the
  header's anatomical 8→1→1→8 reading order must not flip under the
  app's Arabic (RTL) locale, same reasoning as `QuadrantTeethField`.
- **`QuadrantRepeaterField`** (`quadrant_repeater`) — port of
  `Components/QuadrantRepeater.vue`: repeating "info + quadrant tooth
  picker" rows (`{index: {info, quadrants}}`, 1-based), used for both
  "Stages of treatment" and "Appliance type & Design" (same shape,
  different `itemLabel`/`infoLabel`). Reuses the existing
  `QuadrantTeethField` per row for the tooth picker rather than a second
  fdi-cross implementation — the two already share the exact same
  comma-separated-code value shape.

Both are **grouped subkeys** inside `examination_data`, not top-level
JSON-blob columns — unlike Oral Medicine's six composites (which each
needed their own `jsonEncode`/`_jsonBlobFieldTypes` entry),
`_coerce()`'s new cases just normalize `raw` to a `Map` and let the
*existing* group-reassembly in `buildSubmitPayload()` re-encode the
whole `examination_data` blob as it already does for every other
grouped field — no submit-path change needed at all.

This lands the same day `diagnosis`/`treatment_plan`/`treatment_stages`/
`appliance_designs` were registered supervisor-only (see
`dental_laravel/README.md`'s matching entry) — until these two widgets
existed, a supervisor previewing an Orthodontics record on Flutter had
no way to actually *edit* Stages of treatment/Appliance type & Design
even though the permission model now reserves them for exactly that
role; they'd only ever seen the frozen "not supported" placeholder,
same gap the Prosthodontics/Complete Denture stage table had before it
was built.

Verified: `flutter analyze` clean project-wide (no issues). Not
verified on a real device — the user will confirm on next preview after
the next Codemagic build + AltStore reinstall.

## QuadrantRepeaterField: renumber rows after removal, fix stale controller text (2026-08-29)

Follow-up to the entry above, by request to match the original app's
"dynamic teeth numbering" — researched `orthodontics.php`'s actual JS
first: the FDI grid itself was already right, "dynamic" means the
original renumbers `treatment_stage_N`/`appliance_design_N` rows
sequentially after a removal (`renumberTreatmentStages()`/
`renumberApplianceDesigns()`), which `QuadrantRepeaterField._removeRow()`
didn't do — it just deleted the given key, leaving a gap, so every row
past it kept its *old* "Stage N" label instead of its new position.

Fixed to filter the removed key and reassign the remaining rows to
fresh sequential indices (1..N), mirroring the identical fix in the web
`QuadrantRepeater.vue`. Needed one more Flutter-specific fix Vue
doesn't: this widget keeps a `TextEditingController` per row keyed by
position (`info_$i`), which — unlike Vue's fully-reactive `:value`
binding — persists independently of the data once created. After
renumbering, a given controller key can now belong to a *different*
row's data, which would otherwise render that key's stale cached text
instead of the row's real (shifted) value. Fixed by disposing every
controller and clearing the map on removal, so `_controllerFor`
recreates them fresh from the renumbered data on the next build.

Verified: `flutter analyze` clean project-wide (no issues).

## Password reset: OTP dialog replaces the "check your email for a link" hand-off (2026-08-29)

Backend replaced the emailed reset *link* with a 5-minute one-time code
across both account types — see `dental_laravel/README.md`'s matching
entry for the full "two reported vulnerabilities investigated, one real
UI issue fixed, neither was actually exploitable" writeup and the new
`App\Services\OtpPasswordResetBroker`/`Api\PasswordResetController::reset()`.

This is the one surface where the change is more than a background
permission/schema tweak, since the *old* flow never had a native
completion step at all: `AuthRepository.sendPasswordResetLink()` only
ever sent the email and told the user to open it in a browser, landing
on the *web* reset-password page — there was nothing else for Flutter to
do. A typed code has nowhere else to go, so this needed a real in-app
completion screen for the first time.

- `AuthRepository.sendPasswordResetLink()` renamed to
  `sendPasswordResetCode()` (same endpoint, `POST /forgot-password` —
  only what it emails changed) plus a new `resetPasswordWithOtp({email,
  otp, password, passwordConfirmation})` hitting the new
  `POST /reset-password`.
- `LoginScreen._showForgotPasswordDialog()` rebuilt as a 2-step dialog
  instead of the old single "enter email" step: step 1 requests the
  code; on success the *same* dialog swaps its content (via the
  existing `StatefulBuilder`'s `step` flag, no new route/screen needed)
  to a code + new-password + confirm-password form, submitting to
  `resetPasswordWithOtp()`. A wrong/expired code surfaces via the
  existing `ApiException`/`.userMessage` plumbing, same as every other
  form error in this app.

Verified: `flutter analyze` clean project-wide (no issues). Not
verified against a real mailbox/device in this session.

## New `'signature'` field type: auto-captured, no more free-typed names (2026-08-30)

See `dental_laravel/README.md`'s matching entry for the full backend
design (`App\Support\CaseSheetSignatures`, the exact per-resource field
list, and the new `all_signed` Task Progress hint). On this side: every
case-sheet "*_signature" field across all 8 resources is now `type:
'signature'` instead of `'text'` — added to `CaseSheetField.isSupported`
(`case_sheet_field.dart`) and rendered by two new widgets in
`dynamic_section_form.dart`:

- `_SignatureField` — the scalar-field case (`senior_signature`,
  `supervisor_signature`, `senior_name`, `staff_signature`,
  `diagnosis_instructor_signature`), wired into `_FieldWidget`'s switch.
- `_StageSignatureField` — the same behavior for the "Stages and
  evaluation" table's 9 `stage_{key}_signature` cells (Prosthodontics/
  Complete Denture), replacing the plain `TextFormField` that column used
  to be.

Both show a "توقيع" `OutlinedButton` when empty, a pending
"سيُسجَّل التوقيع باسمك عند الحفظ"/"عند الحفظ" state with an إلغاء/×
undo once tapped (nothing is sent until the form is actually submitted —
the client only ever writes the sentinel string into `_values`, never a
real name), or the server-stamped read-only text once signed. No change
needed to `buildSubmitPayload()`/`_coerce()`: a signature field's value
is a plain string exactly like `'text'`, so it already flows through
both the flat and grouped-subkey paths unmodified.

Verified: `flutter analyze` on `case_sheet_field.dart` and
`dynamic_section_form.dart` (no issues).

## The `all_signed` badge, now also on the Flutter Task Progress screen (2026-08-30)

Follow-up the same day: a live screenshot of a Prosthodontics record with
all 10 signatures filled in showed no hint on the Flutter Task Progress
screen — this session's earlier entry above explicitly noted that gap
("UI-only, not a missing endpoint," since `TaskProgressGroupSummary`
already backs both web and API). Closed it:

- `TaskSlotCard.allSigned` (`task_progress_group.dart`) — new `bool`
  field reading the `all_signed` key `TaskProgressGroupSummary` already
  puts in every task-instance card's JSON (`dental_laravel/README.md`'s
  matching entry), defaulting `false` for older cached responses.
- `task_progress_screen.dart`'s `_TaskCard` — a green "✓ كل التواقيع
  جاهزة" pill next to the status chip when `card.allSigned &&
  card.status == 'assigned'`, and the existing "تأشير كمكتملة"
  `TextButton` gets a green-tinted style in that same state — mirrors
  `TaskProgress/Index.vue`'s web badge/button-highlight exactly. Purely
  a visibility hint: `_completeTask()` is completely unchanged, so
  nothing here auto-completes anything.

Verified: `flutter analyze` on both touched files (no issues). Not
verified against a real device in this session — the user will confirm
on next preview after the next Codemagic build + AltStore reinstall.

## A stage can't be signed off until its own Grade and Date are filled in (2026-08-30)

See `dental_laravel/README.md`'s matching entry for the full backend
enforcement (`CaseSheetSignatures::requirementsMet()`) — this is the
Flutter half. `_StageSignatureField`'s "توقيع" button is now disabled
(with an "أكمل الدرجة والتاريخ أولاً" hint underneath) until both
`stage_{key}_grade` and `stage_{key}_date` have values.

The one real wrinkle: `_StageRow` was a `StatelessWidget`, and neither
sibling ever notified it of a change — the grade `TextFormField`'s
`onChanged` wrote straight into `state._values` with no `setState()` at
all, and the date picker's `setState()` only rebuilt `_StageDateField`
itself. `_StageSignatureField` would have kept reading stale grade/date
values indefinitely. Converted `_StageRow` to a `StatefulWidget`; the
grade field's `onChanged` and a new `_StageDateField.onChanged` callback
(invoked after its own `setState()`) both now call the row's own
`setState(() {})`, so `_StageSignatureField` re-evaluates readiness on
every keystroke/date pick, same as the web's reactive `form[...]` check.

Verified: `flutter analyze` on `dynamic_section_form.dart` (no issues).
Not verified on a real device — next Codemagic build + AltStore
reinstall.

## Permissions admin: access-scope restriction (2026-08-30)

Closes the gap the Permissions admin entry above (2026-08-21) left open
on purpose: `Api\UserPermissionController` gained `scope_options`/`scope`
in `show()` and a `scope` field in `update()` (see
`dental_laravel/README.md`'s matching entry for the backend half, which
mirrors the web `Permissions/Edit` page's `edit()`/`update()` exactly).
This is the Flutter side consuming that new surface.

- `PermissionScopeOptions`/`PermissionScope` (domain) decode the new
  `scope_options`/`scope` response keys — a `null` list on any of the
  four dimensions means unrestricted (`ScopeHelper`'s own "zero rows"
  convention), not "nothing selected". A separate mutable
  `PermissionScopeSelection` (always non-null lists, `[]` = unrestricted)
  holds the edit screen's live form state — checkbox widgets need a
  concrete list to test membership against either way, so the null/empty
  distinction only has to survive the initial decode, not the whole
  widget tree.
- `PermissionsAdminRepository.update()` now takes a
  `PermissionScopeSelection` alongside `grants` and always sends all four
  scope keys as arrays (never omitted) — matches the web form's own
  `useForm` shape, and an empty array resolves to unrestricted
  server-side regardless, so there's no need to distinguish "omit the
  key" from "send `[]`" at this layer either.
- `PermissionEditScreen` gets four new `_ScopeDimensionTile`s (أقسام/
  مراحل/أنواع تعليم/أعوام دراسية) above the existing module list, same
  `ExpansionTile`-per-dimension shape as the module tiles below them for
  visual consistency: collapsed subtitle reads "بلا قيد — يرى الكل" when
  empty or "مقيّد بـ N" with a "إزالة القيد" clear action when not,
  mirroring the web page's per-dimension card exactly (dashed "بلا قيد"
  box, `الأقسام`/`المراحل`/`أنواع التعليم`/`الأعوام الدراسية` labels,
  same clear-restriction affordance) rather than the web's uniform
  2/4-column checkbox grid, which doesn't fit a phone any better than the
  module matrix did.

Verified live end-to-end via `flutter run -d chrome` (this session
started XAMPP's Apache + MySQL first — neither was running), logged in
as a throwaway `qa_scope_test` admin account created via `tinker` for
this: opened user 27 (`طبيب ahmed`, confirmed unrestricted on all four
dimensions beforehand via a `curl` baseline), expanded الأقسام, checked
`operative` + `operative dent`, saved — the tile's subtitle switched to
"مقيّد بـ 2" and `user_allowed_departments` gained exactly those two rows
(confirmed via `tinker`, not just the refetched UI state). Clicked
"إزالة القيد", saved again — subtitle back to "بلا قيد — يرى الكل" and
the pivot table back to zero rows, confirming the clear path round-trips
through the API correctly too, not just the local widget state. Test
user and its Sanctum token deleted afterward via `tinker`; user 27 left
exactly as found (unrestricted). `flutter analyze` clean on the whole
project throughout.

## Case-sheet printing (2026-08-30)

Closes a real gap: `Api\CaseSheetPrintController` (the JSON mirror of the
web's printable case sheets — see `dental_laravel/README.md`'s matching
entry) has existed since the web print feature was built, but nothing in
`flutter_app/` ever called it — a repo-wide grep for `"case-sheet-prints"`
found zero matches before this pass. So this was purely client-side work:
no new backend endpoint, just wiring one up.

- **`CaseSheetRecordRepository.fetchPrintDocument()`** — the one new
  repository method, hitting `GET /case-sheet-prints/{resource}/{id}`.
  Unlike every other method on that repository, the response has no
  `{data: ...}` envelope (that controller returns the document fields at
  the top level), so it's a plain pass-through rather than an unwrap.
- **`case_sheet_print_pdf.dart`** — walks that JSON into a real `pw.Document`
  the same way `task_progress_pdf.dart` already does for the task-progress
  report: `PdfLetterhead` for the header, then the identification strip,
  sections (label/value cells, two-per-row or full-width for
  narratives/tooth pickers — one small `pw.Table` per row rather than one
  table per section, since the `pdf` package's `Table` has no colspan to
  mix row shapes), periodontal per-tooth grids (16 tooth columns, 3 sites
  packed per cell, same tiny font the web's own `.perio-table` needs to
  fit them), the odontogram, stages, footer signature strip, and — when
  the sheet belongs to a task instance — the same QR back-link the web
  sheet prints, fetched via the existing `/task-instances/{id}/qr` PNG
  endpoint already used for the "رمز الحالة" button on this same screen.
- **`kCaseSheetPrintableResources`** — a new constant mirroring
  `App\Support\CaseSheetPrint::SHEETS`'s 8 keys, kept deliberately separate
  from the existing `kCaseSheetCreatableResources` even though the two
  sets are identical today: one tracks "can create," the other "has a
  print layout," and nothing keeps them in lockstep going forward.
- **`case_sheet_form_screen.dart`** gets a "طباعة" `IconButton` in its
  `AppBar`, gated by `!isCreate && kCaseSheetPrintableResources.contains(resource)`
  — mirrors the web's `SectionedForm.vue` print link exactly (`isEdit &&
  printable`). `Printing.layoutPdf(...)` hands the generated bytes to the
  platform's native print/share sheet.
- **One small backend addition alongside this** — `dental_laravel/README.md`'s
  matching entry covers it: the JSON endpoint gained `dental_chart`,
  `student_name`, and `grade_group`, which the web controller's Blade
  printout has always had but the JSON mirror never returned until a
  client actually needed to render them.

Verified live: fetched the print document directly via `curl` first to
confirm the JSON shape (a real `surgeries` record) before writing the PDF
builder against it. Then end-to-end through the actual Flutter web app
(`flutter run -d chrome`, doctor login) — pressed "طباعة" on that same
record, confirmed via the browser's own network log that
`/case-sheet-prints/surgeries/109` was called, the two Tajawal font files
loaded, and a `blob:` PDF was produced with no console errors; pulled the
blob's bytes back out via `javascript_tool` and confirmed a genuine
`%PDF-1.5` file (not an empty/broken one). Stopped short of visually
inspecting the rendered page layout — the sandboxed browser used for this
session blocks native print-dialog rendering the same way it blocks
camera access, so that last visual check is left for the next real-device
Codemagic build. `flutter analyze` clean on the whole project throughout;
the doctor test account's temporary password and Sanctum token were
cleaned up afterward.
