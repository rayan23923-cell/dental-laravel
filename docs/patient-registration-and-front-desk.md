# Patient registration, payments/appointments, and front-desk ticket printing

Front-desk (reception) staff — not doctors — register walk-in patients into
`PatientRegistration` (a separate concept from the older `patients` table
used by clinical records/appointments; see `App\Models\PatientRegistration`'s
docblock). Registration picks a day and a service (day narrows the service
list), and prints a thermal ticket carrying a QR code. That same QR is later
scanned twice: once by a lab/reception role to clear an infectious-disease
screening, and once at the payment desk to take payment. A doctor cannot
"start a task" on a patient, and a payment cannot be taken, until screening
is cleared. Both the Laravel/Inertia web app and the Flutter POS/tablet app
implement this workflow against the same backend, and both print physical
tickets — the Flutter side does so via a thermal printer reached over
built-in AIDL, Bluetooth SPP, USB, or (iOS) Bluetooth LE, depending on
hardware and platform.

## Patient registration flow

Flutter's `features/patient_registration/` (deliberately separate from
`features/records/`, which covers the unrelated `patients` table) has three
screens: `patient_registration_form_screen.dart` (day-first cascading
picker: picking a `RegisterDay` filters the `Service` dropdown to
`RegisterDay.services`, mirroring the web's `PatientRegistrations/Create.vue`),
`register_settings_screen.dart` (day/service CRUD, `permission:settings,edit`-gated),
and `patient_registration_list_screen.dart` (list + search + QR + print).
Entry point is "تسجيل المرضى" under the records hub, not admin — this is
front-desk work.

Two early bugs, both caught before/via on-device testing rather than code
review:
- `Api\PatientRegistrationController::index()` returned a raw
  `LengthAwarePaginator` (Laravel's flat default shape) instead of the
  `{data, meta}` shape every other paginated endpoint returns via
  `Resource::collection($query)->response()`, which broke the shared
  `core/network/paginated.dart` parser. Fixed with a new
  `PatientRegistrationResource`.
- The `Service` model had no explicit `$table`; Eloquent's naming
  convention inferred `services`, but the real table is `register_services`
  (the class predates a rename that never happened to the table). Fixed
  with `protected $table = 'register_services';`.
- A Flutter-only crash: the settings screen's "add day" `FilledButton` sat
  inside a `Row` next to an `Expanded` text field and threw `BoxConstraints
  forces an infinite width` — a `Row`'s non-flexible children get unbounded
  max-width, which `FilledButton`'s internal layout doesn't tolerate. The
  screen went to a blank white body with **zero logcat output**; only
  `flutter run`'s live console (not `adb install` + launch) surfaced the
  real exception. Fixed by wrapping the button in `Flexible`. Lesson kept
  in the README: a blank screen with no logcat output is not proof of a
  clean render.

**Diagnosis (task) field.** Registration later gained a "التشخيص" picker
(reusing the existing `tasksLookupProvider`, no new endpoint), showing the
picked task's stage/education-type as read-only context underneath.
`PatientRegistration` gained `taskId`/`taskTitle`/`stageName`/`educationTypeName`.

**Day-governed diagnosis.** Per the user's example ("Sunday's diagnosis is
قلع/extraction"), a new `register_day_task_map` pivot lets a day optionally
narrow which tasks are offered as diagnoses (opt-in per day — an
unconfigured day still shows every task). `RegisterDay` gained
`taskIds: List<int>`; the day picker's `onSelected` clears `_taskId` if the
newly-picked day has rules and the current pick isn't one of them. The task
picker moved from a plain dropdown to the shared `CascadingDropdown`
(`enableFilter: true`), which also fixed a standing complaint that none of
the dropdowns were searchable. `register_settings_screen.dart` got a
matching "التشخيص" section (search + per-day `FilterChip`s per task).

**Filterable pickers (Phase 5/6).** Day/service dropdowns became Material 3
`DropdownMenu(enableFilter: true)`; the registration list gained a debounced
(350ms) search field plus day/service filters, with the provider's family
key changed from a bare `String?` to a `PatientRegistrationFilter` record.
"قائمة المرضى" (the unrelated legacy `patients` list) was hidden from the
records hub, not removed — the appointment form's patient picker still
reads from it directly.

A recurring bug class worth noting: several `*.fromJson` parsers used
`(json['amount'] as num?)?.toDouble()` for a Laravel `decimal`-cast column
— but Laravel serializes `decimal` casts as a JSON **string** (`"5000.00"`),
not a number, so the cast threw after the API call had already succeeded.
This first surfaced as three duplicate 5,000 payments (`Payment.fromJson`)
because the UI reported "تعذر تسجيل الدفع" after the payment had, in fact,
already been recorded; it recurred for `TaskAdmin.grade` (crashed a whole
list with no error detail) and was proactively grepped-and-fixed in
`TaskInstance.grade`. Fix pattern each time:
`double.tryParse(json['field']?.toString() ?? '')`.

## Infectious-disease screening gate

A newly-registered patient must not be paid for, or have a doctor "start a
task" on them, until a lab/reception step scans the patient's ticket QR and
confirms "سليم" (clear).

**Architectural gap found before building this**: "بدء المهمة"
(`TaskStarter::start()`) created/reassigned a `TaskInstance` row that was
**not linked to any patient at all** — by explicit prior design, task
instances are a (task, doctor) case-count for training requirements, kept
separate from `PatientRegistration`. The user confirmed they wanted it
linked properly rather than left ungated, so this feature also threads
`patient_registration_id` through `TaskInstance` and the whole start-task
call chain, on both web and Flutter.

**Schema** (two additive migrations, no FK constraints, matching this
codebase's convention on `payments.patient_registration_id`):
`add_screening_status_to_patients_simple` adds `screening_status`
(`enum('pending','clear','flagged')`, default `pending`),
`screening_checked_by`, `screening_checked_at` to `patients_simple`;
`add_patient_registration_id_to_task_instances` adds a nullable
`patient_registration_id` to `task_instances`.

**One shared gate**: `App\Services\PatientScreeningGate::ensureClear()`
(throws `PatientScreeningException`), called from `TaskStarter::start()`
(now requires a `PatientRegistration` argument, gates before its existing
transaction) and from both web and API `PaymentController::store()` (only
when `patient_registration_id` is present — the reception-desk flow, not
the separate appointment-based payment flow). A refusal returns 422 (API)
or a flash error (web). New endpoint `POST /patient-registrations/{id}/screening`
(`{"screening_status": "clear"|"flagged"}`), gated by a new
`permission:patient_screening,confirm` module, so an admin can grant just
this ability to a "lab person" account. No new QR type — reuses the exact
same ticket QR (`{"type":"patient_registration","id":N}`) already used for
payment.

**Web UI**: `TaskProgress/Index.vue`'s "بدء مهمة للطبيب" modal gained an
"امسح رمز المريض" step (reusing the existing `QrScanner.vue`); "بدء" stays
disabled until a `clear` patient has been scanned.

**Real bug found while testing**: `Api\PatientRegistrationController::store()`
returned `$registration->load([...])` after `create()` — `load()` only
eager-loads relations, it does not refresh scalar columns, so the
freshly-created registration's DB-level-default `screening_status` came
back `null` instead of `'pending'`. Fixed by switching to `->fresh([...])`.
Caught by an E2E curl test, not code review.

**Same-day web follow-up**: the web app had no way to actually *confirm*
screening — only the scan-gate on starting a task. Added a "الفحص" status-badge
column plus a "تحديد" button/modal to `PatientRegistrations/Index.vue`,
posting to the same screening route. Deliberately **no QR camera scan on
web** — staff already see the row on screen. While fixing this, found a
second real gap: `Payments/Create.vue` had **no flash-message display at
all**, so a payment blocked by `PatientScreeningGate` failed completely
silently (redirect back, untouched form, no explanation) even though
`HandleInertiaRequests.php` already shared `flash.error` globally. Fixed by
adding the missing `v-if="page.props.flash?.error"` banner.

**"المختبر" dashboard shortcut.** The screening feature initially had no
visible home — only a small icon buried in the registrations list. Added a
first-class "المختبر" quick-access tile on both platforms: Flutter's
`_StaffDashboard` shortcuts grid (5th tile, `Icons.coronavirus_outlined` →
the existing scan-screening route) and web's `Dashboard.vue` "Quick access"
grid (gated by the same `patient_screening.confirm` permission via a new
`can.patient_screening` prop from `DashboardController::index()`).

## Payments & appointments

**Linking to registrations.** Payments and appointments both gained
`patient_registration_id`/`Name`/`Phone` fields and a `personName` getter
(preferring the registration name, falling back to the legacy appointment
name). The Flutter payment/appointment forms gained a source-type toggle
between the old appointment picker and a new registered-patient picker
(`PatientRegistrationListScreen(pickMode: true)`). Editing a legacy
appointment (registration null, only the old `patient_id` set) doesn't
force a pick — validation only requires a registration on **create**,
matching the backend's `sometimes`/`required` split.

An unrelated bug found live while verifying this: `_pickDate()`'s
`showDatePicker` used `initialDate: DateTime.now()` against a hardcoded
`firstDate: DateTime(2020)`. The test device's system clock read 2010, so
`initialDate` fell before `firstDate` and tripped `showDatePicker`'s own
assertion, crashing the picker on every tap. Fixed by clamping
`initialDate` into `[firstDate, lastDate]`. The same unclamped pattern was
left as a known latent gap in three other screens.

**Scan-to-pay at the desk.** `QrScanScreen` gained a
`QrScanMode.patientRegistrationPayment` (alongside the existing
task-instance mode) reachable from a scanner icon on the registration list.
A successful scan pushes `PatientRegistrationPaymentScreen` with the
resolved registration + payments + `total_paid`/`is_paid` state: paid shows
a banner + payment list, unpaid shows an amount field plus `0`/`00`/`000`/clear
"quick-digit" buttons that append to whatever's typed (type "5", tap "000"
→ 5000) — the same UX later ported back into the plain web payment form.

**Web payment form got the same treatment later**: `Payments/Create.vue`
previously loaded **every** `PatientRegistration` into one giant `<select>`
— unusable past a handful of rows. Replaced with scan-or-search: a new
`GET /patient-registrations/search?q=` endpoint (name/phone `like`, capped
at 10, plain JSON), the existing `QrScanner.vue` for scanning, and the same
quick-digit amount buttons (the amount input switched from `type="number"`
to `inputmode="decimal"` text, since appending digits to a native number
input isn't reliable cross-browser).

**"Tap a row to pay" (Flutter).** The registration list's search UI already
let staff find a patient by name, but tapping a row outside of "pick mode"
did nothing — there was no way to go from "found by name" straight to
paying without also scanning. Fixed by wiring the normal row tap to open
the payment screen directly via the same `status(id)` lookup the QR path
already used.

**PaymentFormScreen iterated three times in one day**, driven by live
feedback after each ship:
1. Gained a QR scanner (`QrScanMode.paymentPatientLink`) and quick-digit
   buttons; blocked (not-clear) registrations render a "لا يمكن الدفع"
   banner and leave the submit-guard active rather than hard-erroring.
2. Simplified to registration-only — the "موعد" (appointment) source
   toggle was removed entirely, `_paidAt` defaulted to now, and "دفع
   بواسطة" was dropped. **Real correctness fix included**: since `update()`
   is a partial update, a form that only ever sent
   `patient_registration_id` and never touched `appointment_id` would leave
   a pre-existing appointment-sourced payment with *both* FKs set at once.
   Fixed by always explicitly sending `'appointment_id': null` (confirmed
   safe against Laravel's `prohibits`/`required_without`, which short-circuit
   to "not triggered" when the field's own value fails `required`).
3. After a real double-payment attempt, added paid/screening feedback:
   `PatientRegistrationPaymentScreen`'s `_ScreeningBlockedBanner`/`_PaidBanner`
   were extracted into a shared `core/widgets/registration_status_banners.dart`.
   A new `RegistrationPaymentState? _paymentState` is populated on both the
   scan and pick paths (the pick path previously discarded payment/screening
   data entirely — now follows up with a `status(id)` call). Deliberately
   scoped to **create only** — editing an existing payment never checks
   "already paid" against itself. `تاريخ الدفع` was removed from the screen
   completely; `paid_at` is never sent on create (DB default fills it) and
   never touched on update.

**Payment list filtering**: a filter icon opens a bottom sheet with a
date-range (`from`/`to` on `paid_at`) plus a موعد|تسجيل مريض source
dropdown; the family key became a `PaymentFilters` Dart record for
structural-equality caching.

## Thermal ticket printing — Android (built-in POS, Bluetooth, USB)

The original plan assumed an external Bluetooth printer; the actual
hardware ("Q2i" MediaTek Android 8.1 POS terminal) has a printer **built
in**.

**Finding the SDK.** `adb shell pm list packages` showed a system priv-app
`com.iposprinter.iposprinterservice` exposing an AIDL bind action (no
readable bytecode — resources only). The real interface came from the
vendor's published SDK PDF, cross-checked against the device (the PDF's
sample Bluetooth address matched the exact address of a pre-bonded
"IposPrinter" device in this unit's own `dumpsys bluetooth_manager`).

**Bug 1**: the PDF's AIDL reference table silently omits the
`IPosPrinterCallback` parameter every method actually takes. Since AIDL
transaction codes are positional, the reconstructed interface called the
wrong methods entirely, failing with a null-callback crash. Fixed by
replacing it with the genuine `.aidl` files transcribed from an
Apache-2.0-licensed open-source Cordova plugin for the same service, found
by searching the real error text.

**Bug 2**: even with the correct interface, `printerInit()` still returned
`isSuccess=false` on this unit specifically (confirmed not a paper/hardware
fault — the same printer worked via Android's own print dialog). Fixed by
implementing the SDK's documented second route: the built-in printer is
also reachable as a virtual Bluetooth SPP device speaking plain ESC/POS.
`PosPrinterPlugin.kt` now tries AIDL first and **falls back to Bluetooth
SPP** on any AIDL failure, connecting to the bonded "IposPrinter" over
RFCOMM and writing an ESC/POS raster block (`GS v 0`). Verified twice: by
the user, and independently via the printer service's own
`BUSY_ACTION → CURRENT_TASK_PRINT_COMPLETE_ACTION → NORMAL_ACTION` logcat
sequence.

**Why the ticket is a bitmap, not printer text**: the built-in printer's
fonts are Chinese GBK/GB18030 + ASCII only, no Arabic glyphs (confirmed
from the printer service's own bundled font resources). `ticket_widget.dart`
renders as a real Flutter widget (correct Arabic shaping/RTL);
`ticket_renderer.dart` rasterizes it off-screen via `OverlayEntry` +
`RepaintBoundary` at `pixelRatio: 1.0`, pinned to 384 logical px (the
documented 384-dot line width); only the resulting PNG crosses the platform
channel. Printing never blocks or rolls back registration — the record is
already saved before printing is attempted.

**Generalized connectivity.** A settings screen
(`printer_settings_screen.dart`, `إعدادات الطابعة`) added three connection
types — built-in (default, unchanged path), Bluetooth (pair via Android's
own system PIN dialog — no custom PIN UI built), USB — plus a 58mm/80mm
paper-width choice (576 vs 384 raster dots, ~8 dots/mm). `TicketWidget`/
`ReceiptWidget` gained a `widthDots` parameter (previously hardcoded to
384) so paper-width actually changes the rendered bitmap, not just the
Kotlin-side raster width. `printViaUsb()` is genuinely new: `UsbManager`/
`UsbDeviceConnection`, finds the first bulk-OUT endpoint across all
interfaces (not assumed to be interface 0), chunks `bulkTransfer()` at the
endpoint's own max packet size. New `EventChannel`
(`.../bt_scan_events`) streams live `ACTION_FOUND` results for Bluetooth
discovery.

Build/version issues hit along the way: `permission_handler`'s transitive
`permission_handler_android` resolved to a version whose Gradle DSL was
incompatible with this project's pinned Kotlin/AGP versions (pinned for
Android 8.1/API 27 compatibility) — fixed with a `dependency_overrides` pin
rather than bumping the toolchain. Separately, three build attempts were
needed because `dl.google.com` was intermittently very slow/unstable
(confirmed via `curl`, not a build misconfiguration).

**Layout crash found on-device, invisible to `flutter analyze`**:
`app_theme.dart`'s button themes default `minimumSize` to
`Size.fromHeight(44)` (infinite width) for standalone full-width buttons.
Every inline button placed in a `Row` (scan/refresh/select buttons)
inherited that and crashed `performLayout()` with "BoxConstraints forces an
infinite width," silently eating the whole row. Fixed with explicit
`minimumSize` overrides on each affected button rather than touching the
shared theme.

## Thermal ticket printing — iOS (Bluetooth LE)

Printing only worked on Android until this point — no classic Bluetooth
SPP, no general USB-host API on iOS for non-MFi devices. The production
printer (a generic "58E" thermal receipt printer) was confirmed via the
LightBlue BLE-scanner app to support Bluetooth LE, exposing GATT service
`0xFF00` (`0xFF01` notify / `0xFF02` write+writeWithoutResponse / `0xFF03`
notify — a very common generic Chinese BLE-serial-module pattern) with
`0x18F0`/`0x2AF0`/`0x2AF1` as a fallback. Its advertisement carries **no**
service UUID, so any scan filtering by service UUID would never find it.

New `ios/Runner/PosPrinterPlugin.swift` (CoreBluetooth-based) is wired to
the *exact same* MethodChannel/EventChannel names Android uses, so
`pos_printer_service.dart` needed zero Dart-side changes.
`bitmapToEscPosRaster()` (including the `ESC d 8` trailing-feed constant —
a hardware fact, not an OS detail) was ported byte-for-byte, rewritten from
Android's `Bitmap.getPixels()` to a `CGContext`-based RGBA read. It scans
for **all** BLE peripherals (no service filter, since the advertisement
omits it), discovers `FF00→FF02` first with `18F0→2AF1` as fallback, writes
in MTU-sized chunks with `.withResponse` (this class of cheap BLE-serial
printer is known to drop unthrottled `.withoutResponse` writes), and waits
the same 2000ms as Android before disconnecting.

Deliberate platform differences (each a real constraint, not an oversight):
`requestEnableBluetooth` is a no-op (iOS exposes no programmatic
Bluetooth-on API); `listPairedDevices` always returns `[]` (BLE has no
OS-level bonded-devices list); `pairDevice` doesn't classically pair — it
connects, resolves the GATT profile, disconnects, and reports
success/failure, which is the honest BLE equivalent of "verify this address
is a real printer"; `isLocationEnabled` always reports `true` (BLE scanning
never needed Location on iOS); "built-in"/"USB" connection types are hidden
entirely on iOS.

A sharp non-obvious gotcha: `ios/Runner.xcodeproj/project.pbxproj` is a
manually-maintained file list, not a glob — a new `.swift` file must be
registered at 4 separate points (`PBXBuildFile`, `PBXFileReference`, the
group's `children`, `PBXSourcesBuildPhase`'s `files`), each with a fresh
24-hex-digit ID, or the build fails with a confusing "cannot find in scope"
error despite the file existing on disk.

**Three real bugs found testing on a physical iPhone, in sequence:**

1. **Bluetooth scan permanently blocked.** The scan requested
   `Permission.bluetoothScan`/`bluetoothConnect` unconditionally — those are
   Android-12+-only permission types with no iOS mapping in
   `permission_handler`, so they always read as denied on iOS regardless of
   the real CoreBluetooth grant. Fixed by requesting `Permission.bluetooth`
   on iOS instead. A second, independent guard bug: `task_progress_screen.dart`'s
   `_printReceipt()` had its own `if (kIsWeb || !Platform.isAndroid) return;`
   at the top of the function — missed because the original sweep only
   checked the line calling `printTicket()`, not the whole enclosing
   function, so "طباعة الوصل بعد بدء المهمة" was a silent no-op on iOS.
2. **Pairing had nothing to select from.** iOS's `listPairedDevices()`
   always returns `[]` (no bonded-devices concept in BLE), but the settings
   screen's flow required tapping "اقتران" on a *discovered* device, then
   "تحديد" on that same device once it reappeared in the *paired* list —
   which never happened on iOS, so `bluetoothAddress` was never saved and
   printing failed with `[bad_args: عنوان بلوتوث مفقود]`. Fixed: on iOS, a
   successful pair calls the selection step directly instead of reloading
   the (always-empty) paired list.
3. **Printing worked but was slow.** `resolveWriteCharacteristic()` always
   chose `.withResponse` (ack after every ~20–180-byte chunk) whenever the
   characteristic supported plain `.write`, even though FF02 also supports
   `.writeWithoutResponse`. With reliability now confirmed, this became a
   user-facing "وضع الطباعة" toggle (سريع/آمن) — `BluetoothWriteMode {fast,
   safe}` on `PrinterSettings`, defaulting to `fast`, shown only on iOS
   (Android's classic SPP has no equivalent distinction).

## Cross-cutting Bluetooth bugs (Android)

Three separate, non-obvious Bluetooth bugs surfaced on Android across two
sessions, each confirmed via live `adb`/`dumpsys` inspection rather than
guessed:

- **Scan silently missing real devices.** On Android 6–11 (API 23–30),
  classic Bluetooth discovery silently withholds results from any app
  lacking a location permission — `startDiscovery()` still reports success
  and `ACTION_DISCOVERY_FINISHED` still fires, the found devices are just
  never delivered. The manifest declared only `BLUETOOTH_SCAN` (Android
  12+, irrelevant to the API-27 test device). Fixed by adding
  `ACCESS_FINE_LOCATION` scoped to `maxSdkVersion="30"` and requesting
  `Permission.locationWhenInUse` alongside Bluetooth permissions on the
  affected OS range only.
- **Scan hang when Bluetooth is off.** The `EventChannel` handler backing
  the scan only checked that a Bluetooth adapter *exists*, not that it's
  *enabled*, and discarded `startDiscovery()`'s boolean return — with
  Bluetooth off, discovery silently returns `false` and fires neither
  `ACTION_FOUND` nor `ACTION_DISCOVERY_FINISHED`, so the scanning spinner
  never stopped. Fixed with an explicit `adapter.isEnabled` check up front
  plus new MethodChannel calls (`isBluetoothEnabled`, `requestEnableBluetooth`,
  `isLocationEnabled`, `openLocationSettings`) so the UI can offer one-tap
  "تشغيل"/"الإعدادات" buttons. A related bug found live in the same pass: the
  new SnackBar action buttons were nearly invisible, since the app theme set
  a SnackBar background/content color but no `actionTextColor` — fixed with
  an explicit blue `textColor`.
- **Broadcasts silently dropped (`RECEIVER_NOT_EXPORTED`).** Even with
  Bluetooth on and both runtime permissions granted, the scan still never
  found new devices or stopped. `dumpsys bluetooth_manager` showed the OS
  adapter had genuinely finished discovering while the app's spinner kept
  running; `dumpsys activity broadcasts` showed `ACTION_FOUND`/
  `ACTION_DISCOVERY_FINISHED` reaching several other apps but marked
  `Skipped` for this app's receiver every time. Root cause:
  `registerReceiverCompat()` registered the scan/pairing receivers with
  `Context.RECEIVER_NOT_EXPORTED` on API 33+ — but on this Android 13
  build, broadcasts from the Bluetooth stack process (uid 1002) are **not**
  treated as equivalent to the system (uid 1000) for that check, so they
  were dropped with no exception or log line at the app level. Fixed by
  giving `registerReceiverCompat()` an `exported` parameter, `true` for the
  two Bluetooth-stack-sourced receivers (the USB-permission receiver, which
  only receives this app's own self-sent broadcast, was unaffected and
  stayed `false`).
- **Printer-not-connected alert.** Every `printTicket()` failure previously
  showed a bare `Text('... $e')`. A shared `showPrinterErrorSnackBar()`
  helper now covers all four print call sites, with an action button
  jumping straight to the printer-settings screen. Deliberately treats
  every failure identically — the native plugin funnels all print failures
  through one generic `print_failed` error, so message-matching would be
  fragile. Later gained a special case: if the configured printer is
  Bluetooth and it's simply switched off, `printTicket()` now proactively
  calls `requestEnableBluetooth()` (Android's "allow app to turn on
  Bluetooth?" prompt) and the SnackBar shows a specific "وافق على تفعيله ثم
  أعد الطباعة" message with no settings-navigation action, since the system
  prompt is the fix.
- **Insufficient paper feed after Bluetooth/USB tickets.** Reported on real
  hardware: staff had to manually feed paper after every ticket to clear
  the tear bar. Root cause: `bitmapToEscPosRaster()` (shared by both the
  Bluetooth and USB code paths — the built-in AIDL path doesn't use it,
  which is why the bug was Bluetooth/USB-only) sent `ESC d 4` (~17mm of
  trailing feed) after the image — not enough to clear the tear bar past
  the QR code. Changed to `ESC d 8` (~34mm).

## Ticket presentation polish

Several small, mostly independent visual changes accumulated on the same
ticket-rendering path:

- **Feed animation.** `showTicketPrintAnimation()` shows a non-dismissible
  dialog revealing the actual rendered ticket PNG top-to-bottom over 1.1s
  (paper "feeding" out of a printer-slot graphic) while the real print call
  runs concurrently via `Future.wait`, so neither a fast nor slow print
  desyncs from the animation.
- **Logo + bigger text/QR.** The ticket gained an optional logo (fetched
  from `ClinicSettings.universityLogoUrl ?? logoUrl`, same precedence the
  web letterhead uses), larger title/QR/date text, and the QR itself grew
  from `widthDots * 0.55` to `* 0.75` of paper width by request — still
  proportionate at both 58mm and 80mm.
- **A deployment gotcha found while verifying the logo**: the backend's
  `logo_url` is an absolute URL built from Laravel's `APP_URL`. With the
  dev default of `APP_URL=http://localhost/...`, a physical device can
  never reach it (`localhost` resolves to the phone itself) — not a bug,
  since the logo fetch already fails open, but real deployments must set
  `APP_URL` to a client-reachable host or every absolute-URL asset silently
  goes missing on physical hardware while working fine from same-machine
  emulators.
- **Final polish pass**: the logo went from a fixed 72×72px square to
  `width: widthDots` with height omitted (preserves aspect ratio, scales to
  full paper width); the header title/subtitle switched from hardcoded
  Arabic strings to `ClinicSettings`-sourced text (falling back to the old
  hardcoded strings only if settings are empty); and the borderless
  label/value rows (`ticketRow()`) were replaced with a real bordered
  `Table` (`ticketTable()`), with row text bumped 18px → 22px. The
  previously logo-less `ReceiptWidget` (payment-desk receipt) gained one to
  match the registration ticket and reprint paths.
