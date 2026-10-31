<?php

namespace App\Console\Commands;

use App\Models\Doctor;
use App\Models\User;
use App\Services\CredentialMailer;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

/**
 * Teaching-staff accounts from a list of names and emails (2026-10-31, by
 * request): role `teacher` (تدريسي), username = the part of the email
 * before "@", a random numeric password, and the login details queued for
 * email (sent by `mail:send-queued` within the daily cap). Departments and
 * permissions are picked later on the permissions screen.
 *
 * The file is a CSV (UTF-8) with two columns, name and email; a header row
 * and repeated emails are skipped, as is anyone who already has an account
 * with that email.
 */
class ImportTeachers extends Command
{
    protected $signature = 'teachers:import
        {file : CSV with the columns name,email}
        {--login-url= : Link in the email (default: this server\'s login page)}
        {--alt-url=* : Other addresses of the server listed in the email, e.g. https://192.168.68.52}
        {--no-email : Create the accounts without queueing emails}
        {--dry-run : Only show what would be done}';

    protected $description = 'Create teaching-staff (تدريسي) accounts from a CSV of names and emails and email them their login details';

    public function handle(): int
    {
        $file = (string) $this->argument('file');
        if (! is_readable($file)) {
            $this->error("Cannot read {$file}");

            return self::FAILURE;
        }

        $rows = self::readCsv($file);
        $dry = (bool) $this->option('dry-run');
        $links = $this->links();
        $seen = [];
        $created = [];
        $skipped = [];

        foreach ($rows as [$name, $email]) {
            $key = Str::lower($email);
            if (isset($seen[$key])) {
                $skipped[] = [$name, $email, 'مكرر في الملف'];

                continue;
            }
            $seen[$key] = true;

            if (User::whereRaw('LOWER(email) = ?', [$key])->exists()) {
                $skipped[] = [$name, $email, 'له حساب مسبقاً'];

                continue;
            }

            $username = self::freeUsername(Str::before($email, '@'), array_column($created, 1));
            $password = CredentialMailer::generateNumericPassword();

            if (! $dry) {
                User::create([
                    'full_name' => $name,
                    'username' => $username,
                    'email' => $email,
                    'password' => Hash::make($password),
                    'role' => 'teacher',
                    'status' => 'active',
                ]);
                if (! $this->option('no-email')) {
                    CredentialMailer::queueWelcome('user', $email, $name, $username, $password, false, $links);
                }
            }
            $created[] = [$name, $username, $email];
        }

        $this->info(($dry ? '[dry run] would create ' : 'Created ').count($created).' teacher accounts'.($dry || $this->option('no-email') ? '' : ' and queued their emails').'.');
        if ($created) {
            $this->table(['name', 'username', 'email'], $created);
        }
        if ($skipped) {
            $this->warn('Skipped '.count($skipped).':');
            $this->table(['name', 'email', 'reason'], $skipped);
        }

        return self::SUCCESS;
    }

    /** @return array{login_url?: string, alt_urls?: list<string>} */
    private function links(): array
    {
        return array_filter([
            'login_url' => $this->option('login-url') ?: null,
            'alt_urls' => array_values(array_filter((array) $this->option('alt-url'))),
        ]);
    }

    /** @return list<array{0: string, 1: string}> name, email */
    public static function readCsv(string $file): array
    {
        $out = [];
        $handle = fopen($file, 'r');
        while (($row = fgetcsv($handle)) !== false) {
            $name = trim(preg_replace('/^\x{FEFF}/u', '', (string) ($row[0] ?? '')));
            $email = trim((string) ($row[1] ?? ''));
            if ($name === '' || ! filter_var($email, FILTER_VALIDATE_EMAIL)) {
                continue; // header or blank line
            }
            $out[] = [$name, $email];
        }
        fclose($handle);

        return $out;
    }

    /** The email's local part, or with 2, 3, … appended when a user or doctor already has it. */
    public static function freeUsername(string $base, array $taken = []): string
    {
        $base = Str::lower(trim($base));
        $candidate = $base;
        for ($i = 2; in_array($candidate, $taken, true)
            || User::where('username', $candidate)->exists()
            || Doctor::where('username', $candidate)->exists(); $i++) {
            $candidate = $base.$i;
        }

        return $candidate;
    }
}
