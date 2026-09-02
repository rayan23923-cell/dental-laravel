# Flutter App: Architecture & Navigation

This is the companion Flutter app doctors and staff use on phones/tablets
(Android, iOS, Windows desktop), talking to the same Laravel API the
Inertia/Vue web admin app uses. This doc covers the app's own high-level
design and its navigation/dashboard/notification UI. For backend-side
detail see the main `README.md`; for other Flutter feature areas (case
sheets, printing, task progress, etc.) see the rest of `flutter_app/README.md`
history or their own docs.

## Overview & architecture

**Who it's for** — two personas, treated differently rather than porting
every admin screen 1:1:
- **Doctor** (dental student) — the primary mobile user: task list, case
  sheets, QR check-in, viewing progress. A genuinely mobile workflow
  (walking between clinic chairs, scanning a patient's QR).
- **Staff/Admin** — manages doctors, groups, permissions, clinic settings,
  backups. A desk-bound, data-entry-heavy workflow already well served by
  the web app; treated as lower-priority, Phase 3 work since the API for
  it already exists.

**Package layout** (`flutter_app/lib/`):
```
lib/
  main.dart
  app.dart                      # MaterialApp.router + ProviderScope
  core/
    network/api_client.dart     # Dio: base URL, bearer token interceptor, 401 handler
    storage/token_storage.dart  # flutter_secure_storage wrapper
    router/app_router.dart      # go_router: route table, auth guard redirect
    theme/app_theme.dart        # fixed Instagram-style light+dark theme
  features/
    auth/ tasks/ task_instances/ case_sheets/ patients/ doctors/
    appointments/ payments/ qr/ clinic_settings/ backup/ tv_board/
  l10n/                         # Arabic (primary) + English
```
Each feature: `data/` (repository calling `ApiClient`), `domain/` (plain
Dart models, hand-written `fromJson`/`toJson` matching the API Resources'
field names — no `freezed`/build_runner, deliberately, since model shapes
are stable and hand-written models are one less build step for a team new
to Flutter), `presentation/` (Riverpod providers + screens/widgets).

**Stack choices** (each justified against an alternative, not default-picked):

| Package | Role | Why |
|---|---|---|
| `dio` | HTTP | Interceptors for bearer token + centralized 401→logout |
| `flutter_riverpod` | State | Compile-safe provider graph, testable without `BuildContext` |
| `go_router` | Routing | Declarative routes + deep links (QR scan → land on that task instance) |
| `flutter_secure_storage` | Token persistence | Keychain/Keystore-backed, not plain SharedPreferences |
| `mobile_scanner` | QR scanning | CameraX-based; mirrors the web app's own QR check-in |
| `cached_network_image` | Images | Doctor photos, logos — avoids re-fetch on rebuild |
| `image_picker` | Uploads | Profile photos, matches web upload fields |

**Auth** — this was originally planned as two separate login endpoints
picked via a "طالب / موظف" segmented toggle; that was superseded before
launch by a unified login, matching the web app's own unified `/login`
form (see `docs/auth-and-public-pages.md`). As actually built: one
`LoginScreen` with a single identifier field (username or email) and a
password field, both posted to the one `POST /api/v1/login`
(`Api\AuthController::login()`), which tries a staff match first, then a
doctor match, and returns `account_type` in the response so the client
knows whether it got back a `UserResource` or `DoctorResource` shape —
`AuthAccount` (sealed class, `StaffAccount`/`DoctorAccount` variants) reads
that field rather than the client having chosen the endpoint itself.
`device_name` (a real device identifier) lets a user hold multiple named
Sanctum tokens. Token stored via `flutter_secure_storage`; a `Dio`
interceptor attaches `Authorization: Bearer <token>` to every request and
redirects to `/login` on a `401`.

**API surface** — grounded directly in `routes/api.php`; every route
reachable behind `auth:sanctum` except login and the public TV board.
Covers: auth, task instances (own work, QR), tasks catalogue, case-sheet
prints + the 12 specialty tables, dental charts, patients, appointments,
payments, lookups (education types/stages/departments), academic sessions,
case sheet types, groups, doctors, clinic settings, backup, activity log,
permissions, and a public unauthenticated TV board endpoint.

**Localization & RTL** — Arabic primary throughout ("تسجيل الدخول",
"مهامي", etc.), English secondary. `flutter_localizations` + `intl` are in
`pubspec.yaml`; `MaterialApp.router` sets `locale: Locale('ar')` and
Flutter's built-in RTL handling drives directionality for Material widgets
automatically.

**Explicitly not planned**: freehand canvas drawing (pain-diagram strokes,
drawn signatures) and offline-first sync — both out of scope on the web
side too, no reason to build mobile-first.

## Build phases

| Phase | Scope |
|---|---|
| **1 — Doctor core (read-first)** | Both login types, secure token storage, auto-logout on 401; fixed light+dark theme; "My tasks" list with status filters; task detail + QR (display own, scan another); read-only case-sheet viewing; profile screen with photo upload |
| **2 — Doctor editing** | Case-sheet form schema endpoint; `DynamicSectionForm` + field-type widgets (text/select/radio/checkbox first, then teeth-picker and JSON-blob composites); dental chart (odontogram) as a custom tap-to-mark widget; create-new for case sheets; patients/appointments/payments CRUD |
| **3 — Admin (optional on mobile, API already exists)** | Doctors/groups/academic sessions/case-sheet-types management; permissions matrix (flagged as possibly staying web-only — awkward on a phone); clinic settings edit, backup trigger, activity log |

A large running "done vs. next action" checklist (original §9) tracked
progress against this phase plan item-by-item; it's superseded by this
summary and by the dated feature entries below, so it isn't reproduced here.

## Installable builds

**Windows `.msix`** — branded with the clinic's circular medallion logo
(`assets/branding/app_logo.png`), applied via `flutter_launcher_icons`
(Windows-scoped) to regenerate `windows/runner/resources/app_icon.ico`,
plus real branding in `windows/runner/main.cpp` (window title) and
`Runner.rc` (version-info strings). Built with the `msix` package (no
Inno Setup/NSIS needed — `makeappx.exe`/`signtool.exe` ship with the
installed Visual Studio 2022's Windows 10 SDK). No `certificate_path`
configured, so it self-signs with an auto-generated test cert — installable
via sideload-trust, not Store-ready. Build: `flutter build windows --release`
→ `dart run msix:create` → a 23.3 MB `.msix`. A new animated splash screen
(`features/auth/presentation/splash_screen.dart`) was built alongside this:
`AnimationController`-driven logo entrance, rotating gold sweep-gradient
ring, breathing glow, on a navy gradient matching the logo's own palette
rather than the in-app Instagram theme.

**Android release APK** — two real release-only bugs found and fixed:
1. **Missing `INTERNET` permission in release builds** — the Flutter
   template only grants it via `src/debug/AndroidManifest.xml` and
   `src/profile/...` (for hot-reload), never `src/main/AndroidManifest.xml`.
   A release build would have had zero network access. Fixed by adding
   the permission to the main manifest unconditionally.
2. **`network_security_config.xml`** only allowlisted the emulator's
   `10.0.2.2` loopback; with `targetSdkVersion` 36, cleartext HTTP to any
   other host is blocked regardless of the device's own Android version.
   Fixed by adding the dev machine's real LAN IP as a second
   cleartext-permitted domain.

Built with `flutter build apk --release --split-per-abi` (universal APK
was 70.8 MB, over a delivery limit). Verified live on real Android 8.1
(API 27) hardware — but on `armeabi-v7a`, not the `arm64-v8a` build
initially assumed for an 8.1-era phone (caught by checking
`adb shell getprop ro.product.cpu.abi` against the actual device rather
than assuming). Both staff and doctor logins verified end-to-end on-device
with `adb logcat` clean throughout.

**Android app icon + rename (2026-08-25)** — the Android build was still
shipping Flutter's default icon. Wired the clinic logo into
`flutter_launcher_icons` for Android too (`android: true` + `image_path`),
after flood-filling its white background transparent with ImageMagick and
using a corrected logo (fixed a missing hamza in the Arabic name). No
adaptive-icon foreground/background configured — plain legacy icons.
`AndroidManifest.xml`'s `android:label` changed from `dental_clinic_app`
to `CDC`; the Dart package name and `applicationId` were deliberately left
untouched as bigger, riskier changes than asked.

## Navigation: the ChatGPT-style sidebar

Before 2026-09-01 the app had no persistent navigation: all ~43 screens
built independent `Scaffold`s, and users navigated an ad-hoc hub-and-spoke
chain (`HomeScreen` → `AdminHubScreen`/`RecordsHubScreen`/
`CaseSheetTypesScreen` → leaf screens). By request ("سايد بار مشابه لواجهة
chatgbt... واعتد ألوان انستجرام"), this was replaced with a permanent left
sidebar (slide-in overlay on narrow screens) with account-type-aware nav
items and a pinned bottom profile/settings/logout area.

**Instagram gradient, finally used** — `InstagramColors.gradient` had
existed in the theme since day one but had zero usages anywhere before
this. Promoted into exactly three small, accent-only spots (matching the
web app's own restrained usage): the sidebar header's logo badge, a 3-4px
bar marking the selected nav item, and a thin "story ring" around the
pinned profile card's avatar.

**New files**:
- `core/router/nav_destinations.dart` — `NavDestination` /
  `navDestinationsFor(AccountType, {required unreadNotifications})`. Doctor
  gets: الرئيسية، النماذج السريرية، مسح QR، رموز المهام المعلقة، الإشعارات.
  Staff gets: الرئيسية، السجلات، الإدارة، الإشعارات.
- `core/widgets/app_sidebar.dart` — header badge, nav list (selection = current
  route prefix matched against `GoRouterState.matchedLocation`), pinned
  profile row, a settings row (staff only — doctors have no admin settings),
  and a logout row that now asks for confirmation via `AlertDialog` before
  logging out (previously an instant-fire button).
- `core/widgets/settings_menu_sheet.dart` — a bottom sheet deep-linking the
  same 5 items already grouped under `AdminHubScreen`'s "الإعدادات" heading.
- `core/widgets/app_shell.dart` — the responsive composition. Deliberately
  **not** a `Scaffold`: a plain `Row`/`Stack` inside `SafeArea`, so every
  routed screen keeps its own existing `Scaffold`/`AppBar` untouched (this
  is what kept the retrofit low-touch). `≥900px`: permanent 280px sidebar +
  `VerticalDivider` + content. `<900px`: sidebar collapses to a top-leading
  circular menu toggle (not bottom, to avoid colliding with existing
  bottom-end FABs).

**Router integration** — hub/list/settings routes wrapped in one plain
`ShellRoute` (not `StatefulShellRoute.indexedStack`, which is built for a
small fixed tab set — disproportionate for ~55 routes with normal
top-level nav semantics). Forms/leaf/full-bleed screens (`*/new`, `*/:id`,
`/profile`, `/scan`, `/tasks/:id`) stay outside the shell, full-screen.
A real ordering hazard was preserved on purpose: `/case-sheets/scan-patient`
must resolve before `/case-sheets/:resource` can swallow it as a dynamic
segment (a previously-fixed bug); the split now puts these routes on
opposite sides of the shell boundary, so all "outside" routes stay declared
before the `ShellRoute` node.

### Drag-to-reveal push drawer (narrow screens)

The first cut was a tap-only overlay (toggle → panel slides over a dimmed,
static screen). By further request, rebuilt to match ChatGPT/Claude's own
mobile behavior: the sidebar sits *behind* the content, and dragging the
content from anywhere on screen slides it aside in real time, revealing
the sidebar underneath.

**Mechanics** — a plain `AnimationController` (0 = closed, 1 = open),
driven two ways: manually during a drag (`onHorizontalDragUpdate` adds
`primaryDelta / sidebarWidth` directly onto `controller.value`, tracking
the finger exactly rather than an eased follow), and via `animateTo(0|1)`
on drag release (snapping based on whichever is closer, or a fling past
300px/s) or on tapping the toggle. This is the same technique Flutter's
built-in `Drawer` uses internally, exposed manually here since
`Scaffold.drawer` isn't available without a shared `Scaffold`.

**RTL-aware, for both drag and layout** — the app is Arabic/RTL and the
sidebar sits at the trailing (visually right) edge. A drag distinguishes
open vs. close by *direction*, not magnitude: `Directionality.of(context)`
flips the sign of `primaryDelta`/fling velocity, so dragging
right-to-left (the natural RTL "reveal what's behind me" gesture) opens
it, matching an LTR app's left-to-right convention.

**Full screen height** — the sidebar `Positioned` spans `top: 0, bottom: 0`
directly, ignoring the outer `SafeArea`, with its own internal `SafeArea`
wrapping just `AppSidebar` so header/nav still clear the status bar/notch
without shrinking the panel's edge-to-edge background.

**Layout bug found by pixel inspection, not code review** — the first pass
wrapped the pushed content in a bare `Transform.translate(child: Stack(...))`;
live testing showed the routed screen rendering at a fraction of real
screen width. Root cause: `Transform`'s non-positioned child inside the
outer `Stack` only receives loose constraints and passes them through
unchanged, so nothing downstream was told to fill the available space.
Fixed by wrapping the inner `Stack` in `SizedBox.expand()`. Caught by
capturing actual `<canvas>` pixels directly (`canvas.toDataURL`) rather
than trusting the browser-automation tool's own screenshot action, which
was independently confirmed to produce corrupted/partial captures for this
canvas-rendered content throughout the session.

### Real bugs found on a real iPhone

Three follow-up fixes, all found via real-device screenshots after the web-based
`flutter run -d web-server` testing (which has no status bar/notch and
`MediaQuery.paddingOf(context).top == 0`) missed them entirely:

- **Menu toggle overlapping the status bar/notch** — the toggle button was
  `Positioned(top: 8, ...)` inside the pushed-content `Stack`, which sits
  *outside* the `SafeArea` that only wraps `widget.child`. A bare `top: 8`
  is measured from the physical top of the screen. Fixed with
  `MediaQuery.paddingOf(context).top` added to the offset:
  `top: topInset + 8`, instead of a second nested `SafeArea` (which would
  need extra `left`/`right`/`bottom: false` flags to avoid double-insetting).
- **Faint shadow line bleeding through at the sidebar's closed edge** — the
  sidebar's `Material(elevation: 4, ...)` used a constant elevation
  regardless of the drag animation's `t` value (0 closed, 1 open), so
  Flutter still computed/painted a drop shadow even fully closed and
  covered by content. Fixed by scaling elevation with `t`:
  `elevation: 4 * t` — at `t = 0` there's no shadow computed at all.
- **Missing iOS permission strings** — `Info.plist` had only
  `NSCameraUsageDescription` (for QR scanning); every other
  permission-gated feature added since was silently refused by iOS with no
  prompt at all. Added `NSPhotoLibraryUsageDescription` (fixed profile
  photo upload outright). Added `NFCReaderUsageDescription` +
  `Runner.entitlements` for NFC doctor-tag reading, but this will likely
  still fail: CoreNFC's entitlement is stripped during signing for a
  free/personal-team Apple signature (what the AltStore/AltServer sideload
  setup uses) — needs a paid Apple Developer account. Bluetooth printer
  scanning has no iOS implementation at all — the `MethodChannel`
  (`com.dentalclinic.dental_clinic_app/pos_printer`) is backed only by
  `PosPrinterPlugin.kt` (Android); permission strings were added but there
  is no native Swift/CoreBluetooth counterpart, flagged as a real
  native-development task rather than attempted blind.

### Two crashes on the new pending-tasks-QR screen

Two follow-on crash fixes for `"رموز المهام المعلقة"` (see next section):

1. **Staff account crash** — `PendingTaskFinder::forDoctor()` is typed
   `Doctor $doctor`, but `Api\PendingTaskQrController::index()` passed
   `$request->user()` straight through with no type check; a staff
   session (`User`, not `Doctor`) reaching the endpoint threw a raw
   `TypeError` → an uncaught 500 → Flutter's `ApiException` mapping fell
   through to a generic `UnknownApiException`. The Flutter sidebar never
   *offers* this destination to staff, but the route itself had no
   server-side guard. Fixed with the same `abort_unless($doctor instanceof
   Doctor, 403, ...)` pattern already used in `TaskProgressController::mine()`.
2. **Graded-task crash** — even after the 403 fix, a real doctor account
   with a graded task still crashed. `Task.grade` is cast `decimal:2`
   server-side, so Laravel serializes it as a JSON **string** (e.g.
   `"85.50"`), but `PendingTask.fromJson` parsed it with a plain
   `json['grade'] as num?`, which throws on any string value — every task
   used while building the screen happened to have `grade: null`, so it
   never surfaced until a graded one did. This is a recurring bug class
   already fixed once in this codebase (`TaskInstance.fromJson` has its
   own doc comment about the identical issue, also noted for
   `TaskAdmin.grade`/`Payment.amount`); `PendingTask` should have followed
   that pattern from the start. Fixed identically:
   `grade: double.tryParse(json['grade']?.toString() ?? '')`, type changed
   from `num?` to `double?`.

## Dashboards & notifications

**Staff dashboard redesign** — the staff landing screen was a placeholder
(two plain centered buttons). Replaced with `home_screen.dart`'s
`_StaffDashboard`: a welcome header (name + role, later given a real
`CircleAvatar` reading `profile_image_url` instead of a hardcoded person
icon), a 2×2 "اختصارات سريعة" grid for the most-used actions (register
patient, appointments, payments, task-progress NFC), and the two module
hubs re-styled as icon/title/subtitle/chevron cards. `admin_hub_screen.dart`'s
flat 14-item list was reorganized into four sections (إدارة الأطباء /
البيانات الأساسية / سير العمل / الإعدادات), matching the same grouping
the web navbar (`AuthenticatedLayout.vue`) got the same day, so both
surfaces share one mental model.

**Doctor's "مهامي" rebuilt** — replaced a flat, status-filterable list
(`task_list_screen.dart`, couldn't show a required-but-not-started case,
no department grouping) with `my_tasks_screen.dart`: a `TabBar` per
department, each department grouping its slot cards by `taskId` into one
`ExpansionTile` per task (collapsed: title + "X/N مكتملة"). Reuses the
admin `task_progress_admin` feature's existing domain classes
(`TaskProgressDoctorRow`, `TaskSlotCard`) since both share the same
backend JSON shape (`TaskProgressGroupSummary::buildDoctorRow()`); a new
`MyTaskDepartment` wraps only the differing outer envelope (a doctor
viewing their own tasks is always exactly one doctor, not a list). A
doctor only ever views, never edits, from this screen. Backed by a new
`GET /my-task-progress` endpoint.

**In-app notification inbox** — new `features/notifications/` (mirroring
`task_instances`' structure): `AppNotification` domain model,
`notification_repository.dart` (`list()`/`markRead()`/`markAllRead()`),
`notifications_providers.dart` (`notificationsListProvider`,
`unreadNotificationCountProvider` derived from it — no dedicated count
endpoint). A bell `IconButton` + `Badge` sits in the sidebar/nav; tapping
a notification marks it read and navigates to the relevant
`/tasks/{taskInstanceId}` detail screen (the only notification type so
far is "a task was started for you"). Two real bugs found live:
1. **Stale inbox cache** — `notificationsListProvider` is `autoDispose`,
   but `HomeScreen`'s bell-badge watch kept a listener alive under a
   pushed route (go_router doesn't dispose it on push), so opening the
   inbox re-served stale cached data even after a new notification
   arrived. Fixed by invalidating the provider in a post-frame callback
   on the inbox screen's `initState`.
2. **Pull-to-refresh did nothing on an empty inbox** — only the non-empty
   list branch was wrapped in `RefreshIndicator`; the empty-state
   `Center(child: Text(...))` had no scrollable ancestor. Fixed by
   wrapping both branches in `RefreshIndicator` with
   `AlwaysScrollableScrollPhysics`.

**Firebase push scaffolding** — added inert until a real Firebase project
exists (confirmed with the user rather than guessing at credentials).
`firebase_core`/`firebase_messaging` added; Android's Google Services
Gradle plugin is declared `apply false` in `settings.gradle.kts` and
applied **conditionally** in `android/app/build.gradle.kts` only
`if (file("google-services.json").exists())`, so the build is unaffected
by the file's absence and self-activates once a real config is dropped in.
`main()` wraps `Firebase.initializeApp()` in try/catch (fails silently
until real config exists). New `PushNotificationService`: no-ops if
`Firebase.apps.isEmpty`; otherwise registers the FCM token via
`POST /device-tokens` and, on a foreground push, just invalidates the
existing notification providers rather than building a separate banner
UI. Verified safe with no `google-services.json` present: a full
`flutter run` completed cleanly with no Firebase-related build failure or
crash.

**Pending-tasks-QR screen** — the web app has a dedicated
`"رموز المهام المعلقة"` page (`PendingTasksQr.vue`); Flutter previously
only had inline per-row QR buttons inside "مهامي", not the dedicated grid
screen. Backend gained `PendingTaskQrController::index()`
(`GET /pending-tasks`), reusing the exact same `PendingTaskFinder::forDoctor()`
query the web page uses, so both surfaces stay in sync by construction.
Flutter: `PendingTask` domain model, `pendingTasksQrProvider`, and
`PendingTasksQrScreen` (title/department/required-count/grade/notes per
task, a "رمز QR" button reusing the existing generic `showQrDialog`
helper rather than a second QR modal). Added to the sidebar as the
doctor account type's 4th destination, matching the web nav's placement.

**"فتح كيس شيت" button added to both pending-tasks-QR screens (2026-09-02).**
By request. No new backend needed — reused the existing pre-instance draft
mechanism (`CaseSheetController::openForTask()`/`Api\CaseSheetController::openForTask()`,
`GET /doctor/case-sheet/for-task/{task}` web, `GET /tasks/{task}/case-sheet-draft`
API) already wired into `RequiredTasks.vue`'s "فتح النموذج" and
`MyTasksScreen`'s `_openCaseSheetForTask()` for not-yet-started slots — a
task on the pending-QR screen is by definition not-yet-started (no
`TaskInstance` exists at all yet), so it's the same case exactly, just a
different list. Web: `PendingTasksQr.vue` gained a second button per card
(`Link` to `route('doctor.case-sheet.for-task', task.id)`), same
indigo/gray-700 pairing as `RequiredTasks.vue`. Flutter:
`_PendingTaskCard` converted from `StatelessWidget` to
`ConsumerStatefulWidget` to carry the same loading-state/navigation logic
as `MyTasksScreen`'s `_SlotRowState._openCaseSheetForTask()`, verbatim
except keyed off `task.id` instead of `slot.taskId`. Verified live on both
platforms: opening the button for an "operative" task correctly landed on
a blank "المخطط السني (Operative)" draft form on both web and Flutter,
with the same "مسودة اختيارية غير مرتبطة بحالة مهمة بعد" notice.

## Fixed: the narrow-mode menu toggle was covering the AppBar's own back arrow (2026-09-01)

Reported live ("اختفى زر الرجوع" — the back button disappeared) after the
drag-drawer sidebar shipped. Root cause: the floating menu-toggle button
(`AppShell`'s narrow-mode branch) was pinned to the *leading* corner —
`top, right: 8` in RTL — which is exactly where Flutter's `AppBar`
automatically renders its own back arrow in RTL (the `leading` slot
mirrors to the visually-right side under RTL `Directionality`, the same
side `right: 8` targets). On any screen reached by a real push (a
genuine back stack to pop — drilling from a hub screen into a list, for
example), the 44px toggle button painted directly on top of that arrow,
hiding it completely; on screens with no back stack (fresh from a sidebar
tap) there was nothing to hide, which is why the bug didn't show up on
every screen and was easy to miss in earlier testing.

Fixed by moving the toggle to the *trailing* corner instead — the same
side an `AppBar`'s own `actions` render on, not its `leading` slot —
`left: 8` in RTL, `right: 8` in LTR (the reverse of before). This can't
collide with a back arrow in either direction; a screen's own AppBar
`actions` (rare on the hub/list screens this shell wraps) are the only
remaining, much less consequential, collision risk.

Also hardened, found while investigating: `main.dart` awaits
`Firebase.initializeApp()` before `runApp()`, wrapped in a try/catch —
but a *hang* (never resolving, as opposed to a quick rejection) rather
than a thrown error would block the entire app from ever rendering, with
nothing shown to the user. Added `.timeout(const Duration(seconds: 3))`
so a slow/unreachable Firebase backend can no longer block startup
indefinitely — the existing catch-and-continue (`PushNotificationService`
already no-ops without Firebase) handles the timeout exactly like any
other failure.

Not independently re-verified live this time — the local Flutter web-test
environment was unusually slow to render across several attempts this
session (unrelated to this fix; even a trivial reload was taking
30-60s+, likely accumulated resource pressure from many earlier test
runs in the same long session) and didn't finish rendering before time
was called on it. The fix is a straightforward, deterministic coordinate
swap (confirmed by re-reading `AppShell`'s exact `Positioned` values
against `AppBar`'s own well-documented RTL `leading` placement), not
something contingent on runtime behavior, so it was shipped on that
analysis rather than a live screenshot. `flutter analyze` clean.
