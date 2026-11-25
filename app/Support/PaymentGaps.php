<?php

namespace App\Support;

use App\Models\ActivityLog;
use App\Models\Payment;
use Illuminate\Support\Collection;

/**
 * The missing numbers in the printed payments report (2026-11-25, by
 * request): every payment id between the report's first and last one that
 * the report doesn't list, with what is known of it, so a gap such as 1401
 * between 1400 and 1402 is shown and explained.
 *
 * A missing id is one of:
 *  - `outside`: the payment exists but the report's filters leave it out
 *    (another source, search, stage...). Its details are shown only when
 *    the account may see its source (PaymentScope).
 *  - `deleted`: the payment was deleted; the activity log says who and
 *    when, and what it was.
 *  - `unknown`: no payment and no log entry (deleted before the log kept
 *    payments, or a number the database skipped).
 */
class PaymentGaps
{
    /** Beyond this many missing ids the report lists none of them inline. */
    public const LIMIT = 1000;

    /**
     * @param  Collection<int, Payment>  $payments  the report's payments, in print order
     * @return array{after: array<int, list<array>>, count: int, counts: array<string, int>, truncated: bool}
     *               `after[i]` are the missing ids printed after row i (-1: before the first row)
     */
    public static function for(Collection $payments, ?array $sources): array
    {
        $empty = ['after' => [], 'count' => 0, 'counts' => [], 'truncated' => false];
        $ids = $payments->pluck('id')->map(fn ($id) => (int) $id)->sort()->values();
        if ($ids->count() < 2) {
            return $empty;
        }

        $present = array_flip($ids->all());
        $missing = [];
        for ($id = $ids->first() + 1; $id < $ids->last(); $id++) {
            if (! isset($present[$id])) {
                $missing[] = $id;
            }
        }
        if ($missing === []) {
            return $empty;
        }
        if (count($missing) > self::LIMIT) {
            return ['after' => [], 'count' => count($missing), 'counts' => [], 'truncated' => true];
        }

        $existing = Payment::with(['appointment', 'patientRegistration'])->whereIn('id', $missing)->get()->keyBy('id');
        $deletions = ActivityLog::query()
            ->where('module', 'Payment')->where('action', 'delete')
            ->whereIn('record_id', $missing)
            ->latest('created_at')->get()
            ->unique('record_id')->keyBy('record_id');

        // Each missing id goes after the listed payment with the largest id
        // below it, so with the report in date order it sits next to its
        // neighbours.
        $rowOf = [];
        foreach ($payments->values() as $i => $p) {
            $rowOf[(int) $p->id] = $i;
        }
        $after = [];
        $counts = ['outside' => 0, 'deleted' => 0, 'unknown' => 0];
        $cursor = 0;
        $sorted = $ids->all();
        foreach ($missing as $id) {
            while ($cursor + 1 < count($sorted) && $sorted[$cursor + 1] < $id) {
                $cursor++;
            }
            $row = self::describe($id, $existing->get($id), $deletions->get($id), $sources);
            $counts[$row['status']]++;
            $after[$rowOf[$sorted[$cursor]]][] = $row;
        }

        return ['after' => $after, 'count' => count($missing), 'counts' => array_filter($counts), 'truncated' => false];
    }

    private static function describe(int $id, ?Payment $payment, ?ActivityLog $deletion, ?array $sources): array
    {
        if ($payment) {
            $visible = PaymentScope::allows($sources, $payment);

            return [
                'id' => $id,
                'status' => 'outside',
                'source' => $payment->source(),
                'details' => $visible ? self::local($payment->activitySnapshot()) : null,
            ];
        }

        if ($deletion) {
            $data = $deletion->data ? json_decode($deletion->data, true) : null;
            $snapshot = $data['snapshot'] ?? null;
            $visible = $snapshot && ($sources === null || in_array($snapshot['source'] ?? null, $sources, true));

            return [
                'id' => $id,
                'status' => 'deleted',
                'source' => $snapshot['source'] ?? null,
                'details' => $visible ? self::local($snapshot) : null,
                'by' => $deletion->username,
                'at' => $deletion->created_at?->copy()->setTimezone(PaymentStats::TIMEZONE)->format('Y-m-d H:i'),
            ];
        }

        return ['id' => $id, 'status' => 'unknown', 'source' => null, 'details' => null];
    }

    /** A snapshot's payment time (UTC) in the clinic's time, as the report prints it. */
    private static function local(array $snapshot): array
    {
        if (! empty($snapshot['paid_at'])) {
            try {
                $snapshot['paid_at'] = \Carbon\Carbon::parse($snapshot['paid_at'], 'UTC')->setTimezone(PaymentStats::TIMEZONE)->format('Y-m-d H:i');
            } catch (\Throwable) {
                // Kept as logged.
            }
        }

        return $snapshot;
    }
}
