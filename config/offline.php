<?php

// The offline (one Windows PC) edition, see offline/README.md.
// The package's .env sets OFFLINE_EDITION=true; the hosted system leaves it off.
return [
    'edition' => (bool) env('OFFLINE_EDITION', false),

    // An offline copy works only after it is activated with a university's
    // code (2026-10-17, by request). Off only in the package's own smoke test.
    'activation' => (bool) env('OFFLINE_ACTIVATION', true),

    // The hosted system that issues and checks activation codes and serves
    // the offline builds and their updates.
    'server' => rtrim((string) env('OFFLINE_LICENSE_SERVER', 'https://dental.azoclinic.duckdns.org'), '/'),

    // The licensing portal (routes/licensing.php): served at the root of this
    // host when set (e.g. licenses.azoclinic.duckdns.org), else under /licensing.
    'portal_domain' => env('LICENSING_DOMAIN') ?: null,
];
