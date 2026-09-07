# Dental Clinic — Flutter Client

Mobile client (Android + iOS, tablet-aware) for the teaching-clinic system,
consuming the `/api/v1` Laravel API built in the parent `dental_laravel/`
repo. This file is the living architecture reference; the detailed,
chronological build log has been condensed by topic into `../docs/` — see
[Development history](#development-history) below.

## Who this app is for

Two personas, treated differently rather than porting every admin screen
1:1:

- **Doctor** (dental student) — the primary mobile user: task list, case
  sheets, QR check-in, viewing progress. A genuinely mobile workflow
  (walking between clinic chairs, scanning a patient's QR).
- **Staff/Admin** — manages doctors, groups, permissions, clinic settings,
  backups. A desk-bound, data-entry-heavy workflow, fully built (Phase 3)
  even though it's lower day-to-day mobile priority.

## Architecture

```
lib/
  main.dart
  app.dart                      # MaterialApp.router + ProviderScope, Instagram theme
  core/
    network/
      api_client.dart           # Dio: base URL, bearer token interceptor, 401 handler
      api_exception.dart        # typed error wrapping Laravel's {message, errors} shape
    storage/
      token_storage.dart        # flutter_secure_storage wrapper
    router/
      app_router.dart           # go_router route table + auth-guard redirect + ShellRoute
      nav_destinations.dart     # account-type-aware sidebar nav list
    theme/
      app_theme.dart            # fixed Instagram-style light+dark theme, InstagramColors
    widgets/
      app_shell.dart            # persistent/drag sidebar frame — see docs/flutter-app-architecture-and-navigation.md
      app_sidebar.dart
      qr_dialog.dart, instagram_spinner.dart, ...
  features/                     # data/domain/presentation split per feature
    auth/ tasks/ task_instances/ case_sheet_forms/ records/ (patients/
    appointments/payments) doctors_admin/ permissions_admin/
    clinic_settings_admin/ backup_admin/ patient_registration/
    printing/ notifications/ profile/ ...
  l10n/                          # Arabic (primary) + English
```

Each feature folder: `data/` (repository calling `ApiClient`), `domain/`
(plain Dart models with `fromJson`, matching the API Resources' real field
names — no `freezed`/build_runner), `presentation/` (Riverpod providers +
screens/widgets).

**Stack choices**:

| Package | Role | Why this one |
|---|---|---|
| `dio` | HTTP client | Interceptors for the bearer token and centralized 401→logout |
| `flutter_riverpod` | State management | Compile-safe provider graph, testable without a `BuildContext` |
| `go_router` | Routing | Declarative routes, deep links, `ShellRoute` for the persistent sidebar |
| `flutter_secure_storage` | Token persistence | Keychain/Keystore-backed, not plain SharedPreferences |
| `mobile_scanner` | QR scanning | CameraX-based on Android; mirrors the web app's own QR check-in |
| `cached_network_image` | Images | Doctor photos, clinic/university logos |
| `image_picker` | Uploads | Profile photos, matches web upload fields |
| `flutter_svg` | Vector rendering | Tooth/implant artwork ported as raw SVG path strings |

**Auth** — one unified login: `POST /api/v1/login` (`login`/`password`/
`device_name`, tried against staff then doctors), returning `account_type`
so the client knows whether it got a `UserResource` or `DoctorResource`
shape (`AuthAccount` sealed class, `StaffAccount`/`DoctorAccount`
variants). Token stored via `flutter_secure_storage`; a `Dio` interceptor
attaches `Authorization: Bearer <token>` to every request and redirects to
`/login` on a `401`. See `docs/auth-and-public-pages.md` for the full
unification history.

**Case sheets** — one generic `DynamicSectionForm` widget renders any of
the 8+ clinical specialty forms from a schema the backend already serves
web (`GET /api/v1/case-sheet-forms/{resource}`), rather than 12 bespoke
screens. See `docs/case-sheets-and-clinical-charting.md` for the full
architecture and field-type catalogue.

**API surface** — grounded in `routes/api.php`; every route reachable
behind `auth:sanctum` except login and the public TV board. Covers: auth,
task instances (own work, QR), tasks catalogue, case-sheet forms/prints +
the specialty tables, dental charts, patients, appointments, payments,
lookups (education types/stages/departments), academic sessions, case
sheet types, groups, doctors, clinic settings, backup, activity log,
permissions, pending-task QR, and a public unauthenticated TV board.

**Localization & RTL** — Arabic primary throughout ("تسجيل الدخول",
"مهامي", etc.), English secondary. `flutter_localizations` + `intl`;
`MaterialApp.router` sets `locale: Locale('ar')` and Flutter's built-in RTL
handling covers directionality for Material widgets — navigation/drag
gestures that need to be direction-aware do so explicitly via
`Directionality.of(context)` (see the sidebar in
`docs/flutter-app-architecture-and-navigation.md`).

**Visual identity** — Instagram-style theme (`InstagramColors`,
`app_theme.dart`): real Instagram UI colours (`#0095F6` action blue,
`#ED4956` error red, true black `#000000` dark-mode background, `#262626`/
`#8E8E8E` text, `#DBDBDB`/`#262626` hairline borders), flat hairline-
bordered cards (no elevation), 8px corner radius, `ThemeMode.system`. The
brand gradient (`InstagramColors.gradient`) is spent sparingly as an
accent — the sidebar header badge, the profile "story ring," the loading
spinner — never a full-UI repaint. Full history in
`docs/auth-and-public-pages.md`.

## Installable builds

Windows `.msix` installer and an Android release `.apk` are both built and
verified — see `docs/flutter-app-architecture-and-navigation.md` for the
signing/build details.

A second Windows option, `windows/installer/setup.iss`, builds a
traditional `.exe` (Inno Setup) instead of `.msix` — no cert-trust step to
install, and the running app self-updates from it silently on startup
(`lib/core/updater/desktop_update_checker.dart` polls
`GET /api/v1/desktop/version`, backed by `config/desktop_releases.php`),
the same flow Telegram Desktop uses. To cut a new release: bump
`pubspec.yaml`'s version, `flutter build windows --release`, compile the
`.iss` with Inno Setup's `ISCC.exe`, upload the resulting installer, then
update `config/desktop_releases.php` to point at it.

## Development history

The detailed, chronological build log (~150 dated entries) has been
condensed by topic into the parent repo's `docs/` folder:

- **[`../docs/flutter-app-architecture-and-navigation.md`](../docs/flutter-app-architecture-and-navigation.md)**
  — build-phase history, installable builds, dashboards/notifications, and
  the ChatGPT-style persistent/drag sidebar (routing integration, RTL-aware
  drag mechanics, and the real bugs found building it).
- **[`../docs/case-sheets-and-clinical-charting.md`](../docs/case-sheets-and-clinical-charting.md)**
  — the case-sheet engine, odontogram, every specialty record type, and
  the Advanced Periodontal Chart's 12 revisions (web + Flutter).
- **[`../docs/supervisor-fields-and-auth-fixes.md`](../docs/supervisor-fields-and-auth-fixes.md)**
  — supervisor-only field access control, and the OTP password-reset bug
  hunt.
- **[`../docs/tasks-and-academic-structure.md`](../docs/tasks-and-academic-structure.md)**
  — required tasks, academic taxonomy, groups, permissions, NFC lookup.
- **[`../docs/patient-registration-and-front-desk.md`](../docs/patient-registration-and-front-desk.md)**
  — patient registration, the screening gate, payments, and thermal ticket
  printing (Bluetooth/USB/iOS BLE — the bulk of this app's hardware-
  integration work).
- **[`../docs/auth-and-public-pages.md`](../docs/auth-and-public-pages.md)**
  — login unification, OTP password reset, Instagram theming, PWA.
- **[`../docs/infrastructure-deployment-and-admin.md`](../docs/infrastructure-deployment-and-admin.md)**
  — PDF/print exports, production deployment, data migration.
