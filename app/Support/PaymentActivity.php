<?php

namespace App\Support;

use App\Models\ActivityLog;
use App\Models\Payment;
use Carbon\CarbonInterface;
use Illuminate\Support\Collection;

/**
 * The payments activity log (2026-11-01, by request): who added, changed
 * or deleted which payment and when. Shared by the printed web page and,
 * since 2026-11-04 (by request), the app's PDF (Api\PaymentController::activity()).
 * Older entries without a snapshot show what is still known of the payment.
 */
class PaymentActivity
{
    public static function rows(?CarbonInterface $from, ?CarbonInterface $to): Collection
    {
        $logs = ActivityLog::query()
            ->where('module', 'Payment')
            ->when($from, fn ($q) => $q->whereDate('created_at', '>=', $from))
            ->when($to, fn ($q) => $q->whereDate('created_at', '<=', $to))
            ->latest('created_at')
            ->limit(2000)
            ->get();

        $current = Payment::with(['appointment', 'patientRegistration'])
            ->whereIn('id', $logs->pluck('record_id')->filter()->unique())
            ->get()->keyBy('id');

        return $logs->map(function (ActivityLog $log) use ($current) {
            $data = $log->data ? json_decode($log->data, true) : null;
            $snapshot = $data['snapshot'] ?? $current->get($log->record_id)?->activitySnapshot();

            return [
                'at' => $log->created_at,
                'user' => $log->username,
                'role' => $log->user_role,
                'action' => $log->action,
                'payment_id' => $log->record_id,
                'snapshot' => $snapshot,
                'before' => $data['before'] ?? null,
                'changes' => $data['changes'] ?? ($log->action === 'update' && is_array($data) ? $data : null),
            ];
        });
    }
}
