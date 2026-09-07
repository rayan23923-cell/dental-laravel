<?php

// Manifest the Windows desktop build checks on startup (see
// flutter_app/lib/core/updater/desktop_update_checker.dart). Bump 'version'
// and 'url' by hand each time a new installer is built with
// flutter_app/windows/installer/setup.iss and uploaded to the server — there
// is no admin UI for this, it is a one-line deploy-time edit like a
// .env value.
return [
    'windows' => [
        'version' => '1.0.1',
        'url' => 'https://cdclinics.com/downloads/DentalClinicSetup-1.0.1.exe',
        'notes' => null,
    ],
];
