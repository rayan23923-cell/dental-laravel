<?php

namespace App\Console\Commands;

use App\Models\LicenseAdmin;
use Illuminate\Console\Command;
use Illuminate\Support\Str;

/**
 * Creates a licensing portal account, or gives an existing one a new
 * password (2026-10-17). The password is random and printed once; with
 * --password-file it is written to that file instead of the screen.
 */
class LicensingAdmin extends Command
{
    protected $signature = 'licensing:admin {username} {--name= : Display name} {--password-file= : Write the password to this file instead of printing it}';

    protected $description = 'Create a licensing portal account, or reset its password';

    public function handle(): int
    {
        $username = (string) $this->argument('username');
        $password = Str::password(16, symbols: false);

        $admin = LicenseAdmin::firstOrNew(['username' => $username]);
        $created = ! $admin->exists;
        $admin->name = $this->option('name') ?: ($admin->name ?: $username);
        $admin->password = $password;
        $admin->save();

        $line = "username: {$username}\npassword: {$password}\n";
        if ($file = $this->option('password-file')) {
            file_put_contents($file, $line);
            @chmod($file, 0600);
            $this->info(($created ? 'Account created.' : 'Password reset.')." Password written to {$file}");
        } else {
            $this->info($created ? 'Account created.' : 'Password reset.');
            $this->line($line);
        }

        return self::SUCCESS;
    }
}
