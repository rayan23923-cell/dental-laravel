<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

// See App\Console\Commands\RunDatabaseBackup — the command itself checks
// the admin's daily-backup toggle and skips if today's backup already ran,
// so this only needs to fire at least once a day; the exact time isn't
// significant. Requires Laravel's scheduler to actually be ticking (see
// README "Daily backup — server setup" for the one-time Windows Task
// Scheduler entry XAMPP doesn't set up on its own).
Schedule::command('backup:run')->daily();
