<?php

namespace App\Services;

use App\Models\Doctor;
use App\Models\Stage;
use App\Models\User;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

/**
 * Accounts and login details in bulk (2026-10-31, by request): teaching
 * staff (تدريسي) from a list of names and emails, and new numeric passwords
 * for the doctors of chosen stages. The offline clinic server has no
 * internet, so this is done on the hosting, which emails everyone, and
 * the login file it gives is uploaded on the offline server to save the
 * same accounts and passwords there (applyFile).
 *
 * Every method returns the login details it produced as rows of
 * CREDENTIAL_COLUMNS.
 */
class BulkCredentials
{
    public const CREDENTIAL_COLUMNS = ['name', 'email', 'username', 'password', 'account_type'];

    public const PASSWORD_LENGTH = 8;

    /**
     * @param  iterable<array{0: string, 1: string}>  $rows  name, email
     * @param  array{login_url?: ?string, alt_urls?: list<string>}|null  $mail  null = don't queue emails here
     * @return array{created: list<array<string, string>>, skipped: list<array{name: string, email: string, reason: string}>}
     */
    public static function importTeachers(iterable $rows, ?array $mail, bool $dryRun = false): array
    {
        $seen = [];
        $created = [];
        $skipped = [];

        foreach ($rows as [$name, $email]) {
            $name = trim((string) $name);
            $email = trim((string) $email);
            $key = Str::lower($email);
            if ($name === '' || ! filter_var($email, FILTER_VALIDATE_EMAIL)) {
                if ($name !== '' || $email !== '') {
                    $skipped[] = ['name' => $name, 'email' => $email, 'reason' => 'ايميل غير صالح'];
                }

                continue;
            }
            if (isset($seen[$key])) {
                $skipped[] = ['name' => $name, 'email' => $email, 'reason' => 'مكرر في الملف'];

                continue;
            }
            $seen[$key] = true;

            if (User::whereRaw('LOWER(email) = ?', [$key])->exists()) {
                $skipped[] = ['name' => $name, 'email' => $email, 'reason' => 'له حساب مسبقاً'];

                continue;
            }

            $username = self::freeUsername(Str::before($email, '@'), array_column($created, 'username'));
            $password = CredentialMailer::generateNumericPassword(self::PASSWORD_LENGTH);

            if (! $dryRun) {
                User::create([
                    'full_name' => $name,
                    'username' => $username,
                    'email' => $email,
                    'password' => Hash::make($password),
                    'role' => 'teacher',
                    'status' => 'active',
                ]);
                if ($mail !== null) {
                    CredentialMailer::queueWelcome('user', $email, $name, $username, $password, false, $mail);
                }
            }
            $created[] = ['name' => $name, 'email' => $email, 'username' => $username, 'password' => $password, 'account_type' => 'user'];
        }

        return ['created' => $created, 'skipped' => $skipped];
    }

    /**
     * New numeric passwords for the doctors of $stageIds who have a real
     * email; their old password and app sessions stop working.
     *
     * @param  array{login_url?: ?string, alt_urls?: list<string>}|null  $mail  null = don't queue emails here
     * @return array{reset: list<array<string, string>>, no_email: list<array{name: string, username: string}>}
     */
    public static function resetDoctors(array $stageIds, ?array $mail, bool $dryRun = false): array
    {
        $reset = [];
        $noEmail = [];

        $doctors = Doctor::whereIn('stage_id', $stageIds)->orderBy('stage_id')->orderBy('name')->get();
        foreach ($doctors as $doctor) {
            if (! CredentialMailer::isDeliverable($doctor->email)) {
                $noEmail[] = ['name' => (string) $doctor->name, 'username' => (string) $doctor->username];

                continue;
            }
            $password = CredentialMailer::generateNumericPassword(self::PASSWORD_LENGTH);
            if (! $dryRun) {
                DB::transaction(function () use ($doctor, $password) {
                    $doctor->forceFill(['password' => Hash::make($password)])->save();
                    $doctor->tokens()->delete();
                });
                if ($mail !== null) {
                    CredentialMailer::queueWelcome('doctor', $doctor->email, $doctor->name, $doctor->username, $password, false, $mail);
                }
            }
            $reset[] = ['name' => (string) $doctor->name, 'email' => trim((string) $doctor->email), 'username' => (string) $doctor->username, 'password' => $password, 'account_type' => 'doctor'];
        }

        return ['reset' => $reset, 'no_email' => $noEmail];
    }

    /**
     * Saves on this server the accounts of a login file made on another
     * one (the hosting made and emailed them; the offline clinic server
     * has no internet), with the same usernames and passwords. Teachers
     * missing here are created; existing accounts, matched by username,
     * get the file's password. No emails are sent.
     *
     * @param  iterable<array<string, string>>  $rows  keyed by CREDENTIAL_COLUMNS
     * @return array{created: int, updated: int, skipped: list<array{name: string, username: string, reason: string}>}
     */
    public static function applyFile(iterable $rows): array
    {
        $created = 0;
        $updated = 0;
        $skipped = [];

        foreach ($rows as $row) {
            $name = trim((string) ($row['name'] ?? ''));
            $email = trim((string) ($row['email'] ?? ''));
            $username = trim((string) ($row['username'] ?? ''));
            $password = (string) ($row['password'] ?? '');
            if ($username === '' || $password === '') {
                $skipped[] = ['name' => $name, 'username' => $username, 'reason' => 'سطر ناقص'];

                continue;
            }

            if (($row['account_type'] ?? '') === 'doctor') {
                $doctor = Doctor::where('username', $username)->first();
                if (! $doctor) {
                    $skipped[] = ['name' => $name, 'username' => $username, 'reason' => 'الطالب غير موجود هنا'];

                    continue;
                }
                DB::transaction(function () use ($doctor, $password) {
                    $doctor->forceFill(['password' => Hash::make($password)])->save();
                    $doctor->tokens()->delete();
                });
                $updated++;

                continue;
            }

            $user = User::where('username', $username)->first();
            if ($user) {
                $user->forceFill(['password' => Hash::make($password)])->save();
                $user->tokens()->delete();
                $updated++;

                continue;
            }
            if ($email !== '' && User::whereRaw('LOWER(email) = ?', [Str::lower($email)])->exists()) {
                $skipped[] = ['name' => $name, 'username' => $username, 'reason' => 'الايميل لحساب آخر'];

                continue;
            }
            if (Doctor::where('username', $username)->exists()) {
                $skipped[] = ['name' => $name, 'username' => $username, 'reason' => 'اسم المستخدم لطالب'];

                continue;
            }
            User::create([
                'full_name' => $name !== '' ? $name : $username,
                'username' => $username,
                'email' => $email !== '' ? $email : $username.'@placeholder.local',
                'password' => Hash::make($password),
                'role' => 'teacher',
                'status' => 'active',
            ]);
            $created++;
        }

        return ['created' => $created, 'updated' => $updated, 'skipped' => $skipped];
    }

    /** Stages with how many of their doctors have an email, for the page. */
    public static function stageSummary(): Collection
    {
        $counts = Doctor::query()
            ->selectRaw("stage_id, COUNT(*) as total, SUM(CASE WHEN email IS NOT NULL AND email <> '' AND email NOT LIKE '%@placeholder.local' THEN 1 ELSE 0 END) as with_email")
            ->groupBy('stage_id')->get()->keyBy('stage_id');

        return Stage::query()->with('educationType:id,name')->orderBy('education_type_id')->orderBy('id')->get()
            ->map(fn (Stage $s) => [
                'id' => $s->id,
                'name' => $s->name,
                'education_type' => $s->educationType?->name,
                'doctors' => (int) ($counts[$s->id]->total ?? 0),
                'with_email' => (int) ($counts[$s->id]->with_email ?? 0),
            ]);
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

    /**
     * @param  list<string>  $altUrls
     * @return array{login_url?: string, alt_urls?: list<string>}
     */
    public static function links(?string $loginUrl, array $altUrls): array
    {
        return array_filter([
            'login_url' => trim((string) $loginUrl) ?: null,
            'alt_urls' => array_values(array_filter(array_map(fn ($u) => trim((string) $u), $altUrls))),
        ]);
    }
}
