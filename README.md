# Dental Clinic — Laravel + Inertia (Vue) Rewrite

Rebuild of the `dental_clinics2` PHP application on Laravel 12 + Inertia.js +
Vue 3 + Tailwind, using the real `clinic_system2` database schema, plus a
versioned JSON API (Sanctum) for the companion Flutter (Android/iOS) client
in `flutter_app/`.

Local dev URL (web app): `http://localhost/dental_laravel/public`
Local dev URL (API base): `http://localhost/dental_laravel/public/api/v1`

**LAN access (test from a phone on the same Wi-Fi)**:
`http://192.168.1.155/dental_laravel/public` — this machine's local IP at
the time this was last verified (Apache binds `0.0.0.0:80`, not just
`127.0.0.1`; Windows Firewall has an inbound-allow rule for "Apache HTTP
Server"/"XAMPP HTTP" on port 80). Laravel's asset URLs resolve against the
*request's own* host, not a hardcoded `APP_URL`, so pages render correctly
from another device with no config change. This IP changes if the machine
reconnects to Wi-Fi or moves networks — re-check with `ipconfig` if it stops
working. Production is deployed separately at `https://cdclinics.com` (see
`docs/infrastructure-deployment-and-admin.md`).

This file is the living technical reference for the rebuild — kept accurate
as modules are added. It covers what's actually implemented and how the
pieces fit together; it deliberately does **not** carry a chronological
build log anymore — see [Development history](#development-history) below
for that.

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

## Auth model — two separate guards, one unified login form

The original PHP app had two independent login systems (staff vs. doctors);
this rebuild keeps that separation at the guard/table level, but the actual
`/login` form (web) and `POST /api/v1/login` (API) are unified — one
identifier field (username or email) tried against staff first, then
doctors (`App\Http\Requests\Auth\LoginRequest`), so callers don't need to
know a doctor from a staff account ahead of time. The API's login response
includes `account_type` so the Flutter client knows which resource shape
(`UserResource` vs `DoctorResource`) it got back.

| Guard | Table | Notes |
|---|---|---|
| `web` (default) | `users` | Session auth; `users.role` enum: `super_admin`, `admin`, `editor`, `doctor` (unused — see below), `accountant`, `senior`, `hr` |
| `doctor` | `doctors` | Session auth; doctor identity is always a `doctors` row + the `doctor` guard, never a `users` row with `role=doctor` |

Both `User` and `Doctor` models use Sanctum's `HasApiTokens`, so a single
`auth:sanctum` middleware authenticates either kind of token — Sanctum
resolves the token to whichever model created it (polymorphic
`personal_access_tokens.tokenable`), independent of the session-guard
wiring in `config/auth.php`.

## Setup

1. Database `dental_laravel` already created (XAMPP MySQL, `root` / same
   password as the PHP app's `config/db.php`).
2. `composer install && npm install`
3. `.env` configured + `php artisan key:generate`
4. `php artisan migrate --seed`
5. `npm run build` (production) or `npm run dev` (Vite dev server)
6. PWA icons (only needed after changing `public/icons/icon-source*.svg`):
   `npm run generate:pwa-icons`

## Flutter client

`flutter_app/` — the mobile client for the `/api/v1` API above (Android +
iOS), Instagram-styled, using go_router + Riverpod. See
`flutter_app/README.md` for its own stack/architecture reference, and
`docs/flutter-app-architecture-and-navigation.md` for the condensed build
history (navigation, dashboards, notifications).

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
- Generic case-sheet engine: one `sections()`-driven form renderer serves
  all clinical specialty types on both platforms rather than bespoke
  screens per sheet — see `docs/case-sheets-and-clinical-charting.md` for
  the full architecture.

## Explicitly out of scope (by request)

- **MikroTik backup integration** — the original PHP app's router-based
  off-site backup feature. Not being ported.

## Not yet built

- **Camera QR scanning UI** on the web — the generate/scan/resolve API loop
  is built; no browser-camera scanner page (the original's
  `qr_scanner.html`) — that lives in the Flutter client instead.
- `doctor_tasks`, `task_assignments`, `task_progress`, `doctor_task_progress`
  — imported for schema fidelity, no models/controllers.
- `tooth_conditions` / `tooth_treatments` — have models
  (`ToothCondition`, `ToothTreatment`) and relations off `DentalChart`, but
  no dedicated controllers or routes; `dental_charts.tooth_data` (JSON) is
  the confirmed real write path, so these two are schema fidelity + read-
  via-relation only for now.

Each of these follows the same pattern established so far: Eloquent model →
web controller + Inertia Vue pages → matching API controller + Resource +
routes in `routes/api.php`.

## Development history

This project was built incrementally with a detailed dev log kept alongside
the code. That log grew to ~250 dated entries and has been condensed
(by topic, not chronologically) into `docs/`:

- **[`docs/case-sheets-and-clinical-charting.md`](docs/case-sheets-and-clinical-charting.md)**
  — the generic case-sheet engine, the odontogram, every clinical specialty
  record type, signatures & sign-off gating, case-sheet printing, the
  Plaque Index, and the Advanced Periodontal Chart's 12 revisions.
- **[`docs/supervisor-fields-and-auth-fixes.md`](docs/supervisor-fields-and-auth-fixes.md)**
  — supervisor-only field access control across every case-sheet type, and
  the password-reset-via-OTP bug hunt.
- **[`docs/tasks-and-academic-structure.md`](docs/tasks-and-academic-structure.md)**
  — the required-task system, academic sessions/stages/education-types/
  departments, groups, the permission matrix, and NFC doctor lookup.
- **[`docs/patient-registration-and-front-desk.md`](docs/patient-registration-and-front-desk.md)**
  — patient registration, the infectious-disease screening gate, payments/
  appointments, and thermal ticket printing (Bluetooth/USB/iOS BLE).
- **[`docs/auth-and-public-pages.md`](docs/auth-and-public-pages.md)**
  — login & auth model history, the public landing page, the Instagram-
  style visual identity, and the installable PWA.
- **[`docs/infrastructure-deployment-and-admin.md`](docs/infrastructure-deployment-and-admin.md)**
  — the web module inventory, the JSON API surface, admin/settings screens,
  PDF exports, production deployment (GitHub Actions → cPanel), and the
  production data-migration/schema-drift fixes.
- **[`docs/flutter-app-architecture-and-navigation.md`](docs/flutter-app-architecture-and-navigation.md)**
  — the Flutter app's own architecture, build phases, installable builds,
  and its navigation/dashboard/notifications UI (including the ChatGPT-
  style persistent sidebar).
