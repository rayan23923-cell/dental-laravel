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

    /** Longest filtered period drawn as one bar per day. */
    public const MAX_RANGE_DAYS = 92;

    private CarbonImmutable $now;

    private int $offsetMinutes;

    /**
     * @param  list<string>|null  $sources  the account's payments (see
     *                                      PaymentScope); null for all
     */
    public function __construct(
        ?CarbonImmutable $now = null,
        private readonly ?array $sources = null,
        private readonly ?Builder $base = null,
    ) {
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
            $row = $this->query()
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

    /**
     * The payments page's date filter (2026-11-04, by request): with a
     * "from" and/or "to" date, the overview shows that period only — its
     * total, count, daily average and best day, a bar per day of it (up to
     * {@see self::MAX_RANGE_DAYS} days) and a bar per month when it spans
     * more than one month — instead of today / this week / this month /
     * this year. Only "to": from the first payment the filters match;
     * only "from": up to today. Null without a date filter.
     *
     * @return array{from: string, to: string, days: int, total: float, count: int, average: float, best: ?array, daily: list<array>, monthly: list<array>}|null
     */
    public function range(?string $from, ?string $to): ?array
    {
        $from = self::localDate($from);
        $to = self::localDate($to);
        if (! $from && ! $to) {
            return null;
        }

        $today = $this->now->startOfDay();
        if (! $from) {
            $first = $this->query()->reorder()->min('paid_at');
            $from = $first
                ? CarbonImmutable::parse($first, 'UTC')->setTimezone(self::TIMEZONE)->startOfDay()
                : $to;
            $from = $from->greaterThan($to) ? $to : $from;
        }
        if (! $to) {
            $to = $from->greaterThan($today) ? $from : $today;
        }
        if ($from->greaterThan($to)) {
            [$from, $to] = [$to, $from];
        }

        $end = $to->addDay();
        $row = $this->query()->reorder()
            ->where('paid_at', '>=', $from->utc())
            ->where('paid_at', '<', $end->utc())
            ->selectRaw('COALESCE(SUM(amount), 0) as total, COUNT(*) as count')
            ->first();
        $total = (float) $row->total;
        $days = (int) $from->diffInDays($to) + 1;
        // The average counts the days that have already passed.
        $elapsed = $from->greaterThan($today) ? 1 : (int) $from->diffInDays($to->lessThan($today) ? $to : $today) + 1;

        $dayTotals = $this->groupedTotals($from, '%Y-%m-%d', $end);
        $daily = [];
        if ($days <= self::MAX_RANGE_DAYS) {
            for ($d = $from; $d <= $to; $d = $d->addDay()) {
                $key = $d->toDateString();
                $daily[] = ['key' => $key, 'label' => $d->format('m/d'), 'total' => $dayTotals[$key] ?? 0.0];
            }
        }

        $monthly = [];
        if ($from->format('Y-m') !== $to->format('Y-m')) {
            $monthTotals = $this->groupedTotals($from, '%Y-%m', $end);
            for ($m = $from->startOfMonth(); $m <= $to; $m = $m->addMonthNoOverflow()) {
                $key = $m->format('Y-m');
                $monthly[] = ['key' => $key, 'label' => $m->year === $to->year && $m->year === $from->year ? (string) $m->month : $m->format('m/y'), 'total' => $monthTotals[$key] ?? 0.0];
            }
        }

        $best = null;
        foreach ($dayTotals as $key => $value) {
            if ($value > 0 && ($best === null || $value > $best['total'])) {
                $best = ['date' => $key, 'total' => $value];
            }
        }

        return [
            'from' => $from->toDateString(),
            'to' => $to->toDateString(),
            'days' => $days,
            'total' => $total,
            'count' => (int) $row->count,
            'average' => round($total / max(1, $elapsed), 2),
            'best' => $best,
            'paid_days' => count(array_filter($dayTotals, fn ($v) => $v > 0)),
            'daily' => $daily,
            'monthly' => $monthly,
        ];
    }

    /**
     * Payments paid on [$from]..[$to] (yyyy-mm-dd) by the clinic's day,
     * Baghdad time (2026-11-04): a payment at 01:00 in Baghdad is stored
     * on the previous UTC date, so `whereDate()` would miss it.
     */
    public static function applyDateRange(Builder $query, ?string $from, ?string $to): Builder
    {
        $from = self::localDate($from);
        $to = self::localDate($to);

        return $query
            ->when($from, fn ($q) => $q->where('paid_at', '>=', $from->utc()))
            ->when($to, fn ($q) => $q->where('paid_at', '<', $to->addDay()->utc()));
    }

    /** A yyyy-mm-dd date as the start of that day in Baghdad, or null. */
    private static function localDate(CarbonImmutable|string|null $date): ?CarbonImmutable
    {
        if ($date instanceof CarbonImmutable) {
            return $date;
        }
        if (! is_string($date) || ! preg_match('/^\d{4}-\d{2}-\d{2}$/', $date)) {
            return null;
        }
        try {
            return CarbonImmutable::createFromFormat('!Y-m-d', $date, self::TIMEZONE);
        } catch (\Throwable) {
            return null;
        }
    }

    /** The payments counted: the page's filtered query, or the account's own. */
    private function query(): Builder
    {
        return $this->base ? (clone $this->base)->withoutEagerLoads()->reorder() : PaymentScope::apply(Payment::query(), $this->sources);
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
    private function groupedTotals(CarbonImmutable $start, string $format, ?CarbonImmutable $end = null): array
    {
        $bucket = "DATE_FORMAT(DATE_ADD(paid_at, INTERVAL {$this->offsetMinutes} MINUTE), '{$format}')";

        return $this->query()
            ->where('paid_at', '>=', $start->utc())
            ->when($end, fn ($q) => $q->where('paid_at', '<', $end->utc()))
            ->selectRaw("{$bucket} as bucket, SUM(amount) as total")
            ->groupBy(DB::raw($bucket))
            ->pluck('total', 'bucket')
            ->map(fn ($v) => (float) $v)
            ->all();
    }
}
