<?php

// The offline (one Windows PC) edition, see offline/README.md.
// The package's .env sets OFFLINE_EDITION=true; the hosted system leaves it off.
return [
    'edition' => (bool) env('OFFLINE_EDITION', false),

    // An offline copy works only after it is activated with a university's
    // code (2026-10-17, by request). Off only in the package's own smoke test.
    'activation' => (bool) env('OFFLINE_ACTIVATION', true),

    // The plain-http port of the offline server (the panel's HTTP_PORT,
    // 2026-11-05): the Wi-Fi/certificate page is linked over http so a
    // device without the clinic certificate never sees a warning first.
    'http_port' => (int) env('OFFLINE_HTTP_PORT', 80),

    // The hosted system that issues and checks activation codes and serves
    // the offline builds and their updates.
    'server' => rtrim((string) env('OFFLINE_LICENSE_SERVER', 'https://dental.azoclinic.duckdns.org'), '/'),

    // The licensing portal (routes/licensing.php): served at the root of this
    // host when set (e.g. licenses.azoclinic.duckdns.org), else under /licensing.
    'portal_domain' => env('LICENSING_DOMAIN') ?: null,
];
