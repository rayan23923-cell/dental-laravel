<?php

namespace App\Providers;

use App\Models\ClinicSetting;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\ServiceProvider;

/**
 * Applies the SMTP settings stored on the clinic_settings row over the
 * `.env` mail config at boot, so mail host/credentials are changed from the
 * settings screen rather than by editing files on the server.
 *
 * Falls back to whatever `.env` says when the settings row has no host —
 * out of the box that's `MAIL_MAILER=log`, which writes mail to the Laravel
 * log instead of sending. That means forgot-password works for testing
 * before SMTP is configured, and the settings page says so explicitly.
 */
class MailSettingsServiceProvider extends ServiceProvider
{
    public function boot(): void
    {
        // Guarded so `migrate` on a fresh database (before clinic_settings
        // exists) can't fail on a boot-time query.
        try {
            if (! Schema::hasTable('clinic_settings')) {
                return;
            }
        } catch (\Throwable) {
            return;
        }

        $settings = ClinicSetting::query()->find(1);

        if (! $settings || ! $settings->mailConfigured()) {
            return;
        }

        Config::set('mail.default', 'smtp');
        Config::set('mail.mailers.smtp.host', $settings->mail_host);
        Config::set('mail.mailers.smtp.port', $settings->mail_port ?: 587);
        Config::set('mail.mailers.smtp.username', $settings->mail_username);
        Config::set('mail.mailers.smtp.password', $settings->mail_password);
        Config::set('mail.mailers.smtp.encryption', $settings->mail_encryption ?: null);
        Config::set('mail.from.address', $settings->mail_from_address);
        Config::set('mail.from.name', $settings->mail_from_name ?: $settings->clinic_name);
    }
}
