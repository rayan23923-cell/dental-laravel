<?php

namespace App\Console\Commands;

use App\Mail\WelcomeCredentials;
use App\Models\ClinicSetting;
use App\Models\QueuedEmail;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Mail;
use Throwable;

/**
 * Sends pending rows from `queued_emails`, never more than MAIL_DAILY_LIMIT
 * in one day (Gmail SMTP caps a free account at ~500/day; the default 400
 * leaves room for password-reset codes and the settings test email).
 * Scheduled every minute; what doesn't fit today goes out tomorrow.
 */
class SendQueuedEmails extends Command
{
    protected $signature = 'mail:send-queued {--batch=20 : Most messages to send in one run}';

    protected $description = 'Send queued emails (welcome credentials) within the daily sending cap';

    private const MAX_ATTEMPTS = 3;

    public function handle(): int
    {
        // Until SMTP is set up on the settings screen, mail would only go to
        // the log: keep the queue intact rather than "sending" it there.
        if (! ClinicSetting::query()->find(1)?->mailConfigured()) {
            $this->info('SMTP is not configured; leaving the queue untouched.');

            return self::SUCCESS;
        }

        $dailyLimit = (int) config('mail.daily_limit', 400);
        $sentToday = QueuedEmail::where('status', QueuedEmail::STATUS_SENT)
            ->where('sent_at', '>=', now()->startOfDay())
            ->count();
        $room = min($dailyLimit - $sentToday, (int) $this->option('batch'));

        if ($room <= 0) {
            $this->info("Daily limit reached ({$sentToday}/{$dailyLimit}).");

            return self::SUCCESS;
        }

        $pending = QueuedEmail::where('status', QueuedEmail::STATUS_PENDING)->orderBy('id')->limit($room)->get();

        foreach ($pending as $email) {
            try {
                Mail::to($email->recipient_email, $email->recipient_name)->send($this->mailableFor($email));

                // The payload holds the password: drop it once it has been delivered.
                $email->update(['status' => QueuedEmail::STATUS_SENT, 'sent_at' => now(), 'payload' => null, 'last_error' => null]);
            } catch (Throwable $e) {
                $attempts = $email->attempts + 1;
                $email->update([
                    'attempts' => $attempts,
                    'last_error' => mb_substr($e->getMessage(), 0, 1000),
                    'status' => $attempts >= self::MAX_ATTEMPTS ? QueuedEmail::STATUS_FAILED : QueuedEmail::STATUS_PENDING,
                ]);
                report($e);
            }
        }

        $this->info("Processed {$pending->count()} queued emails ({$sentToday} already sent today, limit {$dailyLimit}).");

        return self::SUCCESS;
    }

    private function mailableFor(QueuedEmail $email): WelcomeCredentials
    {
        $p = $email->payload;

        return new WelcomeCredentials($p['name'], $p['username'], $p['password'], $p['account_type'], (bool) ($p['reset'] ?? false), $p['login_url'] ?? null, $p['alt_urls'] ?? []);
    }
}
