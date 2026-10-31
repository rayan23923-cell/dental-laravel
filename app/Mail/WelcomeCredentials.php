<?php

namespace App\Mail;

use App\Models\ClinicSetting;
use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;

/**
 * Login details for a newly created account (staff user or doctor), sent
 * through the daily-capped queue (App\Services\CredentialMailer), or the
 * new ones after an admin reset the password (`reset`, 2026-10-21).
 */
class WelcomeCredentials extends Mailable
{
    use Queueable;

    public function __construct(
        public string $name,
        public string $username,
        public string $password,
        public string $accountType,
        public bool $reset = false,
        public ?string $loginUrl = null,
        /** Other addresses of the same server, e.g. its LAN IP. */
        public array $altUrls = [],
    ) {}

    public function envelope(): Envelope
    {
        return new Envelope(subject: 'بيانات الدخول إلى '.$this->clinicName());
    }

    public function content(): Content
    {
        return new Content(
            view: 'emails.welcome-credentials',
            with: [
                'clinicName' => $this->clinicName(),
                'loginUrl' => $this->loginUrl ?: route('login'),
                'altUrls' => $this->altUrls,
            ],
        );
    }

    private function clinicName(): string
    {
        return ClinicSetting::query()->value('clinic_name') ?: config('app.name');
    }
}
