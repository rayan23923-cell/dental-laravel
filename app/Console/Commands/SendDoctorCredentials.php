<?php

namespace App\Console\Commands;

use App\Models\Stage;
use App\Services\BulkCredentials;
use Illuminate\Console\Command;

/**
 * New random numeric passwords for the doctors (students) of the chosen
 * stages, emailed with their username and the login link (2026-10-31, by
 * request: the 4th and 5th stages); see App\Services\BulkCredentials.
 */
class SendDoctorCredentials extends Command
{
    protected $signature = 'doctors:send-credentials
        {--stage=* : Stage id, or part of its name (e.g. الرابعة)}
        {--login-url= : Link in the email (default: this server\'s login page)}
        {--alt-url=* : Other addresses of the server listed in the email, e.g. https://192.168.68.52}
        {--wifi= : Clinic Wi-Fi name to show in the email}
        {--save-file : Keep the login file on this server (downloadable on /users/bulk-credentials)}
        {--dry-run : Only show who would get an email}';

    protected $description = 'Reset the passwords of the doctors in the given stages and email them their login details';

    public function handle(): int
    {
        $wanted = (array) $this->option('stage');
        if (! $wanted) {
            $this->error('Give at least one --stage.');

            return self::FAILURE;
        }

        $stages = Stage::query()->get(['id', 'name'])->filter(function ($stage) use ($wanted) {
            foreach ($wanted as $w) {
                if ((string) $stage->id === (string) $w || str_contains($stage->name, (string) $w)) {
                    return true;
                }
            }

            return false;
        });
        if ($stages->isEmpty()) {
            $this->error('No stage matches.');

            return self::FAILURE;
        }
        $this->info('Stages: '.$stages->map(fn ($s) => "{$s->id} {$s->name}")->implode(', '));

        $dry = (bool) $this->option('dry-run');
        $mail = BulkCredentials::links($this->option('login-url'), (array) $this->option('alt-url'), $this->option('wifi'));
        ['reset' => $reset, 'no_email' => $noEmail] = BulkCredentials::resetDoctors($stages->pluck('id')->all(), $mail, $dry);

        foreach (BulkCredentials::stageSummary()->whereIn('id', $stages->pluck('id')) as $s) {
            $this->line("  {$s['name']} ({$s['education_type']}): {$s['with_email']} of {$s['doctors']} doctors have an email");
        }
        if (! $dry && $reset && $this->option('save-file')) {
            $this->info('Login file saved: '.BulkCredentials::saveLoginFile($reset, 'doctors-logins'));
        }
        $this->info(($dry ? '[dry run] would email ' : 'Reset and queued emails for ').count($reset).' doctors.');
        if ($reset) {
            $this->table(['name', 'username', 'email'], array_map(fn ($r) => [$r['name'], $r['username'], $r['email']], $reset));
        }
        if ($noEmail) {
            $this->warn(count($noEmail).' doctors have no email and were left unchanged:');
            $this->table(['name', 'username'], $noEmail);
        }

        return self::SUCCESS;
    }
}
