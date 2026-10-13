<?php

// Backs both the /download page (resources/views/downloads.blade.php) and
// the Windows desktop build's silent self-update check (see
// flutter_app/lib/core/updater/desktop_update_checker.dart, which only ever
// reads 'windows.url' — always the raw .exe, since it downloads straight
// into a path it then executes; never point it at 'zip_url').
//
// 'zip_url' exists only for the human-facing /download page: Chrome/Edge
// silently block first-time downloads of unsigned .exe/.apk files (Google
// Safe Browsing / SmartScreen application reputation — confirmed
// 2026-09-07, the raw links produced no visible error at all, just no
// download). A .zip wrapper around the same file is scrutinized less
// aggressively and reliably reaches the user's disk; they unzip it
// themselves, one extra step.
//
// Bump 'version' and both URLs by hand each time a new build is cut and
// uploaded to public/downloads/ — there is no admin UI for this, it is a
// one-line deploy-time edit like a .env value.
return [
    'windows' => [
        'version' => '1.0.1',
        'url' => 'https://dental.azoclinic.duckdns.org/downloads/DentalClinicSetup-1.0.1.exe',
        'zip_url' => 'https://dental.azoclinic.duckdns.org/downloads/DentalClinicSetup-1.0.1.zip',
        'notes' => null,
    ],
    'android' => [
        'version' => '1.0.1',
        'url' => 'https://dental.azoclinic.duckdns.org/downloads/DentalClinicApp-1.0.1.apk',
        'zip_url' => 'https://dental.azoclinic.duckdns.org/downloads/DentalClinicApp-1.0.1.zip',
        'notes' => null,
    ],
    // Unsigned .ipa — sideloaded with Sideloadly/AltStore (see the install
    // steps on /download), so there is no zip wrapper and no self-update.
    'ios' => [
        'version' => '1.0.1',
        'url' => 'https://dental.azoclinic.duckdns.org/downloads/DentalClinicApp-1.0.1.ipa',
        'notes' => null,
    ],
];
