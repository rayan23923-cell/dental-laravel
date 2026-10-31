<?php

namespace App\Console\Commands;

use App\Services\BulkCredentials;
use Illuminate\Console\Command;

/**
 * Teaching-staff accounts from a CSV of names and emails (2026-10-31, by
 * request); see App\Services\BulkCredentials. The same is on the web at
 * /users/bulk-credentials.
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

        $dry = (bool) $this->option('dry-run');
        $mail = $this->option('no-email') ? null : BulkCredentials::links($this->option('login-url'), (array) $this->option('alt-url'));
        ['created' => $created, 'skipped' => $skipped] = BulkCredentials::importTeachers(self::readCsv($file), $mail, $dry);

        $this->info(($dry ? '[dry run] would create ' : 'Created ').count($created).' teacher accounts'.($dry || $mail === null ? '' : ' and queued their emails').'.');
        if ($created) {
            $this->table(['name', 'username', 'email'], array_map(fn ($r) => [$r['name'], $r['username'], $r['email']], $created));
        }
        if ($skipped) {
            $this->warn('Skipped '.count($skipped).':');
            $this->table(['name', 'email', 'reason'], $skipped);
        }

        return self::SUCCESS;
    }

    /** @return list<array{0: string, 1: string}> name, email (header and blank lines dropped) */
    public static function readCsv(string $file): array
    {
        $out = [];
        $handle = fopen($file, 'r');
        while (($row = fgetcsv($handle)) !== false) {
            $name = trim(preg_replace('/^\x{FEFF}/u', '', (string) ($row[0] ?? '')));
            $email = trim((string) ($row[1] ?? ''));
            if ($name !== '' && filter_var($email, FILTER_VALIDATE_EMAIL)) {
                $out[] = [$name, $email];
            }
        }
        fclose($handle);

        return $out;
    }
}
