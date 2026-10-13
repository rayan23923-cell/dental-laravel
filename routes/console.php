<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

// See App\Console\Commands\RunDatabaseBackup — the command itself checks
// the admin's daily-backup toggle and skips if today's backup already ran,
// so firing hourly backs up once a day at the first hour the computer is
// on (a clinic laptop is often off at midnight). Requires Laravel's scheduler to actually be ticking (see
// README "Daily backup — server setup" for the one-time Windows Task
// Scheduler entry XAMPP doesn't set up on its own).
Schedule::command('backup:run')->hourly();

// Welcome emails with login details (App\Services\CredentialMailer), sent a
// batch at a time within the daily cap (config mail.daily_limit).
Schedule::command('mail:send-queued')->everyMinute()->withoutOverlapping();
