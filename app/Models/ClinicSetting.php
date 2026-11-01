<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Storage;

/**
 * Ports admin/clinic_settings.php + includes/settings_helper.php's
 * ClinicSettings class — a single-row settings table (always id=1).
 * MikroTik connection fields (mikrotik_ip/user/pass/ssh_port) exist on the
 * real imported table but are deliberately excluded here — out of scope by
 * explicit request, same as the MikroTik backup feature elsewhere in this
 * rebuild. `jwt_secret_key` also excluded: an internal secret column, not
 * a user-facing setting, and nothing in this rebuild's auth uses it
 * (Sanctum tokens are used instead).
 */
class ClinicSetting extends Model
{
    public $timestamps = false;

    // The single row is always created with an explicit id 1 (see
    // current()). With the default `$incrementing = true`, Eloquent then
    // reads the key back from LAST_INSERT_ID(), which MySQL leaves at 0 for
    // an explicit id — so the first save after the row was created updated
    // `id = 0` and was silently lost (found by AdminSettingsApiTest).
    public $incrementing = false;

    protected $fillable = [
        'id', // not auto-increment on the real table — always explicitly 1, see current()
        'clinic_name',
        'clinic_description',
        'clinic_logo',
        'clinic_address',
        'clinic_phone',
        'clinic_email',
        'clinic_website',
        'clinic_working_hours',
        'clinic_currency',
        'theme',
        'clinic_timezone',
        'base_url',
        'university_name',
        'college_name',
        'university_logo',
        'enable_notifications',
        'enable_sms',
        'enable_email',
        'mail_host',
        'mail_port',
        'mail_username',
        'mail_password',
        'mail_encryption',
        'mail_from_address',
        'mail_from_name',
        'enable_daily_backup',
        'last_backup_at',
        'lab_fee',
        'lab_validity_days',
        // Student discount on the lab fee (2026-10-25), see App\Support\StudentDiscount.
        'lab_student_discount_percent',
        // Care codes on/off (2026-11-01), see App\Support\SupportCodes.
        'support_codes_enabled',
        'groups_enabled',
        // "إعدادات النماذج" (2026-10-22), see App\Support\FormSettings.
        'electronic_forms_enabled',
        'paper_forms_enabled',
        'show_grades_to_doctors',
        'supervisor_code_enabled',
        'supervisor_code_period',
        'supervisor_code_actions',
        // Task progress switches for the whole system (2026-10-22).
        'task_start_enabled',
        'task_finish_enabled',
        'task_lists_enabled',
        'grade_entry_enabled',
        'step_add_enabled',
        'steps_enabled',
        'task_cancel_enabled',
    ];

    /**
     * `mail_password` — never sent to the browser; the settings form shows
     * whether a password is set, and leaving its field blank keeps the
     * stored one. `mikrotik_*`/`jwt_secret_key` — a real leak, found while
     * building the Flutter clinic-settings screen: this class's own
     * docblock claims these are "deliberately excluded," but that was only
     * ever true of `$fillable` (mass-assignment protection), not
     * serialization — `toArray()`/`toJson()` return every loaded column
     * regardless of `$fillable`. Both `ClinicSettingController::edit()`
     * (web, Inertia props) and `Api\ClinicSettingController::show()` spread
     * `$settings->toArray()` unfiltered, so the MikroTik router credentials
     * (including a password field, empty in dev but not guaranteed empty
     * in a real deployment) and the JWT secret were both actually reaching
     * the browser/API response. Hiding them here fixes both call sites at
     * once, the same way `mail_password` already was.
     */
    protected $hidden = ['mail_password', 'mikrotik_ip', 'mikrotik_user', 'mikrotik_pass', 'mikrotik_ssh_port', 'jwt_secret_key'];

    protected function casts(): array
    {
        return [
            'enable_notifications' => 'boolean',
            'enable_sms' => 'boolean',
            'enable_email' => 'boolean',
            'mail_password' => 'encrypted',
            'enable_daily_backup' => 'boolean',
            'last_backup_at' => 'datetime',
            'groups_enabled' => 'boolean',
            'electronic_forms_enabled' => 'boolean',
            'paper_forms_enabled' => 'boolean',
            'show_grades_to_doctors' => 'boolean',
            'supervisor_code_enabled' => 'boolean',
            'supervisor_code_actions' => 'array',
            'task_start_enabled' => 'boolean',
            'task_finish_enabled' => 'boolean',
            'task_lists_enabled' => 'boolean',
            'grade_entry_enabled' => 'boolean',
            'step_add_enabled' => 'boolean',
            'steps_enabled' => 'boolean',
            'task_cancel_enabled' => 'boolean',
            'support_codes_enabled' => 'boolean',
        ];
    }

    /** True once enough SMTP settings exist to actually send mail. */
    public function mailConfigured(): bool
    {
        return filled($this->mail_host) && filled($this->mail_from_address);
    }

    /**
     * Groups on/off (2026-10-13, by request). Off hides groups everywhere
     * they appear — menus, doctor pages, prints, the waiting screen — and
     * task progress lists a stage's doctors directly. Defaults to on when
     * the column has not been migrated yet.
     */
    public static function groupsEnabled(): bool
    {
        return (bool) (static::current()->groups_enabled ?? true);
    }

    public static function current(): self
    {
        return static::firstOrCreate(['id' => 1], [
            'clinic_name' => 'عيادة الأسنان',
            // Was 'ريال' / 'Asia/Riyadh' — inconsistent with
            // university_name below naming an Iraqi university. Iraq has no
            // timezone/currency selector elsewhere in this app (confirmed:
            // neither the original nor this port has a country field
            // anywhere), so this bootstrap default was the only place that
            // combination existed, and it named the wrong country.
            'clinic_currency' => 'دينار عراقي',
            'clinic_timezone' => 'Asia/Baghdad',
            'university_name' => 'Tikrit University',
            'college_name' => 'College of Dentistry',
            'enable_notifications' => true,
            'enable_sms' => false,
            'enable_email' => true,
        ]);
    }

    public function logoUrl(): ?string
    {
        // clinic_logo's real column DEFAULT is the literal string
        // 'default-logo.png' (a filename that existed in the original PHP
        // app's uploads/ folder, not anywhere in this app's storage) — a
        // never-uploaded row would otherwise produce a URL to a file that
        // was never actually written here, i.e. a broken image. Only
        // return a URL for a file that's actually present.
        return $this->clinic_logo && Storage::disk('public')->exists($this->clinic_logo)
            ? Storage::disk('public')->url($this->clinic_logo)
            : null;
    }

    public function universityLogoUrl(): ?string
    {
        return $this->university_logo && Storage::disk('public')->exists($this->university_logo)
            ? Storage::disk('public')->url($this->university_logo)
            : null;
    }
}
