<?php

namespace App\Services;

use App\Models\QueuedEmail;
use Illuminate\Support\Str;

/**
 * Queues the welcome email (username + password) for a newly created account.
 * Nothing is sent here: `mail:send-queued` drains the queue every minute
 * without exceeding the daily cap, so a 600-row Excel import spreads over two
 * days instead of getting the Gmail account blocked.
 */
class CredentialMailer
{
    /** Readable passwords: no 0/O/1/l/I lookalikes, since people type them from an email. */
    public static function generatePassword(int $length = 10): string
    {
        $alphabet = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789';
        $password = '';
        for ($i = 0; $i < $length; $i++) {
            $password .= $alphabet[random_int(0, strlen($alphabet) - 1)];
        }

        return $password;
    }

    /** Digits only (2026-10-31, by request for the teaching staff and students). */
    public static function generateNumericPassword(int $length = 8): string
    {
        $password = (string) random_int(1, 9);
        for ($i = 1; $i < $length; $i++) {
            $password .= random_int(0, 9);
        }

        return $password;
    }

    public static function isDeliverable(?string $email): bool
    {
        $email = trim((string) $email);

        return $email !== '' && ! Str::endsWith($email, '@placeholder.local') && filter_var($email, FILTER_VALIDATE_EMAIL);
    }

    /**
     * Usernames in an import sheet whose generated password nobody could ever
     * learn: no default password was given and the row has no usable email.
     *
     * @param  array<int, array<int, mixed>>  $rows  sheet rows, header first
     * @return list<string>
     */
    public static function unreachableImportRows(array $rows): array
    {
        $missing = [];
        foreach (array_slice($rows, 1) as $row) {
            [, , $email, , $username] = array_pad($row, 5, null);
            $username = trim((string) $username);
            if ($username !== '' && ! self::isDeliverable((string) $email)) {
                $missing[] = $username;
            }
        }

        return $missing;
    }

    /**
     * @param  'doctor'|'user'  $accountType
     * @param  bool  $reset  an admin set a new password on an existing account
     * @param  array{login_url?: string, alt_urls?: list<string>}  $links  where to sign in, when
     *                                                                     not this server's own login page (e.g. https://clinic.lan and its IP)
     */
    public static function queueWelcome(string $accountType, ?string $email, string $name, string $username, string $plainPassword, bool $reset = false, array $links = []): bool
    {
        // The Excel importer fills a missing email with {username}@placeholder.local.
        if (! self::isDeliverable($email)) {
            return false;
        }
        $email = trim((string) $email);

        QueuedEmail::create([
            'kind' => QueuedEmail::KIND_WELCOME,
            'recipient_email' => $email,
            'recipient_name' => $name,
            'payload' => [
                'account_type' => $accountType,
                'name' => $name,
                'username' => $username,
                'password' => $plainPassword,
                'reset' => $reset,
                'login_url' => $links['login_url'] ?? null,
                'alt_urls' => array_values($links['alt_urls'] ?? []),
            ],
            'status' => QueuedEmail::STATUS_PENDING,
        ]);

        return true;
    }
}
