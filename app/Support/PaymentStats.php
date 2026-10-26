<?php

namespace App\Support;

use App\Models\Payment;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\DB;

/**
 * Income figures for the payments page and its printed report
 * (2026-10-12, by request): today / this week / this month / this year,
 * plus the daily and monthly series behind the charts.
 *
 * The app stores times in UTC but the clinic's day runs on Baghdad time
 * (UTC+3, no daylight saving), so period boundaries are computed there
 * and dates are grouped after shifting by the same offset. The week
 * starts on Saturday, as it does in Iraq. Archived (soft-deleted)
 * patients' payments are always counted: they were really received.
 */
class PaymentStats
{
    public const TIMEZONE = 'Asia/Baghdad';

    private CarbonImmutable $now;

    private int $offsetMinutes;

    /**
     * @param  list<string>|null  $sources  the account's payments (see
     *                                      PaymentScope); null for all
     */
    public function __construct(?CarbonImmutable $now = null, private readonly ?array $sources = null)
    {
        $this->now = ($now ?? CarbonImmutable::now())->setTimezone(self::TIMEZONE);
        $this->offsetMinutes = $this->now->utcOffset();
    }

    /** Totals and counts for the four standard periods. */
    public function periods(): array
    {
        $starts = [
            'today' => $this->now->startOfDay(),
            'week' => $this->now->startOfWeek(CarbonImmutable::SATURDAY),
            'month' => $this->now->startOfMonth(),
            'year' => $this->now->startOfYear(),
        ];

        $out = [];
        foreach ($starts as $key => $start) {
            $row = PaymentScope::apply(Payment::query(), $this->sources)
                ->where('paid_at', '>=', $start->utc())
                ->selectRaw('COALESCE(SUM(amount), 0) as total, COUNT(*) as count')
                ->first();
            $out[$key] = [
                'total' => (float) $row->total,
                'count' => (int) $row->count,
                'from' => $start->toDateString(),
            ];
        }

        return $out;
    }

    /** One total per day for the last [$days] days, oldest first, zero-filled. */
    public function daily(int $days = 30): array
    {
        $start = $this->now->startOfDay()->subDays($days - 1);
        $totals = $this->groupedTotals($start, '%Y-%m-%d');

        $series = [];
        for ($d = $start; $d <= $this->now; $d = $d->addDay()) {
            $key = $d->toDateString();
            $series[] = ['key' => $key, 'label' => $d->format('m/d'), 'total' => $totals[$key] ?? 0.0];
        }

        return $series;
    }

    /** One total per month of the current year, January first, zero-filled. */
    public function monthly(): array
    {
        $start = $this->now->startOfYear();
        $totals = $this->groupedTotals($start, '%Y-%m');

        $series = [];
        for ($m = 1; $m <= 12; $m++) {
            $d = $start->month($m);
            $key = $d->format('Y-m');
            $series[] = ['key' => $key, 'label' => (string) $m, 'total' => $totals[$key] ?? 0.0];
        }

        return $series;
    }

    /** Total of a filtered payments query, by source (registration service, lab, appointment). */
    public static function bySource(Builder $query, ?array $sources = null): array
    {
        $rows = (clone $query)
            ->reorder()
            ->selectRaw("CASE WHEN type = ? THEN 'lab' WHEN appointment_id IS NOT NULL THEN 'appointment' ELSE 'registration' END as source", [Payment::TYPE_LAB])
            ->selectRaw('SUM(amount) as total, COUNT(*) as count')
            ->groupBy('source')
            ->get()
            ->keyBy('source');

        // Appointments dropped from payments (2026-10-14, by request).
        // Only the account's own sources (PaymentScope, 2026-10-26).
        return collect(['registration', 'lab'])
            ->filter(fn ($s) => $sources === null || in_array($s, $sources, true))
            ->values()
            ->map(fn ($s) => ['source' => $s, 'total' => (float) ($rows[$s]->total ?? 0), 'count' => (int) ($rows[$s]->count ?? 0)])
            ->all();
    }

    /** @return array<string, float> local date bucket => total */
    private function groupedTotals(CarbonImmutable $start, string $format): array
    {
        $bucket = "DATE_FORMAT(DATE_ADD(paid_at, INTERVAL {$this->offsetMinutes} MINUTE), '{$format}')";

        return PaymentScope::apply(Payment::query(), $this->sources)
            ->where('paid_at', '>=', $start->utc())
            ->selectRaw("{$bucket} as bucket, SUM(amount) as total")
            ->groupBy(DB::raw($bucket))
            ->pluck('total', 'bucket')
            ->map(fn ($v) => (float) $v)
            ->all();
    }
}
