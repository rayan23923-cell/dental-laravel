<?php

namespace App\Support;

use App\Models\ClinicSetting;
use App\Models\PatientRegistration;
use App\Models\Payment;
use App\Models\Service;
use App\Models\SupportCode;
use App\Models\User;
use App\Services\ActivityLogger;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Validation\ValidationException;

/**
 * Care codes, "بطاقات الرعاية" (2026-11-01, by request).
 *
 * The clinic generates one-time 5-digit codes, prints them as cards to cut
 * out and hand to patients who are treated free. The desk ticks
 * "مشمول بالرعاية" when registering and types the card's code: the service
 * and the lab test then cost 0, so nothing is booked against the ticket
 * desk or the lab and the payments report leaves them out of its totals; a
 * table on the report's last page lists them instead, with what was not
 * charged. A code works once; unused codes can be stopped (and started
 * again). The feature is off until switched on in the registration
 * settings. The wording stays neutral on purpose ("رعاية", not "محتاج").
 */
class SupportCodes
{
    public const LENGTH = 5;

    /** Most codes one generation makes. */
    public const MAX_BATCH = 500;

    /** Wrong codes an account may type before a short wait (codes are only 5 digits). */
    public const MAX_WRONG = 10;

    public const LOCK_SECONDS = 600;

    /** Module name in the activity log ("سجل النشاطات"). */
    public const LOG_MODULE = 'SupportCode';

    public const LABEL = 'مشمول بالرعاية';

    public static function enabled(?ClinicSetting $settings = null): bool
    {
        return (bool) ($settings ?? ClinicSetting::current())->support_codes_enabled;
    }

    /** Arabic-Indic digits to ASCII, everything else but digits dropped. */
    public static function normalize(?string $code): string
    {
        $code = strtr((string) $code, ['٠' => '0', '١' => '1', '٢' => '2', '٣' => '3', '٤' => '4', '٥' => '5', '٦' => '6', '٧' => '7', '٨' => '8', '٩' => '9',
            '۰' => '0', '۱' => '1', '۲' => '2', '۳' => '3', '۴' => '4', '۵' => '5', '۶' => '6', '۷' => '7', '۸' => '8', '۹' => '9']);

        return preg_replace('/\D+/', '', $code);
    }

    /**
     * Makes [$count] new codes in one batch. Codes never repeat, used ones
     * included, so a code always names one card.
     *
     * @return Collection<int, SupportCode>
     */
    public static function generate(int $count, ?string $note, ?User $user): Collection
    {
        $count = max(1, min(self::MAX_BATCH, $count));

        return DB::transaction(function () use ($count, $note, $user) {
            $batch = ((int) SupportCode::lockForUpdate()->max('batch')) + 1;
            $taken = SupportCode::pluck('code')->flip();
            if ($taken->count() + $count > 89000) {
                throw ValidationException::withMessages(['count' => 'لم يعد هناك أرقام كافية لتوليد أكواد جديدة.']);
            }

            $now = now();
            $rows = [];
            while (count($rows) < $count) {
                $code = (string) random_int(10000, 99999);
                if (isset($taken[$code])) {
                    continue;
                }
                $taken[$code] = true;
                $rows[] = [
                    'code' => $code,
                    'batch' => $batch,
                    'note' => $note !== null && trim($note) !== '' ? trim($note) : null,
                    'created_by' => $user?->id,
                    'created_at' => $now,
                    'updated_at' => $now,
                ];
            }
            SupportCode::insert($rows);
            $codes = SupportCode::where('batch', $batch)->orderBy('id')->get();
            ActivityLogger::log('create', self::LOG_MODULE, "توليد {$count} بطاقة رعاية (الدفعة {$batch})", $codes->first()?->id,
                ['batch' => $batch, 'count' => $count, 'note' => $rows[0]['note']]);

            return $codes;
        });
    }

    /**
     * Stops (or starts again) unused codes, picked by id or a whole batch.
     * Used codes stay as they are. Returns how many changed.
     */
    public static function setDisabled(array $ids, ?int $batch, bool $disabled, ?User $user): int
    {
        if ($ids === [] && $batch === null) {
            return 0;
        }

        $query = SupportCode::query()
            ->whereNull('used_at')
            ->where(fn ($q) => $q->when($ids !== [], fn ($q) => $q->whereIn('id', $ids))
                ->when($batch !== null, fn ($q) => $q->orWhere('batch', $batch)))
            ->when($disabled, fn ($q) => $q->whereNull('disabled_at'), fn ($q) => $q->whereNotNull('disabled_at'));
        $codes = (clone $query)->orderBy('id')->pluck('code')->all();
        $changed = $query->update($disabled
            ? ['disabled_at' => now(), 'disabled_by' => $user?->id, 'updated_at' => now()]
            : ['disabled_at' => null, 'disabled_by' => null, 'updated_at' => now()]);

        if ($changed > 0) {
            ActivityLogger::log('update', self::LOG_MODULE,
                ($disabled ? 'إيقاف' : 'إعادة تفعيل')." {$changed} بطاقة رعاية".($batch !== null ? " (الدفعة {$batch})" : ''),
                null, ['disabled' => $disabled, 'batch' => $batch, 'codes' => $codes]);
        }

        return $changed;
    }

    /** Switches the feature on or off from the registration settings, logging who did it. */
    public static function setEnabled(bool $enabled): void
    {
        ClinicSetting::current()->update(['support_codes_enabled' => $enabled]);
        ActivityLogger::log('update', self::LOG_MODULE, $enabled ? 'تفعيل بطاقات الرعاية' : 'إلغاء تفعيل بطاقات الرعاية', null, ['support_codes_enabled' => $enabled]);
    }

    /** Why [$code] cannot be used, or null when it can. */
    public static function problem(?SupportCode $code): ?string
    {
        return match ($code?->status()) {
            null => 'رمز الرعاية غير صحيح.',
            SupportCode::USED => 'رمز الرعاية هذا مستخدم مسبقًا.',
            SupportCode::DISABLED => 'رمز الرعاية هذا موقوف.',
            default => null,
        };
    }

    /**
     * Looks a typed code up for the desk, counting wrong guesses per
     * account. Throws a validation error on `support_code` when the
     * feature is off, the account is waiting, or the code cannot be used.
     */
    public static function lookup(string $typed, ?User $user): SupportCode
    {
        if (! self::enabled()) {
            throw ValidationException::withMessages(['support_code' => 'خاصية بطاقات الرعاية غير مفعلة في إعدادات التسجيل.']);
        }

        $key = 'support-code:'.($user?->id ?? request()->ip());
        if (RateLimiter::tooManyAttempts($key, self::MAX_WRONG)) {
            $minutes = (int) ceil(RateLimiter::availableIn($key) / 60);
            throw ValidationException::withMessages(['support_code' => "محاولات خاطئة كثيرة، حاول بعد {$minutes} دقيقة."]);
        }

        $digits = self::normalize($typed);
        $code = strlen($digits) === self::LENGTH ? SupportCode::firstWhere('code', $digits) : null;
        if ($problem = self::problem($code)) {
            if ($code === null) {
                RateLimiter::hit($key, self::LOCK_SECONDS);
            }
            throw ValidationException::withMessages(['support_code' => $problem]);
        }

        return $code;
    }

    /**
     * Marks the code used by [$registration] inside the registration's
     * transaction, with the service price it did not pay. The row is
     * re-read under a lock so two desks cannot use one card.
     */
    public static function redeem(SupportCode $code, PatientRegistration $registration, Service $service, ?User $user): void
    {
        $fresh = SupportCode::whereKey($code->id)->lockForUpdate()->first();
        if ($problem = self::problem($fresh)) {
            throw ValidationException::withMessages(['support_code' => $problem]);
        }

        $fresh->update([
            'used_at' => now(),
            'patient_registration_id' => $registration->id,
            'used_by' => $user?->full_name ?? $user?->username,
            'waived_service' => $service->price !== null ? (float) $service->price : null,
        ]);
        $registration->forceFill(['support_code_id' => $fresh->id])->save();
        ActivityLogger::log('update', self::LOG_MODULE, "استخدام بطاقة الرعاية {$fresh->code} للمراجع \"{$registration->name}\"", $fresh->id,
            ['code' => $fresh->code, 'patient_registration_id' => $registration->id, 'patient' => $registration->name, 'service' => $service->name, 'waived_service' => $fresh->waived_service]);
    }

    /** Records the lab fee a cared-for patient did not pay, when the result is recorded. */
    public static function noteLabWaived(PatientRegistration $registration): void
    {
        $fee = ClinicSetting::current()->lab_fee;
        if ($registration->support_code_id && $fee !== null) {
            $changed = SupportCode::whereKey($registration->support_code_id)->whereNull('waived_lab')->update(['waived_lab' => (float) $fee]);
            if ($changed > 0) {
                ActivityLogger::log('update', self::LOG_MODULE, "فحص مختبر مجاني (رعاية) للمراجع \"{$registration->name}\"", $registration->support_code_id,
                    ['patient_registration_id' => $registration->id, 'waived_lab' => (float) $fee]);
            }
        }
    }

    /** One code as the web page and the app show it. */
    public static function present(SupportCode $code): array
    {
        $registration = $code->relationLoaded('registration') ? $code->registration : null;

        return [
            'id' => $code->id,
            'code' => $code->code,
            'batch' => $code->batch,
            'note' => $code->note,
            'status' => $code->status(),
            'created_at' => $code->created_at,
            'disabled_at' => $code->disabled_at,
            'used_at' => $code->used_at,
            'used_by' => $code->used_by,
            'patient' => $registration ? ['id' => $registration->id, 'name' => $registration->name, 'phone' => $registration->phone] : null,
        ];
    }

    /** Counts by status for the page's tiles. */
    public static function counts(): array
    {
        return [
            'all' => SupportCode::count(),
            SupportCode::ACTIVE => SupportCode::inStatus(SupportCode::ACTIVE)->count(),
            SupportCode::USED => SupportCode::inStatus(SupportCode::USED)->count(),
            SupportCode::DISABLED => SupportCode::inStatus(SupportCode::DISABLED)->count(),
        ];
    }

    /** The batches, newest first, with how many of each are still active. */
    public static function batches(): array
    {
        return SupportCode::query()
            ->selectRaw('batch, MIN(created_at) AS created_at, MAX(note) AS note, COUNT(*) AS total')
            ->selectRaw('SUM(CASE WHEN used_at IS NULL AND disabled_at IS NULL THEN 1 ELSE 0 END) AS active')
            ->selectRaw('SUM(CASE WHEN used_at IS NOT NULL THEN 1 ELSE 0 END) AS used')
            ->groupBy('batch')->orderByDesc('batch')->limit(200)->get()
            ->map(fn ($b) => [
                'batch' => (int) $b->batch,
                'created_at' => $b->created_at,
                'note' => $b->note,
                'total' => (int) $b->total,
                'active' => (int) $b->active,
                'used' => (int) $b->used,
            ])->all();
    }

    /**
     * [reportRows()] for the payments page's filters: none for the
     * appointments source, only the lab / ticket part for those sources.
     */
    public static function reportRowsFor(array $filters, ?array $sources): array
    {
        $source = $filters['source'] ?? null;
        if ($source === 'appointment' || ($sources !== null && array_intersect($sources, ['registration', 'lab']) === [])) {
            return [];
        }
        $sources = $source && ($sources === null || in_array($source, $sources, true)) ? [$source] : $sources;

        return self::reportRows($filters['from'] ?? null, $filters['to'] ?? null, (string) ($filters['search'] ?? ''), $sources);
    }

    /**
     * The report's "المستفيدون من الرعاية" table: registrations made free by
     * a code in the date range (the day the code was used), with what was
     * not charged. Search matches the patient's name like the payments list.
     */
    public static function reportRows(?string $from, ?string $to, string $search = '', ?array $sources = null): array
    {
        $showService = $sources === null || in_array('registration', $sources, true);
        $showLab = $sources === null || in_array('lab', $sources, true);

        return SupportCode::query()
            ->whereNotNull('used_at')
            ->with(['registration.service'])
            ->when($from, fn ($q) => $q->whereDate('used_at', '>=', $from))
            ->when($to, fn ($q) => $q->whereDate('used_at', '<=', $to))
            ->when($search !== '', fn ($q) => $q->whereHas('registration', fn ($r) => $r->where('name', 'like', "%{$search}%")))
            ->orderBy('used_at')
            ->limit(5000)
            ->get()
            ->map(fn (SupportCode $c) => [
                'name' => $c->registration?->name,
                'phone' => $c->registration?->phone,
                'service' => $c->registration?->service?->name,
                'code' => $c->code,
                'waived_service' => $showService ? $c->waived_service : null,
                'waived_lab' => $showLab ? $c->waived_lab : null,
                'waived_total' => ($showService ? (float) $c->waived_service : 0) + ($showLab ? (float) $c->waived_lab : 0),
                'used_at' => $c->used_at?->setTimezone(PaymentStats::TIMEZONE)->format('Y-m-d H:i'),
                'used_by' => $c->used_by,
            ])->values()->all();
    }

    /**
     * The report's "المشمولون بالتخفيض" table: the discounted payments
     * among [$payments] (already filtered like the report), one row each.
     *
     * @param  iterable<Payment>  $payments
     */
    public static function discountRows(iterable $payments, ?ClinicSetting $settings = null): array
    {
        $settings ??= ClinicSetting::current();
        $rows = [];
        foreach ($payments as $p) {
            $registration = $p->patientRegistration;
            if (! $registration?->discount_eligible) {
                continue;
            }
            $full = StudentDiscount::fullAmountFor($p, $settings);
            $b = StudentDiscount::breakdown($registration, (float) $p->amount, $full);
            $rows[] = [
                'name' => $registration->name,
                'who' => $b['who'] ?? StudentDiscount::whoLabel($registration),
                'source' => $p->type === Payment::TYPE_LAB ? 'lab' : 'registration',
                'service' => $registration->service?->name,
                'full' => $full,
                'percent' => $b['percent'] ?? null,
                'paid' => (float) $p->amount,
                'saved' => $full !== null ? max(0, round($full - (float) $p->amount, 2)) : null,
                'paid_at' => $p->paid_at?->setTimezone(PaymentStats::TIMEZONE)->format('Y-m-d H:i'),
            ];
        }

        return array_reverse($rows);
    }
}
