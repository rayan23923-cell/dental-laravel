<?php

// Backs both the /download page (resources/views/downloads.blade.php) and
// the Windows desktop build's silent self-update check (see
// flutter_app/lib/core/updater/desktop_update_checker.dart, which only ever
// reads the 'windows' key). Bump 'version' and 'url' by hand each time a new
// build is cut and uploaded to public/downloads/ — there is no admin UI for
// this, it is a one-line deploy-time edit like a .env value.
return [
    'windows' => [
        'version' => '1.0.1',
        'url' => 'https://cdclinics.com/downloads/DentalClinicSetup-1.0.1.exe',
        'notes' => null,
    ],
    'android' => [
        'version' => '1.0.1',
        'url' => 'https://cdclinics.com/downloads/DentalClinicApp-1.0.1.apk',
        'notes' => null,
    ],
];
