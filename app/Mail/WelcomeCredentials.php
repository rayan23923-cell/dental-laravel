<?php

namespace App\Mail;

use App\Models\ClinicSetting;
use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;

/**
 * Login details for a newly created account (staff user or doctor), sent
 * through the daily-capped queue (App\Services\CredentialMailer).
 */
class WelcomeCredentials extends Mailable
{
    use Queueable;

    public function __construct(
        public string $name,
        public string $username,
        public string $password,
        public string $accountType,
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
                'loginUrl' => route('login'),
            ],
        );
    }

    private function clinicName(): string
    {
        return ClinicSetting::query()->value('clinic_name') ?: config('app.name');
    }
}
