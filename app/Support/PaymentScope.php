<?php

namespace App\Support;

use App\Models\Payment;
use App\Models\User;
use App\Services\PermissionManager;
use Illuminate\Database\Eloquent\Builder;

/**
 * Which payments an account may see (2026-10-26, by request): the lab
 * account sees and prints the lab fees only, the ticket desk the tickets'
 * (registrations') income only, each with the payments page's filters.
 * `payments.view` still sees every payment, as before.
 *
 * `sources()` is null for "everything", otherwise the allowed sources
 * ('lab', 'registration'). For the printed report, `payments.view` covers
 * everything only together with `payments.export`; without it the report
 * falls back to the account's lab / tickets grants.
 */
class PaymentScope
{
    public const SOURCES = ['lab' => 'view_lab', 'registration' => 'view_tickets'];

    /** The permission list for `permission:payments,…` route middleware. */
    public const VIEW = 'view|view_lab|view_tickets';

    public const REPORT = 'export|view_lab|view_tickets';

    /** @return list<string>|null */
    public static function sources(?User $user, bool $report = false): ?array
    {
        if (! $user) {
            return [];
        }
        $permissions = new PermissionManager($user);
        if ($permissions->can('payments', 'view') && (! $report || $permissions->can('payments', 'export'))) {
            return null;
        }

        return array_keys(array_filter(self::SOURCES, fn ($permission) => $permissions->can('payments', $permission)));
    }

    /** Limits a payments query to [$sources] (null: no limit). */
    public static function apply(Builder $query, ?array $sources): Builder
    {
        if ($sources === null) {
            return $query;
        }

        return $query->where(fn ($q) => $q
            ->when(in_array('lab', $sources, true), fn ($q) => $q->orWhere('type', Payment::TYPE_LAB))
            ->when(in_array('registration', $sources, true), fn ($q) => $q->orWhere(fn ($q) => $q
                ->whereNotNull('patient_registration_id')->where('type', '!=', Payment::TYPE_LAB)))
            // No source allowed: nothing.
            ->when($sources === [], fn ($q) => $q->whereRaw('1 = 0')));
    }

    public static function allows(?array $sources, Payment $payment): bool
    {
        return $sources === null || in_array($payment->source(), $sources, true);
    }
}
