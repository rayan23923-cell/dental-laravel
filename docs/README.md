# Development history

Condensed, topic-organized dev log for this project (web app in the parent
`dental_laravel/` repo + its `flutter_app/` companion) — moved here from
the two project READMEs, which had grown to ~250 dated, chronological
entries. Each page below groups related entries by subject regardless of
when they were written, and condenses the narrative while keeping concrete
facts (file paths, table/column names, real bug root causes).

- **[case-sheets-and-clinical-charting.md](case-sheets-and-clinical-charting.md)**
  — the generic case-sheet engine (web + Flutter), the odontogram, every
  clinical specialty record type, signatures & sign-off gating, case-sheet
  printing, the Plaque Index, and the Advanced Periodontal Chart's 12
  revisions.
- **[supervisor-fields-and-auth-fixes.md](supervisor-fields-and-auth-fixes.md)**
  — supervisor-only field access control rolled out across every
  case-sheet type, and the password-reset-via-OTP production bug hunt.
- **[tasks-and-academic-structure.md](tasks-and-academic-structure.md)**
  — the required-task system, academic sessions/stages/education-types/
  departments, groups, the permission matrix, and NFC doctor lookup.
- **[patient-registration-and-front-desk.md](patient-registration-and-front-desk.md)**
  — patient registration, the infectious-disease screening gate, payments/
  appointments, and thermal ticket printing (Bluetooth/USB/iOS BLE).
- **[auth-and-public-pages.md](auth-and-public-pages.md)**
  — login & auth-model unification, OTP password reset, the public landing
  page, the Instagram-style visual identity, and the installable PWA.
- **[infrastructure-deployment-and-admin.md](infrastructure-deployment-and-admin.md)**
  — the web module inventory, the JSON API surface, admin/settings
  screens, PDF exports, production deployment (GitHub Actions → cPanel),
  and the production data-migration/schema-drift fixes.
- **[flutter-app-architecture-and-navigation.md](flutter-app-architecture-and-navigation.md)**
  — the Flutter app's build-phase history, installable builds, and its
  navigation/dashboard/notifications UI, including the ChatGPT-style
  persistent/drag sidebar.

For current architecture (not history), see the top-level `README.md` and
`flutter_app/README.md` instead — these pages are development history, not
living reference docs, and may describe things that were later changed
again (each page notes it where known).
