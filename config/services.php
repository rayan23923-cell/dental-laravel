<?php

return [

    // Speech for calling names on the waiting screen (2026-11-17), see
    // App\Services\Speech\SpeechSynthesizer. On the VPS `url` is the Piper
    // container; on the Windows server piper\piper.exe is found by itself.
    'tts' => [
        'url' => env('TTS_URL'),
        'piper_bin' => env('PIPER_BIN'),
        'piper_voices' => env('PIPER_VOICES'),
    ],


    /*
    |--------------------------------------------------------------------------
    | Third Party Services
    |--------------------------------------------------------------------------
    |
    | This file is for storing the credentials for third party services such
    | as Mailgun, Postmark, AWS and more. This file provides the de facto
    | location for this type of information, allowing packages to have
    | a conventional file to locate the various service credentials.
    |
    */

    'postmark' => [
        'key' => env('POSTMARK_API_KEY'),
    ],

    'resend' => [
        'key' => env('RESEND_API_KEY'),
    ],

    'ses' => [
        'key' => env('AWS_ACCESS_KEY_ID'),
        'secret' => env('AWS_SECRET_ACCESS_KEY'),
        'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    ],

    'slack' => [
        'notifications' => [
            'bot_user_oauth_token' => env('SLACK_BOT_USER_OAUTH_TOKEN'),
            'channel' => env('SLACK_BOT_USER_DEFAULT_CHANNEL'),
        ],
    ],

    // "Sign in with Google" for both login screens — see
    // App\Http\Controllers\Auth\GoogleAuthController. One OAuth app/redirect
    // URI serves both guards; which one a callback resolves against is
    // carried through the session, not a second registered redirect URI.
    'google' => [
        'client_id' => env('GOOGLE_CLIENT_ID'),
        'client_secret' => env('GOOGLE_CLIENT_SECRET'),
        'redirect' => env('GOOGLE_REDIRECT_URI'),
    ],

];
