<?php

namespace App\Console\Commands;

use App\Models\Doctor;
use App\Models\Stage;
use App\Services\CredentialMailer;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Hash;

/**
 * Gives the doctors (students) of the chosen stages a new random numeric
 * password and emails it with their username and the login link
 * (2026-10-31, by request: the 4th and 5th stages). Their old password
 * stops working and their app sessions are signed out.
 */
class SendDoctorCredentials extends Command
{
    protected $signature = 'doctors:send-credentials
        {--stage=* : Stage id, or part of its name (e.g. الرابعة)}
        {--login-url= : Link in the email (default: this server\'s login page)}
        {--alt-url=* : Other addresses of the server listed in the email, e.g. https://192.168.68.52}
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
        $links = array_filter([
            'login_url' => $this->option('login-url') ?: null,
            'alt_urls' => array_values(array_filter((array) $this->option('alt-url'))),
        ]);
        $sent = [];
        $noEmail = [];

        $doctors = Doctor::whereIn('stage_id', $stages->pluck('id'))->orderBy('stage_id')->orderBy('name')->get();
        foreach ($doctors as $doctor) {
            if (! CredentialMailer::isDeliverable($doctor->email)) {
                $noEmail[] = [$doctor->name, $doctor->username];

                continue;
            }
            if (! $dry) {
                $password = CredentialMailer::generateNumericPassword();
                $doctor->forceFill(['password' => Hash::make($password)])->save();
                $doctor->tokens()->delete();
                CredentialMailer::queueWelcome('doctor', $doctor->email, $doctor->name, $doctor->username, $password, false, $links);
            }
            $sent[] = [$doctor->name, $doctor->username, $doctor->email];
        }

        $this->info(($dry ? '[dry run] would email ' : 'Reset and queued emails for ').count($sent).' doctors.');
        if ($sent) {
            $this->table(['name', 'username', 'email'], $sent);
        }
        if ($noEmail) {
            $this->warn(count($noEmail).' doctors have no email and were left unchanged:');
            $this->table(['name', 'username'], $noEmail);
        }

        return self::SUCCESS;
    }
}
